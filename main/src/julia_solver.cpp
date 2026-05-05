#include "julia_api.h"

#include <cstdio>
#include <cstring>
#include <string>

#include <julia.h>

// ── Internal state ────────────────────────────────────────────────────────────

static bool          g_initialized{false};
static jl_function_t* g_fn_propagate{nullptr};
static jl_module_t*   g_module{nullptr};

static bool check_julia_error(const char* context) {
    jl_value_t* exc = jl_exception_occurred();
    if (!exc) return false;
    jl_printf(jl_stderr_stream(), "[vsl] Julia error in %s: ", context);
    jl_call2(jl_get_function(jl_base_module, "showerror"),
              jl_stderr_obj(), exc);
    jl_printf(jl_stderr_stream(), "\n");
    jl_exception_clear();
    return true;
}

// ── Public C API ──────────────────────────────────────────────────────────────

extern "C" {

int vsl_solver_init(const char* sysimage_path) {
    // Phase 3: load PackageCompiler sysimage here.
    // Phase 2: activate the solver project and load the module.
    (void)sysimage_path;

    // Activate solver project so Julia finds VSLSolver without installing it.
    const char* activate_cmd =
        "import Pkg; Pkg.activate(joinpath(@__DIR__, "
        "\"../../../solver\"), io=devnull)";
    jl_eval_string(activate_cmd);
    if (check_julia_error("Pkg.activate")) return -1;

    jl_eval_string("using VSLSolver");
    if (check_julia_error("using VSLSolver")) return -1;

    g_module = (jl_module_t*)jl_eval_string("VSLSolver");
    if (check_julia_error("get VSLSolver module") || !g_module) return -1;

    g_fn_propagate = jl_get_function(g_module, "propagate_orbit");
    if (!g_fn_propagate) {
        std::fprintf(stderr, "[vsl] propagate_orbit not found in VSLSolver\n");
        return -1;
    }

    g_initialized = true;
    std::fprintf(stderr, "[vsl] VSLSolver loaded OK\n");
    return 0;
}

void vsl_solver_shutdown() {
    g_fn_propagate = nullptr;
    g_module       = nullptr;
    g_initialized  = false;
}

int vsl_propagate_orbit(
    const char* tle_line1,
    const char* tle_line2,
    double      duration_s,
    double      step_s,
    float*      out_positions,
    int*        out_count
) {
    if (!g_initialized || !g_fn_propagate) {
        std::fprintf(stderr, "[vsl] vsl_propagate_orbit: solver not initialized\n");
        return -1;
    }

    // read_tle(line1, line2)
    jl_function_t* read_tle = jl_get_function(
        (jl_module_t*)jl_eval_string("SatelliteToolboxTle"), "read_tle");
    if (!read_tle || check_julia_error("get read_tle")) return -1;

    jl_value_t* tle = jl_call2(read_tle,
        jl_cstr_to_string(tle_line1), jl_cstr_to_string(tle_line2));
    if (check_julia_error("read_tle") || !tle) return -1;

    // propagate_orbit(tle, duration_s; step_s=step_s)
    // Julia signature: propagate_orbit(tle, duration_s; step_s) -> (times, pos, vel)

    // Call with keyword arg via jl_call — use named tuple workaround
    // Simpler: use jl_eval_string to construct the call with literal args
    char call_buf[512];
    std::snprintf(call_buf, sizeof(call_buf),
        "let r = VSLSolver.propagate_orbit("
        "SatelliteToolboxTle.read_tle(\"%s\", \"%s\"), "
        "%.1f; step_s=%.1f); r end",
        tle_line1, tle_line2, duration_s, step_s);

    jl_value_t* result = jl_eval_string(call_buf);
    if (check_julia_error("propagate_orbit") || !result) return -1;

    // result is a Tuple{Vector{Float64}, Vector{Vec3}, Vector{Vec3}}
    // Extract positions (index 2, 1-based in Julia)
    jl_function_t* getindex = jl_get_function(jl_base_module, "getindex");
    jl_value_t* positions   = jl_call2(getindex, result, jl_box_int64(2));
    if (check_julia_error("getindex positions") || !positions) return -1;

    jl_function_t* length_fn = jl_get_function(jl_base_module, "length");
    int n = (int)jl_unbox_int64(jl_call1(length_fn, positions));
    *out_count = n;

    // Copy Vec3 elements into out_positions (Float32, x,y,z interleaved)
    jl_function_t* norm_fn = jl_get_function(
        (jl_module_t*)jl_eval_string("LinearAlgebra"), "norm");
    (void)norm_fn;

    for (int i = 0; i < n; ++i) {
        jl_value_t* idx = jl_box_int64(i + 1);  // Julia 1-indexed
        jl_value_t* vec = jl_call2(getindex, positions, idx);
        if (check_julia_error("getindex vec")) return -1;

        // Vec3 is an SVector{3,Float64} — access via getindex
        auto x = (float)jl_unbox_float64(jl_call2(getindex, vec, jl_box_int64(1)));
        auto y = (float)jl_unbox_float64(jl_call2(getindex, vec, jl_box_int64(2)));
        auto z = (float)jl_unbox_float64(jl_call2(getindex, vec, jl_box_int64(3)));

        out_positions[i * 3 + 0] = x;
        out_positions[i * 3 + 1] = y;
        out_positions[i * 3 + 2] = z;
    }

    return 0;
}

int vsl_compute_access(
    const char* /*tle_line1*/,
    const char* /*tle_line2*/,
    double      /*gs_lat_deg*/,
    double      /*gs_lon_deg*/,
    double      /*gs_min_elevation_deg*/,
    double      /*duration_s*/,
    double*     /*out_start_times*/,
    double*     /*out_end_times*/,
    int*        out_count,
    int         /*max_windows*/
) {
    // Phase 3 — placeholder
    *out_count = 0;
    return 0;
}

} // extern "C"
