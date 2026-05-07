#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <string>

#include <julia.h>

#include "double_buffer.h"
#include "godot_bridge.h"
#include "julia_api.h"

// ── Globals ───────────────────────────────────────────────────────────────────

static std::atomic<bool> g_running{true};
static DoubleBuffer       g_orbit_buffer;

// ISS reference TLE — replaced by UI input in Phase 3
static constexpr const char* ISS_L1 =
    "1 25544U 98067A   24001.50000000  .00006000  00000-0  10000-3 0  9992";
static constexpr const char* ISS_L2 =
    "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49507896 12343";

// ── RAII — Julia runtime ──────────────────────────────────────────────────────

struct JuliaRuntime {
    explicit JuliaRuntime(const char* sysimage) {
        jl_init();
        if (vsl_solver_init(sysimage) != 0)
            std::fprintf(stderr,
                "[vsl] WARNING: vsl_solver_init failed\n");
    }
    ~JuliaRuntime() {
        vsl_solver_shutdown();
        jl_atexit_hook(0);
    }
    JuliaRuntime(const JuliaRuntime&)            = delete;
    JuliaRuntime& operator=(const JuliaRuntime&) = delete;
};

// ── Solver — runs on main thread (jl_init constraint) ────────────────────────
//
// Julia API calls must happen on the thread that called jl_init().
// Phase 2: solver runs synchronously on the main thread between Godot frames.
// Phase 3: move to async dispatch via libuv/jl_task_t so Godot never stalls.

static void solver_update_orbit() {
    auto& buf   = g_orbit_buffer.back();
    int   count = 0;

    int rc = vsl_propagate_orbit(
        ISS_L1, ISS_L2,
        5400.0,             // 90 min — one full orbit
        10.0,               // 10 s step → 540 points
        buf.positions.data(),
        &count
    );

    if (rc == 0) {
        buf.point_count = count;
        buf.frame_id++;
        g_orbit_buffer.swap();
    } else {
        std::fprintf(stderr, "[vsl] vsl_propagate_orbit error: %d\n", rc);
    }
}

// ── Solver JSON export ────────────────────────────────────────────────────────
//
// Writes solver_results.json into the Godot project directory so GDScript
// (SolverBridge) can read orbit, eclipse, and access data on startup.

