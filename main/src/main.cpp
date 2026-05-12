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
#include "mission_params.h"
#include "mission_params_loader.h"

// ── Globals ───────────────────────────────────────────────────────────────────

static std::atomic<bool>      g_running{true};
static DoubleBuffer            g_orbit_buffer;
static TrajectoryDoubleBuffer  g_trajectory_buffer;

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

// ── Solver — orbital propagation ─────────────────────────────────────────────

static void solver_update_orbit(const VslMissionParams& mp) {
    auto& buf   = g_orbit_buffer.back();
    int   count = 0;

    int rc = vsl_propagate_orbit(
        mp.orbital.tle_line1.c_str(),
        mp.orbital.tle_line2.c_str(),
        mp.orbital.analysis_duration_s > 5400.0 ? 5400.0 : mp.orbital.analysis_duration_s,
        mp.orbital.orbit_step_s,
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

// ── Solver — 6-DOF trajectory ─────────────────────────────────────────────────

static void solver_update_trajectory(const VslMissionParams& mp) {
    auto& buf = g_trajectory_buffer.back();

    VslThrustCurveData thrust = make_thrust_curve(mp);
    VslAeroTableData   aero   = make_aero_table(mp);
    const auto& ic = mp.simulation;

    int rc = vsl_trajectory_sixdof_points(
        ic.pos_enu_m[0],     ic.pos_enu_m[1],     ic.pos_enu_m[2],
        ic.vel_enu_mps[0],   ic.vel_enu_mps[1],   ic.vel_enu_mps[2],
        ic.quat_body2enu[0], ic.quat_body2enu[1],
        ic.quat_body2enu[2], ic.quat_body2enu[3],
        ic.ang_rate_rad_s[0], ic.ang_rate_rad_s[1], ic.ang_rate_rad_s[2],
        &thrust, &aero,
        mp.atmosphere.use_nrlmsise ? 1 : 0,
        ic.t_end_s,
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

// ── JSON export ───────────────────────────────────────────────────────────────

static void write_solver_json(const char* project_path, const VslMissionParams& mp) {
    auto& buf       = g_orbit_buffer.front();
    const float* pos = buf.positions.data();
    int           n  = buf.point_count;
    if (n <= 0) {
        std::fprintf(stderr, "[vsl] write_solver_json: no orbit data\n");
        return;
    }

    VslEclipseResult ecl{};
    if (vsl_compute_eclipse(
            mp.orbital.tle_line1.c_str(),
            mp.orbital.tle_line2.c_str(),
            86400.0, &ecl) != 0)
        std::fprintf(stderr, "[vsl] write_solver_json: eclipse failed\n");

    VslAccessWindow wins[64]{};
    int nwins = 0;
    vsl_compute_access(
        mp.orbital.tle_line1.c_str(),
        mp.orbital.tle_line2.c_str(),
        mp.ground_station.lat_deg,
        mp.ground_station.lon_deg,
        mp.ground_station.min_elev_deg,
        86400.0, wins, &nwins, 64);

    VslManeuverResult hohmann{};
    float x0 = pos[0], y0 = pos[1], z0 = pos[2];
    float r1_km = std::sqrt(x0*x0 + y0*y0 + z0*z0);
    vsl_compute_hohmann((double)r1_km, 6371.0 + mp.orbital.target_alt_km, &hohmann);

    float alt_km   = r1_km - 6371.0f;
    float incl_deg = (float)std::atof(mp.orbital.tle_line2.c_str() + 8);
    float mm_rev   = (float)std::atof(mp.orbital.tle_line2.c_str() + 52);
    float period_s = (mm_rev > 0.0f) ? 86400.0f / mm_rev : 0.0f;

    std::string path = std::string(project_path) + "/solver_results.json";
    FILE* f = std::fopen(path.c_str(), "w");
    if (!f) {
        std::fprintf(stderr, "[vsl] Cannot write %s\n", path.c_str());
        return;
    }

    std::fprintf(f, "{\n");
    std::fprintf(f, "  \"orbit_step_s\": %.1f,\n",        mp.orbital.orbit_step_s);
    std::fprintf(f, "  \"point_count\": %d,\n",            n);
    std::fprintf(f, "  \"altitude_km\": %.1f,\n",          (double)alt_km);
    std::fprintf(f, "  \"inclination_deg\": %.4f,\n",      (double)incl_deg);
    std::fprintf(f, "  \"orbit_period_s\": %.2f,\n",       (double)period_s);
    std::fprintf(f, "  \"eclipse_fraction\": %.4f,\n",     (double)ecl.fraction);
    std::fprintf(f, "  \"eclipse_n_periods\": %d,\n",      ecl.n_periods);

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
    std::fprintf(f, "  \"trajectory_apogee_m\": %.1f,\n",    trj.apogee_m);
    std::fprintf(f, "  \"trajectory_point_count\": %d,\n",   trj.point_count);
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
    const char* project_path = (argc > 2) ? argv[2] : "../godot/project";
    const char* params_path  = (argc > 3) ? argv[3] : nullptr;

    // Resolve mission_params.json: explicit arg or default in project dir
    std::string params_file = params_path
        ? std::string(params_path)
        : std::string(project_path) + "/mission_params.json";

    // 1. Load mission parameters (defaults stay if file missing)
    VslMissionParams mp;
    load_mission_params(params_file, mp);

    // 2. Initialize Julia on main thread
    JuliaRuntime julia{sysimage};

    // 3. Pre-populate buffers and run full analysis before first frame
    solver_update_orbit(mp);
    solver_update_trajectory(mp);
    write_solver_json(project_path, mp);

    // 4. Initialize LibGodot
    auto godot = godot_init(project_path);
    if (!godot.success) {
        std::fprintf(stderr, "[vsl] LibGodot init failed: %s\n",
            godot.error_message.c_str());
        return 1;
    }

    // 5. Render loop — solver refreshes orbit every 60 frames (~1 Hz at 60 fps)
    int frame = 0;
    while (g_running.load(std::memory_order_relaxed)) {
        if (!godot_iterate()) {
            g_running.store(false, std::memory_order_relaxed);
            break;
        }
        if (++frame % 60 == 0)
            solver_update_orbit(mp);
    }

    // 6. Ordered cleanup (JuliaRuntime destructor handles Julia)
    godot_shutdown();
    return 0;
}
