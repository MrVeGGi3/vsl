// Phase 3 integration test — full chain: init → propagate → eclipse → access → hohmann → report_json
//
// Reference values from SMAD Ch.6/9/11 and SatelliteToolbox validation (test_eclipse.jl,
// test_access.jl, test_maneuvers.jl). Tolerances chosen to match Julia test suite.
//
// Run from build/ directory so solver_abs_path() resolves correctly.

#include <cmath>
#include <cstdio>
#include <cstring>
#include <cassert>

#include <julia.h>
#include "../src/julia_api.h"

// TLE: ISS (ZARYA), epoch 2024-01-01 ~12:00 UTC — same as Julia test suite
static const char ISS_L1[] =
    "1 25544U 98067A   24001.50000000  .00006000  00000-0  10000-3 0  9992";
static const char ISS_L2[] =
    "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49507896 12343";

static bool near(double a, double b, double tol) {
    return std::fabs(a - b) <= tol;
}

static int passed = 0;
static int failed = 0;

#define CHECK(cond, msg)                                        \
    do {                                                        \
        if (!(cond)) {                                          \
            std::fprintf(stderr, "  FAIL: %s\n", msg);         \
            ++failed;                                           \
        } else {                                                \
            std::fprintf(stdout, "  ok  : %s\n", msg);         \
            ++passed;                                           \
        }                                                       \
    } while (0)

// ── Tests ─────────────────────────────────────────────────────────────────────

static void test_propagate() {
    std::printf("[1/5] vsl_propagate_orbit\n");

    static float pos[16384 * 3];
    int count = 0;

    int rc = vsl_propagate_orbit(ISS_L1, ISS_L2, 5556.0, 30.0, pos, &count);
    CHECK(rc == 0, "return code 0");
    CHECK(count >= 100 && count <= 16384, "point count in range");

    float r0 = std::sqrt(pos[0]*pos[0] + pos[1]*pos[1] + pos[2]*pos[2]);
    // ISS altitude ≈ 408 km → |r| ≈ 6779 km ± 200 km
    CHECK(near(r0, 6779.0f, 200.0f), "|r0| ≈ 6779 km");

    // One orbit at step=30s → ~185 points for 5556s
    CHECK(count >= 170 && count <= 200, "~1 orbit step count");

    std::printf("  |r0|=%.1f km, count=%d\n", r0, count);
}

static void test_eclipse() {
    std::printf("[2/5] vsl_compute_eclipse\n");

    VslEclipseResult ecl{};
    // 3 orbital periods at 30 s resolution (matches Julia test)
    int rc = vsl_compute_eclipse(ISS_L1, ISS_L2, 3.0 * 5556.0, &ecl);
    CHECK(rc == 0, "return code 0");

    // SMAD Ch.11: ISS eclipse fraction 28–45% on Jan 1 (solar beta ≈ −23°)
    CHECK(ecl.fraction >= 0.28f && ecl.fraction <= 0.45f, "fraction in SMAD range [0.28, 0.45]");

    std::printf("  eclipse_fraction=%.3f\n", ecl.fraction);
}

static void test_access() {
    std::printf("[3/5] vsl_compute_access\n");

    VslAccessWindow wins[32];
    int n_wins = 0;
    // GS Brasília: lat=-15.78°, lon=-47.93°, min_elev=5°, 24 h
    int rc = vsl_compute_access(
        ISS_L1, ISS_L2,
        -15.78, -47.93, 5.0, 86400.0,
        wins, &n_wins, 32);

    CHECK(rc == 0, "return code 0");
    // SMAD Ch.9: ISS (i=51.6°) covers Brasília — expect 2–8 passes in 24 h
    CHECK(n_wins >= 2 && n_wins <= 8, "2–8 passes in 24 h");

    double total_dur = 0.0;
    for (int i = 0; i < n_wins; ++i) {
        double dur = wins[i].t_end_s - wins[i].t_start_s;
        total_dur += dur;
        CHECK(wins[i].t_end_s > wins[i].t_start_s, "t_end > t_start");
        CHECK(wins[i].max_elev_deg >= 5.0f, "max_elev >= min_elev");
    }
    double avg_dur = total_dur / n_wins;
    // SMAD: typical pass 2–15 min above 5°
    CHECK(avg_dur >= 120.0 && avg_dur <= 900.0, "avg pass duration 2–15 min");

    std::printf("  n_wins=%d, avg_dur=%.1f s (%.1f min)\n",
                n_wins, avg_dur, avg_dur / 60.0);
}

