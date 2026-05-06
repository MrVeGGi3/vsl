using Dates
using SatelliteToolboxTle
using SatelliteToolboxPropagators

"""
Full mission analysis result for a given TLE and ground station configuration.
All times in seconds from TLE epoch, distances in km, velocities in km/s.
"""
struct MissionReport
    tle_epoch::DateTime
    orbit_period_s::Float64
    eclipse_fraction::Float64
    access_windows::Vector{Tuple{Float64,Float64,Float64}}  # (t_start_s, t_end_s, max_elev_deg)
    delta_v_hohmann::Tuple{Float64,Float64,Float64}         # (dv1_kms, dv2_kms, tof_s)
    link_cn0_dbhz::Float64
end

# Parse TLE epoch into DateTime (year from 2-digit code per NORAD convention).
function _tle_epoch_dt(tle_line1::AbstractString)::DateTime
    epoch = strip(tle_line1[19:32])
    yr2   = parse(Int, epoch[1:2])
    year  = yr2 < 57 ? 2000 + yr2 : 1900 + yr2
    day   = parse(Float64, epoch[3:end])
    ms    = round(Int64, (day - 1.0) * 86_400_000)
    return DateTime(year, 1, 1) + Millisecond(ms)
end

# Julian date from TLE line 1 epoch string.
function _tle_jd(tle_line1::AbstractString)::Float64
    return datetime2julian(_tle_epoch_dt(tle_line1))
end

# Slant range (km) from GS to satellite given GS altitude (≈0) and satellite
# orbital radius r_sat_km at elevation angle el_rad.
function _slant_range(r_sat_km::Float64, el_rad::Float64)::Float64
    re = R_EARTH_KM
    return sqrt(r_sat_km^2 - re^2 * cos(el_rad)^2) - re * sin(el_rad)
end

"""
    mission_report(tle_line1, tle_line2; gs_lat, gs_lon, gs_min_elev=5.0,
                   target_alt_km=35786.0, duration_s=86400.0,
                   pt_dbw=0.0, gt_dbi=0.0, gr_dbi=0.0, freq_hz=2.4e9)
                   -> MissionReport

Compute a complete mission analysis: orbital period, eclipse fraction,
access windows, Hohmann ΔV, and link C/N₀.

- `target_alt_km`: altitude (km) for the Hohmann raise/lower target.
- `duration_s`:    analysis duration in seconds (default: 1 day).
- `pt_dbw`, `gt_dbi`, `gr_dbi`, `freq_hz`: Friis link budget parameters.
"""
function mission_report(
    tle_line1::AbstractString,
    tle_line2::AbstractString;
    gs_lat::Float64,
    gs_lon::Float64,
    gs_min_elev::Float64  = 5.0,
    target_alt_km::Float64 = 35786.0,
    duration_s::Float64   = 86400.0,
    pt_dbw::Float64       = 0.0,
    gt_dbi::Float64       = 0.0,
    gr_dbi::Float64       = 0.0,
    freq_hz::Float64      = 2.4e9,
)::MissionReport
    tle      = read_tle(tle_line1, tle_line2)
    jd_epoch = _tle_jd(tle_line1)
    epoch_dt = _tle_epoch_dt(tle_line1)

    # Propagate orbit at 30 s steps
    times, positions, velocities = propagate_orbit(tle, duration_s; step_s=30.0)

    # Orbital period via vis-viva at epoch
    r0n = norm(positions[1])
    v0n = norm(velocities[1])
    a   = 1.0 / (2.0 / r0n - v0n^2 / MU_EARTH)
    period_s = 2π * sqrt(a^3 / MU_EARTH)

    # Eclipse fraction over full duration
    ecl_frac = eclipse_fraction(positions, times, jd_epoch)

    # Access windows from ground station
    wins = access_windows(
        positions, times, gs_lat, gs_lon, jd_epoch;
        min_elev_deg = gs_min_elev,
    )

    # Hohmann ΔV from current orbit to target altitude
    r2_km      = R_EARTH_KM + target_alt_km
    dv1, dv2, tof_h = hohmann_transfer(r0n, r2_km)

    # Link budget: use best-elevation slant range from first window, or nadir
    el_rad   = isempty(wins) ? π / 2 : deg2rad(wins[1][3])
    range_km = _slant_range(r0n, el_rad)
    lb       = link_budget(; pt_dbw, gt_dbi, gr_dbi, freq_hz, range_km)

    return MissionReport(epoch_dt, period_s, ecl_frac, wins, (dv1, dv2, tof_h), lb.cn0_dbhz)
end

"""
    to_json(report::MissionReport) -> String

Serialize a MissionReport to a JSON string (no external dependencies).
"""
function to_json(r::MissionReport)::String
    wins_str = join([
        """{"t_start_s":$(w[1]),"t_end_s":$(w[2]),"max_elev_deg":$(round(w[3]; digits=2))}"""
        for w in r.access_windows
    ], ",")

    return """{
  "tle_epoch": "$(Dates.format(r.tle_epoch, "yyyy-mm-ddTHH:MM:SSZ"))",
  "orbit_period_s": $(round(r.orbit_period_s; digits=2)),
  "eclipse_fraction": $(round(r.eclipse_fraction; digits=4)),
  "access_windows": [$(wins_str)],
  "delta_v_kms": {
    "dv1": $(round(r.delta_v_hohmann[1]; digits=4)),
    "dv2": $(round(r.delta_v_hohmann[2]; digits=4)),
    "tof_s": $(round(r.delta_v_hohmann[3]; digits=1))
  },
  "link_cn0_dbhz": $(round(r.link_cn0_dbhz; digits=2))
}"""
end
