using StaticArrays

const MU_EARTH = 398600.4418  # km³/s²

"""
    hohmann_transfer(r1_km, r2_km) -> (dv1, dv2, tof_s)

Compute delta-v burns and time of flight for a Hohmann transfer
between circular orbits at radii `r1_km` and `r2_km` (km).
"""
function hohmann_transfer(r1_km::Float64, r2_km::Float64)
    v1  = sqrt(MU_EARTH / r1_km)
    v2  = sqrt(MU_EARTH / r2_km)
    a_t = (r1_km + r2_km) / 2.0

    v_t1 = sqrt(MU_EARTH * (2.0 / r1_km - 1.0 / a_t))
    v_t2 = sqrt(MU_EARTH * (2.0 / r2_km - 1.0 / a_t))

    dv1  = abs(v_t1 - v1)
    dv2  = abs(v2  - v_t2)
    tof  = π * sqrt(a_t^3 / MU_EARTH)

    return dv1, dv2, tof
end

# Lambert problem solver — placeholder for Izzo/Gooding implementation (Phase 2)
function lambert_problem(r1::Vec3, r2::Vec3, tof::Float64; prograde::Bool=true)
    error("Lambert solver not yet implemented — Phase 2")
end
