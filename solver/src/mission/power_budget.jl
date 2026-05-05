"""
    power_budget(solar_area_m2, eta, eclipse_frac; solar_flux=1361.0) -> NamedTuple

Simple power budget for a satellite.
- `solar_area_m2`: effective solar panel area (m²)
- `eta`: panel efficiency (0–1)
- `eclipse_frac`: fraction of orbit in eclipse
- `solar_flux`: W/m² (default = 1361 W/m² at 1 AU)

Returns `(p_generated, p_avg, sunlight_frac)` in Watts.
"""
function power_budget(
    solar_area_m2::Float64,
    eta::Float64,
    eclipse_frac::Float64;
    solar_flux::Float64=1361.0,
)
    sunlight_frac = 1.0 - eclipse_frac
    p_generated   = solar_area_m2 * eta * solar_flux
    p_avg         = p_generated * sunlight_frac  # avg over full orbit

    return (p_generated=p_generated, p_avg=p_avg, sunlight_frac=sunlight_frac)
end
