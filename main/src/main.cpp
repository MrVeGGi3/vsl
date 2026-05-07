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

    // 2. Pre-populate orbit buffer before first frame
    solver_update_orbit();

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
