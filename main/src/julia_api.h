#pragma once
#include <cstdint>

// C interface to the VSL Julia solver.
//
// Phase 2: call via jl_eval_string / Julia embedding API.
// Phase 3: heavy analysis functions also available here.
//
// All functions:
//   return 0 on success, -1 on error
//   write results into caller-allocated output buffers

struct VslAccessWindow {
    double t_start_s;     // seconds from TLE epoch
    double t_end_s;
    float  max_elev_deg;
};

struct VslEclipseResult {
    float  fraction;              // 0–1
    int    n_periods;
    double period_starts[64];     // seconds from epoch (up to 64 periods)
    double period_ends[64];
};

struct VslManeuverResult {
    float dv1_kms;
    float dv2_kms;
    float tof_s;
};

extern "C" {

    // Load VSLSolver module. Call once after jl_init().
    // sysimage_path: path to PackageCompiler sysimage (Phase 3+) or "" for bare Julia.
    int  vsl_solver_init(const char* sysimage_path);

    // Release Julia resources. Call before jl_atexit_hook().
    void vsl_solver_shutdown();

    // Propagate a TLE for duration_s seconds.
    // out_positions: caller-allocated Float32[] x,y,z interleaved (km), at least
    //   ceil(duration_s / step_s + 1) * 3 floats.
    // out_count: number of points written.
    int vsl_propagate_orbit(
        const char* tle_line1,
        const char* tle_line2,
        double      duration_s,
        double      step_s,
        float*      out_positions,
        int*        out_count
    );

    // Compute eclipse fraction over duration_s seconds.
    // Returns eclipse fraction in *out_fraction (0–1).
    int vsl_compute_eclipse(
        const char*        tle_line1,
        const char*        tle_line2,
        double             duration_s,
        VslEclipseResult*  out
    );

    // Compute ground-station access windows.
    // out_windows: caller-allocated array of at least max_windows elements.
    // out_count: number of windows written.
    int vsl_compute_access(
        const char*       tle_line1,
        const char*       tle_line2,
        double            gs_lat_deg,
        double            gs_lon_deg,
        double            gs_min_elev_deg,
        double            duration_s,
        VslAccessWindow*  out_windows,
        int*              out_count,
        int               max_windows
    );

    // Compute Hohmann transfer delta-v.
    int vsl_compute_hohmann(
        double             r1_km,
        double             r2_km,
        VslManeuverResult* out
    );

    // Generate full mission report as a JSON string.
    // out_json: caller-allocated buffer of out_json_maxlen bytes.
    int vsl_generate_report_json(
        const char* tle_line1,
        const char* tle_line2,
        double      gs_lat_deg,
        double      gs_lon_deg,
        double      gs_min_elev_deg,
        double      target_alt_km,
        double      duration_s,
        char*       out_json,
        int         out_json_maxlen
    );

} // extern "C"
