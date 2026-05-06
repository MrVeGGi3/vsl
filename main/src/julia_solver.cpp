#include "julia_api.h"

#include <climits>
#include <cstdio>
#include <cstring>
#include <string>
#include <unistd.h>

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

// Resolve the absolute path to the solver/ directory, relative to the binary.
// Binary lives at  .../vsl/main/<build>/vsl_main
// Solver lives at  .../vsl/solver/
static std::string solver_abs_path() {
    char exe_buf[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", exe_buf, PATH_MAX - 1);
    if (len < 0) return "";
    exe_buf[len] = '\0';
    std::string build_dir(exe_buf);
    build_dir = build_dir.substr(0, build_dir.rfind('/'));
    return build_dir + "/../../solver";
}

// ── Public C API ──────────────────────────────────────────────────────────────

extern "C" {

int vsl_solver_init(const char* sysimage_path) {
    (void)sysimage_path;  // Phase 3+: load PackageCompiler sysimage here

    std::string solver_path = solver_abs_path();
    if (solver_path.empty()) {
        std::fprintf(stderr, "[vsl] cannot resolve solver path\n");
        return -1;
    }

    char cmd[2048];
    std::snprintf(cmd, sizeof(cmd),
        "import Pkg; Pkg.activate(abspath(\"%s\"), io=devnull)",
        solver_path.c_str());
    jl_eval_string(cmd);
    if (check_julia_error("Pkg.activate")) return -1;

    jl_eval_string("using VSLSolver");
    if (check_julia_error("using VSLSolver")) return -1;

    jl_eval_string("using SatelliteToolboxTle");
    if (check_julia_error("using SatelliteToolboxTle")) return -1;

    jl_eval_string("using Dates");
    if (check_julia_error("using Dates")) return -1;

    g_module = (jl_module_t*)jl_eval_string("VSLSolver");
    if (check_julia_error("get VSLSolver module") || !g_module) return -1;

    g_fn_propagate = jl_get_function(g_module, "propagate_orbit");
    if (!g_fn_propagate) {
        std::fprintf(stderr, "[vsl] propagate_orbit not found in VSLSolver\n");
        return -1;
    }

    // Julia 1.12 requires globals to be declared before jl_set_global can write them
    // (binding check re-introduced after being accidentally removed in 1.9–1.10, issue #56933).
    jl_eval_string("global _vsl_l1 = \"\"; global _vsl_l2 = \"\"");
    if (check_julia_error("declare TLE globals")) return -1;
    jl_eval_string("global _vsl_t = Float64[]; global _vsl_pos = VSLSolver.Vec3[]; global _vsl_jd = 0.0");
    if (check_julia_error("declare propagation globals")) return -1;

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

    char call_buf[512];
    std::snprintf(call_buf, sizeof(call_buf),
        "let r = VSLSolver.propagate_orbit("
        "SatelliteToolboxTle.read_tle(\"%s\", \"%s\"), "
        "%.1f; step_s=%.1f); r end",
        tle_line1, tle_line2, duration_s, step_s);

    jl_value_t* result = jl_eval_string(call_buf);
    if (check_julia_error("propagate_orbit") || !result) return -1;

    jl_function_t* getindex = jl_get_function(jl_base_module, "getindex");
    jl_value_t* positions   = jl_call2(getindex, result, jl_box_int64(2));
    if (check_julia_error("getindex positions") || !positions) return -1;

    jl_function_t* length_fn = jl_get_function(jl_base_module, "length");
    int n = (int)jl_unbox_int64(jl_call1(length_fn, positions));
    *out_count = n;

    for (int i = 0; i < n; ++i) {
        jl_value_t* idx = jl_box_int64(i + 1);
        jl_value_t* vec = jl_call2(getindex, positions, idx);
        if (check_julia_error("getindex vec")) return -1;

        auto x = (float)jl_unbox_float64(jl_call2(getindex, vec, jl_box_int64(1)));
        auto y = (float)jl_unbox_float64(jl_call2(getindex, vec, jl_box_int64(2)));
        auto z = (float)jl_unbox_float64(jl_call2(getindex, vec, jl_box_int64(3)));

        out_positions[i * 3 + 0] = x;
        out_positions[i * 3 + 1] = y;
        out_positions[i * 3 + 2] = z;
    }

    return 0;
}

// Helper: load a TLE and compute its Julian epoch date into a Julia variable pair.
// Sets Main._vsl_t, Main._vsl_pos, Main._vsl_jd via Julia-level global assignment.
static int _jl_propagate_tle(const char* l1, const char* l2, double dur_s) {
    // jl_set_global requires the binding to pre-exist in Julia 1.12 (issue #56933).
    // Use jl_eval_string for top-level assignment — TLE format has no quotes/backslashes.
    char set_l1[128], set_l2[128];
    std::snprintf(set_l1, sizeof(set_l1), "_vsl_l1 = \"%s\"", l1);
    std::snprintf(set_l2, sizeof(set_l2), "_vsl_l2 = \"%s\"", l2);
    jl_eval_string(set_l1);
    if (check_julia_error("set _vsl_l1")) return -1;
    jl_eval_string(set_l2);
    if (check_julia_error("set _vsl_l2")) return -1;

    char cmd[512];
    std::snprintf(cmd, sizeof(cmd),
        "let tle = SatelliteToolboxTle.read_tle(_vsl_l1, _vsl_l2),"
        "    jd  = VSLSolver._tle_jd(_vsl_l1),"
        "    (t, pos, _) = VSLSolver.propagate_orbit(tle, %.1f; step_s=30.0);"
        "    global _vsl_t=t; global _vsl_pos=pos; global _vsl_jd=jd; nothing\n"
        "end", dur_s);

    jl_eval_string(cmd);
    return check_julia_error("_jl_propagate_tle") ? -1 : 0;
}

int vsl_compute_eclipse(
    const char*       tle_line1,
    const char*       tle_line2,
    double            duration_s,
    VslEclipseResult* out
) {
    if (!g_initialized) return -1;
    if (_jl_propagate_tle(tle_line1, tle_line2, duration_s) != 0) return -1;

    jl_value_t* result = jl_eval_string(
        "VSLSolver.eclipse_fraction(_vsl_pos, _vsl_t, _vsl_jd)");
    if (check_julia_error("vsl_compute_eclipse") || !result) return -1;

    out->fraction  = (float)jl_unbox_float64(result);
    out->n_periods = 0;  // period-by-period detail not yet exposed
    return 0;
}

int vsl_compute_access(
    const char*      tle_line1,
    const char*      tle_line2,
    double           gs_lat_deg,
    double           gs_lon_deg,
    double           gs_min_elev_deg,
    double           duration_s,
    VslAccessWindow* out_windows,
    int*             out_count,
    int              max_windows
) {
    if (!g_initialized) return -1;
    if (_jl_propagate_tle(tle_line1, tle_line2, duration_s) != 0) return -1;

    char cmd[256];
    std::snprintf(cmd, sizeof(cmd),
        "VSLSolver.access_windows(_vsl_pos, _vsl_t, %.6f, %.6f, _vsl_jd;"
        "    min_elev_deg=%.2f)",
        gs_lat_deg, gs_lon_deg, gs_min_elev_deg);

    jl_value_t* wins_jl = jl_eval_string(cmd);
    if (check_julia_error("vsl_compute_access") || !wins_jl) return -1;

    jl_function_t* length_fn = jl_get_function(jl_base_module, "length");
    jl_function_t* getindex  = jl_get_function(jl_base_module, "getindex");

    int n = (int)jl_unbox_int64(jl_call1(length_fn, wins_jl));
    n = (n < max_windows) ? n : max_windows;
    *out_count = n;

    for (int i = 0; i < n; ++i) {
        jl_value_t* win = jl_call2(getindex, wins_jl, jl_box_int64(i + 1));
        if (check_julia_error("getindex win")) return -1;

        auto ts  = jl_unbox_float64(jl_call2(getindex, win, jl_box_int64(1)));
        auto te  = jl_unbox_float64(jl_call2(getindex, win, jl_box_int64(2)));
        auto el  = (float)jl_unbox_float64(jl_call2(getindex, win, jl_box_int64(3)));

        out_windows[i] = {ts, te, el};
    }

    return 0;
}

int vsl_compute_hohmann(
    double             r1_km,
    double             r2_km,
    VslManeuverResult* out
) {
    if (!g_initialized) return -1;

    char cmd[256];
    std::snprintf(cmd, sizeof(cmd),
        "VSLSolver.hohmann_transfer(%.6f, %.6f)", r1_km, r2_km);

    jl_value_t* result = jl_eval_string(cmd);
    if (check_julia_error("vsl_compute_hohmann") || !result) return -1;

    jl_function_t* getindex = jl_get_function(jl_base_module, "getindex");
    out->dv1_kms = (float)jl_unbox_float64(jl_call2(getindex, result, jl_box_int64(1)));
    out->dv2_kms = (float)jl_unbox_float64(jl_call2(getindex, result, jl_box_int64(2)));
    out->tof_s   = (float)jl_unbox_float64(jl_call2(getindex, result, jl_box_int64(3)));

    return 0;
}

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
) {
    if (!g_initialized) return -1;

    char set_l1[128], set_l2[128];
    std::snprintf(set_l1, sizeof(set_l1), "_vsl_l1 = \"%s\"", tle_line1);
    std::snprintf(set_l2, sizeof(set_l2), "_vsl_l2 = \"%s\"", tle_line2);
    jl_eval_string(set_l1);
    if (check_julia_error("set _vsl_l1 (report)")) return -1;
    jl_eval_string(set_l2);
    if (check_julia_error("set _vsl_l2 (report)")) return -1;

    char cmd[512];
    std::snprintf(cmd, sizeof(cmd),
        "let r = VSLSolver.mission_report(_vsl_l1, _vsl_l2;"
        "    gs_lat=%.6f, gs_lon=%.6f, gs_min_elev=%.2f,"
        "    target_alt_km=%.2f, duration_s=%.1f);"
        "    VSLSolver.to_json(r)"
        "end",
        gs_lat_deg, gs_lon_deg, gs_min_elev_deg,
        target_alt_km, duration_s);

    jl_value_t* result = jl_eval_string(cmd);
    if (check_julia_error("vsl_generate_report_json") || !result) return -1;

    const char* json_str = jl_string_ptr(result);
    std::strncpy(out_json, json_str, out_json_maxlen - 1);
    out_json[out_json_maxlen - 1] = '\0';

    return 0;
}

} // extern "C"