static void write_solver_json(const char* project_path) {
    auto& buf       = g_orbit_buffer.front();
    const float* pos = buf.positions.data();
    int           n  = buf.point_count;
    if (n <= 0) {
        std::fprintf(stderr, "[vsl] write_solver_json: no orbit data\n");
        return;
    }

    VslEclipseResult ecl{};
    if (vsl_compute_eclipse(ISS_L1, ISS_L2, 86400.0, &ecl) != 0)
        std::fprintf(stderr, "[vsl] write_solver_json: eclipse failed\n");

    VslAccessWindow wins[64]{};
    int nwins = 0;
    vsl_compute_access(ISS_L1, ISS_L2, -15.78, -47.93, 5.0, 86400.0, wins, &nwins, 64);

    VslManeuverResult hohmann{};
    float x0 = pos[0], y0 = pos[1], z0 = pos[2];
    float r1_km = std::sqrt(x0*x0 + y0*y0 + z0*z0);
    vsl_compute_hohmann((double)r1_km, 6371.0 + 600.0, &hohmann);

    float alt_km      = r1_km - 6371.0f;
    float incl_deg    = (float)std::atof(ISS_L2 + 8);
    float mm_rev_day  = (float)std::atof(ISS_L2 + 52);
    float period_s    = (mm_rev_day > 0.0f) ? 86400.0f / mm_rev_day : 0.0f;

    std::string path = std::string(project_path) + "/solver_results.json";
    FILE* f = std::fopen(path.c_str(), "w");
    if (!f) {
        std::fprintf(stderr, "[vsl] Cannot write %s\n", path.c_str());
        return;
    }

    std::fprintf(f, "{\n");
    std::fprintf(f, "  \"orbit_step_s\": 10.0,\n");
    std::fprintf(f, "  \"point_count\": %d,\n", n);
    std::fprintf(f, "  \"altitude_km\": %.1f,\n", (double)alt_km);
    std::fprintf(f, "  \"inclination_deg\": %.4f,\n", (double)incl_deg);
    std::fprintf(f, "  \"orbit_period_s\": %.2f,\n", (double)period_s);
    std::fprintf(f, "  \"eclipse_fraction\": %.4f,\n", (double)ecl.fraction);
    std::fprintf(f, "  \"eclipse_n_periods\": %d,\n", ecl.n_periods);

    std::fprintf(f, "  \"eclipse_period_starts\": [");
    for (int i = 0; i < ecl.n_periods; ++i) {
        if (i > 0) std::fputc(',', f);
        std::fprintf(f, "%.2f", ecl.period_starts[i]);
    }
    std::fprintf(f, "],\n  \"eclipse_period_ends\": [");
    for (int i = 0; i < ecl.n_periods; ++i) {
        if (i > 0) std::fputc(',', f);
        std::fprintf(f, "%.2f", ecl.period_ends[i]);
    }
    std::fprintf(f, "],\n");

    std::fprintf(f, "  \"access_windows\": [");
    for (int i = 0; i < nwins; ++i) {
        if (i > 0) std::fputc(',', f);
        std::fprintf(f, "{\"t_start_s\":%.2f,\"t_end_s\":%.2f,\"max_elev_deg\":%.2f}",
                     wins[i].t_start_s, wins[i].t_end_s, (double)wins[i].max_elev_deg);
    }
    std::fprintf(f, "],\n");

    std::fprintf(f, "  \"hohmann_dv1_kms\": %.4f,\n", (double)hohmann.dv1_kms);
    std::fprintf(f, "  \"hohmann_dv2_kms\": %.4f,\n", (double)hohmann.dv2_kms);
    std::fprintf(f, "  \"hohmann_tof_s\": %.1f,\n",   (double)hohmann.tof_s);

    std::fprintf(f, "  \"positions_flat\": [");
    for (int i = 0; i < n * 3; ++i) {
        if (i > 0) std::fputc(',', f);
        std::fprintf(f, "%.3f", (double)pos[i]);
    }
    std::fprintf(f, "]\n}\n");

    std::fclose(f);
    std::fprintf(stderr, "[vsl] solver_results.json → %s (%d pts, %d wins)\n",
                 path.c_str(), n, nwins);
}

// ── Signal handler ────────────────────────────────────────────────────────────

static void on_signal(int) { g_running.store(false, std::memory_order_relaxed); }

// ── Entry point ───────────────────────────────────────────────────────────────

int main(int argc, char* argv[]) {
    std::signal(SIGINT,  on_signal);
    std::signal(SIGTERM, on_signal);

    const char* sysimage     = (argc > 1) ? argv[1] : "";
    const char* project_path = (argc > 2) ? argv[2]
        : "../godot/project";  // default relative path from build/

    // 1. Initialize Julia on main thread
    JuliaRuntime julia{sysimage};

    // 2. Pre-populate orbit buffer and run full analysis before first frame
    solver_update_orbit();
    write_solver_json(project_path);

    // 3. Initialize LibGodot
    auto godot = godot_init(project_path);
    if (!godot.success) {
        std::fprintf(stderr, "[vsl] LibGodot init failed: %s\n",
            godot.error_message.c_str());
        return 1;
    }

    // 4. Render loop — solver refreshes orbit every 60 frames (~1 Hz at 60 fps)
    int frame = 0;
    while (g_running.load(std::memory_order_relaxed)) {
        if (!godot_iterate()) {
            g_running.store(false, std::memory_order_relaxed);
            break;
        }
        if (++frame % 60 == 0)
            solver_update_orbit();
    }

    // 5. Ordered cleanup (JuliaRuntime destructor handles Julia)
    godot_shutdown();
    return 0;
}
