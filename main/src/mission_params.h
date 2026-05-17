#pragma once
#include <string>
#include <vector>

// Input parameter structs for Pipeline A — Sounding Rocket Mission.
//
// These mirror the fields in mission_params.json written by the Godot UI.
// Use mission_params_loader.h to populate from JSON.

struct VslLaunchSite {
    double lat_deg      = -2.37;
    double lon_deg      = -44.40;
    double alt_m        = 6.0;
    double azimuth_deg  = 90.0;   // compass heading of launch rail
    double elevation_deg = 90.0;  // 90 = vertical, < 90 = angled
};

struct VslGroundStation {
    double lat_deg      = -15.78;  // Brasília default
    double lon_deg      = -47.93;
    double min_elev_deg = 5.0;
};

struct VslAtmosphereConfig {
    bool   use_nrlmsise  = true;
    double f107a_sfu     = 150.0;  // 81-day average F10.7
    double f107_sfu      = 150.0;  // daily F10.7
    double ap_nt         = 4.0;    // geomagnetic ap index
};

struct VslPayloadConfig {
    double mass_kg       = 2.0;
    double diameter_m    = 0.08;
    double length_m      = 0.20;
    double max_g         = 30.0;   // structural G limit
    double temp_min_c    = -40.0;
    double temp_max_c    = 85.0;
};

// Propulsion — tabular thrust curve.
// mass_wet_kg is computed by the loader: mass_dry_kg + integrated propellant.
struct VslThrustCurveConfig {
    std::vector<double> times_s;
    std::vector<double> thrusts_n;
    std::vector<double> mass_flows_kgs;
    double mass_dry_kg   = 6.2;
    double mass_wet_kg   = 8.0;   // set by loader from integration or JSON
    double isp_s         = 220.0; // used for Tsiolkovsky estimates only
};

// Aerodynamics — bilinear lookup tables (Mach × AoA).
// cd_table and cn_table are row-major: [n_mach × n_aoa].
struct VslAeroConfig {
    std::vector<double> mach_grid;
    std::vector<double> aoa_grid_rad;
    std::vector<double> cd_table;
    std::vector<double> cn_table;
    double s_ref_m2 = 0.00503;   // π × (d/2)²; loader computes from body_diameter_m
    double xcp_m    = 0.85;
    double xcg_m    = 0.55;
};

struct VslRocketConfig {
    double body_diameter_m        = 0.08;
    double body_length_m          = 1.20;
    std::string nose_shape        = "ogive";  // ogive | vonkarman | conical
    double nose_length_m          = 0.24;
    double inertia_lateral_kgm2   = 0.96;    // I_xx = I_yy
    double inertia_axial_kgm2     = 0.006;   // I_zz (roll)
    VslAeroConfig aero;
};

struct VslSimConfig {
    double t_end_s              = 120.0;
    double pos_enu_m[3]         = {0.0, 0.0, 0.0};
    double vel_enu_mps[3]       = {0.0, 0.0, 0.0};
    double quat_body2enu[4]     = {1.0, 0.0, 0.0, 0.0}; // scalar-first
    double ang_rate_rad_s[3]    = {0.0, 0.0, 0.0};
};

// Orbital analysis (satellite reference — ISS by default).
struct VslOrbitalConfig {
    std::string tle_line1;
    std::string tle_line2;
    double      analysis_duration_s = 86400.0;
    double      orbit_step_s        = 10.0;
    double      target_alt_km       = 600.0;  // Hohmann target
};

struct VslObdhConfig {
    double      mass_kg         = 0.5;
    double      power_avg_w     = 3.0;
    double      data_rate_kbps  = 100.0;
    double      storage_mb      = 128.0;
    std::string processor       = "STM32H7";
};

struct VslTtcConfig {
    double freq_mhz        = 433.0;
    double tx_power_w      = 1.0;
    double tx_gain_dbi     = 0.0;
    double rx_gain_dbi     = 6.0;
    double system_losses_db = 3.0;
    double range_km        = 50.0;
};

struct VslPowerConfig {
    double battery_capacity_wh = 20.0;
    double battery_mass_kg     = 0.3;
    double payload_w           = 5.0;
    double obdh_w              = 3.0;
    double ttc_w               = 2.0;
    double actuators_w         = 0.5;
};

struct VslThermalConfig {
    std::string material               = "aluminum_6061";
    double      wall_thickness_mm      = 2.0;
    double      emissivity             = 0.15;
    double      temp_max_structural_c  = 130.0;
    double      temp_min_structural_c  = -40.0;
};

struct VslMissionParams {
    VslOrbitalConfig     orbital;
    VslLaunchSite        launch_site;
    VslGroundStation     ground_station;
    VslAtmosphereConfig  atmosphere;
    VslPayloadConfig     payload;
    VslThrustCurveConfig propulsion;
    VslRocketConfig      rocket;
    VslSimConfig         simulation;
    VslObdhConfig        obdh;
    VslTtcConfig         ttc;
    VslPowerConfig       power;
    VslThermalConfig     thermal;
};
