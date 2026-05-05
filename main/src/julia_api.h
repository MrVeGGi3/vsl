#pragma once
#include <cstdint>

// C interface to the VSL Julia solver.
//
// Phase 2: implemented in julia_solver.cpp via Julia embedding API (jl_call*).
//          jl_init() must have been called on this thread before any call.
//
// Phase 3: replaced by @ccallable symbols compiled into a PackageCompiler
//          sysimage. The function signatures below will remain identical.

extern "C" {

    // Load VSLSolver module. Call once after jl_init().
    // sysimage_path: path to PackageCompiler sysimage (Phase 3) or "" for bare Julia.
    // Returns 0 = ok, -1 = error.
    int vsl_solver_init(const char* sysimage_path);

    // Release Julia resources. Call before jl_atexit_hook().
    void vsl_solver_shutdown();

    // Propagate a TLE for duration_s seconds.
    // out_positions: caller-allocated Float32[] x,y,z interleaved (km).
    // out_count:     number of points written.
    int vsl_propagate_orbit(
        const char* tle_line1,
        const char* tle_line2,
        double      duration_s,
        double      step_s,
        float*      out_positions,
        int*        out_count
    );

    // Compute ground-station access windows.
    int vsl_compute_access(
        const char* tle_line1,
        const char* tle_line2,
        double      gs_lat_deg,
        double      gs_lon_deg,
        double      gs_min_elevation_deg,
        double      duration_s,
        double*     out_start_times,
        double*     out_end_times,
        int*        out_count,
        int         max_windows
    );

} // extern "C"
