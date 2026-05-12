#include "mission_params_loader.h"

#include <cmath>
#include <cstdio>
#include <fstream>

#include <nlohmann/json.hpp>

using json = nlohmann::json;

// ── helpers ───────────────────────────────────────────────────────────────────

static std::vector<double> to_vec(const json& arr) {
    std::vector<double> v;
    v.reserve(arr.size());
    for (auto& el : arr)
        v.push_back(el.get<double>());
    return v;
}

// ── loader ────────────────────────────────────────────────────────────────────

bool load_mission_params(const std::string& path, VslMissionParams& p) {
    std::ifstream f(path);
    if (!f.is_open()) {
        std::fprintf(stderr, "[vsl] mission_params: cannot open %s\n", path.c_str());
        return false;
    }

    json j;
    try {
        f >> j;
    } catch (const json::parse_error& e) {
        std::fprintf(stderr, "[vsl] mission_params: parse error in %s: %s\n",
                     path.c_str(), e.what());
        return false;
    }

    // orbital
    if (j.contains("orbital")) {
        auto& o = j["orbital"];
        if (o.contains("tle_line1"))          p.orbital.tle_line1          = o["tle_line1"];
        if (o.contains("tle_line2"))          p.orbital.tle_line2          = o["tle_line2"];
        if (o.contains("analysis_duration_s")) p.orbital.analysis_duration_s = o["analysis_duration_s"];
        if (o.contains("orbit_step_s"))        p.orbital.orbit_step_s        = o["orbit_step_s"];
        if (o.contains("target_alt_km"))       p.orbital.target_alt_km       = o["target_alt_km"];
    }

    // launch site
    if (j.contains("launch_site")) {
        auto& s = j["launch_site"];
        if (s.contains("lat_deg"))       p.launch_site.lat_deg       = s["lat_deg"];
        if (s.contains("lon_deg"))       p.launch_site.lon_deg       = s["lon_deg"];
        if (s.contains("alt_m"))         p.launch_site.alt_m         = s["alt_m"];
        if (s.contains("azimuth_deg"))   p.launch_site.azimuth_deg   = s["azimuth_deg"];
        if (s.contains("elevation_deg")) p.launch_site.elevation_deg = s["elevation_deg"];
    }

    // ground station
    if (j.contains("ground_station")) {
        auto& g = j["ground_station"];
        if (g.contains("lat_deg"))      p.ground_station.lat_deg      = g["lat_deg"];
        if (g.contains("lon_deg"))      p.ground_station.lon_deg      = g["lon_deg"];
        if (g.contains("min_elev_deg")) p.ground_station.min_elev_deg = g["min_elev_deg"];
    }

    // atmosphere
    if (j.contains("atmosphere")) {
        auto& a = j["atmosphere"];
        if (a.contains("model"))    p.atmosphere.use_nrlmsise = (a["model"] == "nrlmsise00");
        if (a.contains("f107a_sfu")) p.atmosphere.f107a_sfu = a["f107a_sfu"];
        if (a.contains("f107_sfu"))  p.atmosphere.f107_sfu  = a["f107_sfu"];
        if (a.contains("ap_nt"))     p.atmosphere.ap_nt      = a["ap_nt"];
    }

    // payload
    if (j.contains("payload")) {
        auto& pl = j["payload"];
        if (pl.contains("mass_kg"))    p.payload.mass_kg    = pl["mass_kg"];
        if (pl.contains("diameter_m")) p.payload.diameter_m = pl["diameter_m"];
        if (pl.contains("length_m"))   p.payload.length_m   = pl["length_m"];
        if (pl.contains("max_g"))      p.payload.max_g      = pl["max_g"];
        if (pl.contains("temp_min_c")) p.payload.temp_min_c = pl["temp_min_c"];
        if (pl.contains("temp_max_c")) p.payload.temp_max_c = pl["temp_max_c"];
    }

    // propulsion
    if (j.contains("propulsion")) {
        auto& pr = j["propulsion"];
        if (pr.contains("isp_s"))      p.propulsion.isp_s      = pr["isp_s"];
        if (pr.contains("mass_dry_kg")) p.propulsion.mass_dry_kg = pr["mass_dry_kg"];
        if (pr.contains("mass_wet_kg")) p.propulsion.mass_wet_kg = pr["mass_wet_kg"];

        if (pr.contains("thrust_curve")) {
            auto& tc = pr["thrust_curve"];
            if (tc.contains("times_s"))        p.propulsion.times_s        = to_vec(tc["times_s"]);
            if (tc.contains("thrusts_n"))       p.propulsion.thrusts_n      = to_vec(tc["thrusts_n"]);
            if (tc.contains("mass_flows_kgs"))  p.propulsion.mass_flows_kgs = to_vec(tc["mass_flows_kgs"]);
        }
    }

    // rocket geometry + aero
    if (j.contains("rocket")) {
        auto& r = j["rocket"];
        if (r.contains("body_diameter_m"))      p.rocket.body_diameter_m      = r["body_diameter_m"];
        if (r.contains("body_length_m"))         p.rocket.body_length_m         = r["body_length_m"];
        if (r.contains("nose_shape"))            p.rocket.nose_shape            = r["nose_shape"].get<std::string>();
        if (r.contains("nose_length_m"))         p.rocket.nose_length_m         = r["nose_length_m"];
        if (r.contains("inertia_lateral_kgm2"))  p.rocket.inertia_lateral_kgm2  = r["inertia_lateral_kgm2"];
        if (r.contains("inertia_axial_kgm2"))    p.rocket.inertia_axial_kgm2    = r["inertia_axial_kgm2"];

        auto& aero = p.rocket.aero;
        if (r.contains("xcp_m"))  aero.xcp_m = r["xcp_m"];
        if (r.contains("xcg_m"))  aero.xcg_m = r["xcg_m"];

        // s_ref derived from body diameter
        double d = p.rocket.body_diameter_m;
        aero.s_ref_m2 = M_PI * (d / 2.0) * (d / 2.0);

        if (r.contains("aero_table")) {
            auto& at = r["aero_table"];
            if (at.contains("mach_grid"))    aero.mach_grid    = to_vec(at["mach_grid"]);
            if (at.contains("aoa_grid_rad")) aero.aoa_grid_rad = to_vec(at["aoa_grid_rad"]);
            if (at.contains("cd_table"))     aero.cd_table     = to_vec(at["cd_table"]);
            if (at.contains("cn_table"))     aero.cn_table     = to_vec(at["cn_table"]);
        }
    }

    // simulation initial conditions
    if (j.contains("simulation")) {
        auto& sim = j["simulation"];
        if (sim.contains("t_end_s")) p.simulation.t_end_s = sim["t_end_s"];

        if (sim.contains("initial_state")) {
            auto& ic = sim["initial_state"];
            auto fill3 = [&](const char* key, double* dst) {
                if (ic.contains(key) && ic[key].size() == 3)
                    for (int i = 0; i < 3; ++i) dst[i] = ic[key][i];
            };
            auto fill4 = [&](const char* key, double* dst) {
                if (ic.contains(key) && ic[key].size() == 4)
                    for (int i = 0; i < 4; ++i) dst[i] = ic[key][i];
            };
            fill3("position_enu_m",       p.simulation.pos_enu_m);
            fill3("velocity_enu_mps",     p.simulation.vel_enu_mps);
            fill4("quaternion_body2enu",  p.simulation.quat_body2enu);
            fill3("angular_rate_rad_s",   p.simulation.ang_rate_rad_s);
        }
    }

    std::fprintf(stderr, "[vsl] loaded mission_params: %s\n", path.c_str());
    return true;
}

// ── C API struct builders ─────────────────────────────────────────────────────

VslThrustCurveData make_thrust_curve(const VslMissionParams& p) {
    const auto& pr = p.propulsion;
    VslThrustCurveData tc{};
    tc.times      = pr.times_s.data();
    tc.thrusts    = pr.thrusts_n.data();
    tc.mass_flows = pr.mass_flows_kgs.data();
    tc.mass_dry_kg = pr.mass_dry_kg;
    tc.mass_wet_kg = pr.mass_wet_kg;
    tc.n_points    = static_cast<int>(pr.times_s.size());
    return tc;
}

VslAeroTableData make_aero_table(const VslMissionParams& p) {
    const auto& a = p.rocket.aero;
    VslAeroTableData at{};
    at.mach_grid = a.mach_grid.data();
    at.aoa_grid  = a.aoa_grid_rad.data();
    at.cd_table  = a.cd_table.data();
    at.cn_table  = a.cn_table.data();
    at.s_ref_m2  = a.s_ref_m2;
    at.xcp_m     = a.xcp_m;
    at.xcg_m     = a.xcg_m;
    at.n_mach    = static_cast<int>(a.mach_grid.size());
    at.n_aoa     = static_cast<int>(a.aoa_grid_rad.size());
    return at;
}
