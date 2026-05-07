using StaticArrays
using SatelliteToolboxCelestialBodies

# R_EARTH_KM defined in access.jl (included earlier in the module)
const R_SUN_KM = 696000.0
const AU_KM    = 1.496e8

"""
    in_eclipse(r_eci::Vec3, sun_eci::Vec3) -> Bool

Cylindrical shadow model — fast approximation for LEO.
Returns true if satellite is in Earth's shadow.
"""
function in_eclipse(r_eci::Vec3, sun_eci::Vec3)::Bool
    # Project satellite position onto anti-sun direction
    sun_hat = sun_eci / norm(sun_eci)
    proj    = dot(r_eci, sun_hat)
    proj > 0.0 && return false  # satellite on sun side

    perp_sq = dot(r_eci, r_eci) - proj^2
    return perp_sq < R_EARTH_KM^2
end

"""
    eclipse_periods(positions, times_s, jd_epoch) -> Vector{Tuple{Float64,Float64}}

Returns (t_start_s, t_end_s) pairs for each contiguous eclipse period.
"""
function eclipse_periods(
    positions::Vector{Vec3},
    times_s::Vector{Float64},
    jd_epoch::Float64,
)::Vector{Tuple{Float64,Float64}}
    periods = Tuple{Float64,Float64}[]
    in_ecl  = false
    t_start = 0.0
    @inbounds for i in eachindex(positions)
        jd      = jd_epoch + times_s[i] / 86400.0
        sun_eci = Vec3(sun_position_mod(jd))
        ecl     = in_eclipse(positions[i], sun_eci)
        if ecl && !in_ecl
            t_start = times_s[i]
            in_ecl  = true
        elseif !ecl && in_ecl
            push!(periods, (t_start, times_s[i - 1]))
            in_ecl = false
        end
    end
    in_ecl && push!(periods, (t_start, times_s[end]))
    return periods
end

"""
    eclipse_fraction(positions, times_s, jd_epoch) -> Float64

Fraction of orbit spent in eclipse (0–1).
`jd_epoch` is the Julian Date at t=0.
"""
function eclipse_fraction(
    positions::Vector{Vec3},
    times_s::Vector{Float64},
    jd_epoch::Float64,
)::Float64
    count_eclipse = 0
    @inbounds for (i, r) in enumerate(positions)
        jd      = jd_epoch + times_s[i] / 86400.0
        sun_eci = Vec3(sun_position_mod(jd))  # from SatelliteToolboxCelestialBodies
        count_eclipse += in_eclipse(r, sun_eci) ? 1 : 0
    end
    return count_eclipse / length(positions)
end
