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

static std::atomic<bool>      g_running{true};
static DoubleBuffer            g_orbit_buffer;
static TrajectoryDoubleBuffer  g_trajectory_buffer;

// ISS reference TLE — replaced by UI input in Phase 3
static constexpr const char* ISS_L1 =
    "1 25544U 98067A   24001.50000000  .00006000  00000-0  10000-3 0  9992";
static constexpr const char* ISS_L2 =
    "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49507896 12343";

// Demo rocket: N-class solid motor, 80 mm airframe, 1.2 m long.
// Launched from rest at ground level; motor fires at t=0.
// Simulates 120 s: burn (~3 s) + coast to apogee + start of descent.

// Thrust curve: simplified Cesaroni N-class (4-point approximation)
static constexpr double ROCKET_TC_TIMES[]  = {0.0, 0.1,    3.0,    3.05};  // s
static constexpr double ROCKET_TC_FORCES[] = {0.0, 2100.0, 1800.0, 0.0};   // N
static constexpr double ROCKET_TC_MDOTS[]  = {0.0, 0.60,   0.55,   0.0};   // kg/s
static constexpr double ROCKET_MASS_DRY    = 6.2;   // kg
static constexpr double ROCKET_MASS_WET    = 8.0;   // kg

// Aerodynamic table: mach=[0, 0.5, 1.5], aoa=[0, 5°, 10°] in radians
static constexpr double ROCKET_AERO_MACH[] = {0.0, 0.5, 1.5};
static constexpr double ROCKET_AERO_AOA[]  = {0.0, 0.0873, 0.1745};       // rad
static constexpr double ROCKET_AERO_CD[]   = {                             // row-major 3×3
    0.70, 0.70, 0.70,   // Mach 0.0
    0.55, 0.58, 0.65,   // Mach 0.5
    0.45, 0.48, 0.55,   // Mach 1.5
};
static constexpr double ROCKET_AERO_CN[]   = {
    0.0,  0.20, 0.40,
    0.0,  0.22, 0.44,
    0.0,  0.18, 0.36,
};
static constexpr double ROCKET_S_REF   = 0.00503;  // m²  (π × 0.04²)
static constexpr double ROCKET_XCP     = 0.85;     // m from nose — CP aft of CG → stable
static constexpr double ROCKET_XCG     = 0.55;     // m from nose
static constexpr double ROCKET_TEND    = 120.0;    // s simulation duration

// ── RAII — Julia runtime ──────────────────────────────────────────────────────

struct JuliaRuntime {
    explicit JuliaRuntime(const char* sysimage) {
        if (sysimage && sysimage[0])
            jl_init_with_image(VSL_JULIA_BINDIR, sysimage);
        else
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

// ── Solver — trajectory ───────────────────────────────────────────────────────

static void solver_update_trajectory() {
    auto& buf = g_trajectory_buffer.back();

    VslThrustCurveData thrust{
        ROCKET_TC_TIMES, ROCKET_TC_FORCES, ROCKET_TC_MDOTS,
        ROCKET_MASS_DRY, ROCKET_MASS_WET,
        4,  // n_points
    };
    VslAeroTableData aero{
        ROCKET_AERO_MACH, ROCKET_AERO_AOA, ROCKET_AERO_CD, ROCKET_AERO_CN,
        ROCKET_S_REF, ROCKET_XCP, ROCKET_XCG,
        3, 3,  // n_mach, n_aoa
    };

    int rc = vsl_trajectory_sixdof_points(
        0.0, 0.0, 0.0,          // position — launch from pad (ground level)
        0.0, 0.0, 0.0,          // velocity — at rest (motor fires at t=0)
        1.0, 0.0, 0.0, 0.0,    // quaternion — vertical, no rotation
        0.0, 0.0, 0.0,          // angular rate — zero
        &thrust, &aero, 1,      // propulsion, aerodynamics, use NRLMSISE-00
        ROCKET_TEND,
        buf.final_state, &buf.apogee_m,
        buf.times.data(), buf.positions.data(), &buf.point_count,
        MAX_TRAJ_POINTS
    );

    if (rc == 0) {
        buf.valid = 1;
        buf.frame_id++;
        g_trajectory_buffer.swap();
        std::fprintf(stderr, "[vsl] trajectory: apogee %.0f m, %d pts\n",
                     buf.apogee_m, buf.point_count);
    } else {
        std::fprintf(stderr, "[vsl] vsl_trajectory_sixdof_points error: %d\n", rc);
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
    std::fprintf(f, "],\n");

    auto& trj = g_trajectory_buffer.front();
    std::fprintf(f, "  \"trajectory_apogee_m\": %.1f,\n", trj.apogee_m);
    std::fprintf(f, "  \"trajectory_point_count\": %d,\n", trj.point_count);
    std::fprintf(f, "  \"trajectory_final_state\": [");
    for (int i = 0; i < 13; ++i) {
        if (i > 0) std::fputc(',', f);
        std::fprintf(f, "%.6f", trj.final_state[i]);
    }
    std::fprintf(f, "],\n");

    std::fprintf(f, "  \"trajectory_times\": [");
    for (int i = 0; i < trj.point_count; ++i) {
        if (i > 0) std::fputc(',', f);
        std::fprintf(f, "%.3f", (double)trj.times[i]);
    }
    std::fprintf(f, "],\n");

    std::fprintf(f, "  \"trajectory_positions_flat\": [");
    for (int i = 0; i < trj.point_count * 3; ++i) {
        if (i > 0) std::fputc(',', f);
        std::fprintf(f, "%.2f", (double)trj.positions[i]);
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

    // 2. Pre-populate buffers and run full analysis before first frame
    solver_update_orbit();
    solver_update_trajectory();
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
