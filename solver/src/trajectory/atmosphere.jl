using SatelliteToolboxAtmosphericModels
using SatelliteToolboxAtmosphericModels.AtmosphericModels
using Dates

const _GAMMA_AIR = 1.4
const _R_AIR     = 287.058  # J/(kg·K)

"""
    AtmosphereState

Output from the NRLMSISE-00 atmospheric model at a given point and time.
"""
struct AtmosphereState
    density::Float64        # kg/m³
    temperature::Float64    # K
    pressure::Float64       # Pa  (ideal gas: p = ρ·R·T)
    speed_of_sound::Float64 # m/s (γ·R·T)^0.5
end

"""
    nrlmsise00_at(alt_m, lat_deg, lon_deg, jd; f107A, f107, ap) -> AtmosphereState

NRLMSISE-00 wrapper.  Accepts altitude in metres, lat/lon in degrees, epoch
as Julian Date.  Space weather constants default to moderate solar activity
(f107A = f107 = 150 SFU, ap = 4 nT) so no network access is required.
"""
function nrlmsise00_at(
    alt_m::Float64,
    lat_deg::Float64,
    lon_deg::Float64,
    jd::Float64;
    f107A::Float64 = 150.0,
    f107::Float64  = 150.0,
    ap::Float64    = 4.0,
)::AtmosphereState
    instant = julian2datetime(jd)
    lat_rad = deg2rad(lat_deg)
    lon_rad = deg2rad(lon_deg)
    out = nrlmsise00(instant, alt_m, lat_rad, lon_rad, f107A, f107, ap)
    ρ   = out.total_density
    T   = out.temperature
    p   = ρ * _R_AIR * T
    a   = sqrt(_GAMMA_AIR * _R_AIR * T)
    AtmosphereState(ρ, T, p, a)
end