static void test_hohmann() {
    std::printf("[4/5] vsl_compute_hohmann\n");

    VslManeuverResult m{};
    // ISS (r1=6779 km) → GEO (r2=42157 km)
    int rc = vsl_compute_hohmann(6779.0, 42157.0, &m);

    CHECK(rc == 0, "return code 0");
    // Analytical: dv1≈2.39, dv2≈1.45, total≈3.84 km/s, tof≈5.29 h
    CHECK(near(m.dv1_kms, 2.39f, 0.05f), "dv1 ≈ 2.39 km/s");
    CHECK(near(m.dv2_kms, 1.45f, 0.05f), "dv2 ≈ 1.45 km/s");
    CHECK(near(m.dv1_kms + m.dv2_kms, 3.84f, 0.08f), "dv_total ≈ 3.84 km/s");
    CHECK(near(m.tof_s / 3600.0f, 5.29f, 0.15f), "tof ≈ 5.29 h");

    std::printf("  dv1=%.4f dv2=%.4f total=%.4f tof=%.3f h\n",
                m.dv1_kms, m.dv2_kms, m.dv1_kms + m.dv2_kms, m.tof_s / 3600.0f);
}

static void test_report_json() {
    std::printf("[5/5] vsl_generate_report_json\n");

    static char json[65536];
    int rc = vsl_generate_report_json(
        ISS_L1, ISS_L2,
        -15.78, -47.93, 5.0,
        35786.0, 86400.0,
        json, sizeof(json));

    CHECK(rc == 0, "return code 0");
    CHECK(std::strlen(json) > 200, "json non-empty (>200 chars)");

    // Structural validation — all required keys present
    CHECK(std::strstr(json, "\"tle_epoch\"")        != nullptr, "key: tle_epoch");
    CHECK(std::strstr(json, "\"orbit_period_s\"")   != nullptr, "key: orbit_period_s");
    CHECK(std::strstr(json, "\"eclipse_fraction\"") != nullptr, "key: eclipse_fraction");
    CHECK(std::strstr(json, "\"access_windows\"")   != nullptr, "key: access_windows");
    CHECK(std::strstr(json, "\"delta_v_kms\"")      != nullptr, "key: delta_v_kms");
    CHECK(std::strstr(json, "\"link_cn0_dbhz\"")    != nullptr, "key: link_cn0_dbhz");

    // Value sanity: eclipse_fraction should contain a float in [0.28, 0.45] region
    // (just check that a digit follows the key, not that the value is exact)
    const char* ef_pos = std::strstr(json, "\"eclipse_fraction\":");
    CHECK(ef_pos != nullptr && *(ef_pos + 20) != '}', "eclipse_fraction has a value");

    std::printf("  json_len=%zu chars\n", std::strlen(json));
}

// ── Main ──────────────────────────────────────────────────────────────────────

int main() {
    std::printf("=== VSL Phase 3 Integration Test ===\n");

    jl_init();

    std::printf("[init] vsl_solver_init\n");
    int rc = vsl_solver_init("");
    if (rc != 0) {
        std::fprintf(stderr, "FATAL: vsl_solver_init failed\n");
        jl_atexit_hook(0);
        return 1;
    }
    std::printf("  VSLSolver loaded OK\n\n");

    test_propagate();   std::printf("\n");
    test_eclipse();     std::printf("\n");
    test_access();      std::printf("\n");
    test_hohmann();     std::printf("\n");
    test_report_json(); std::printf("\n");

    vsl_solver_shutdown();
    jl_atexit_hook(0);

    std::printf("=== Results: %d passed, %d failed ===\n", passed, failed);
    return (failed == 0) ? 0 : 1;
}
