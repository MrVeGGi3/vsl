using SatelliteToolboxTle
using SatelliteToolboxPropagators
using StaticArrays

"""
    propagate_orbit(tle, duration_s; step_s=60.0) -> (times, positions, velocities)

Propagate a TLE using SGP4 for `duration_s` seconds.
Returns times (s), positions (Vec3, km), velocities (Vec3, km/s).
"""
function propagate_orbit(tle::TLE, duration_s::Float64; step_s::Float64=60.0)
    orbp = Propagators.init(Val(:SGP4), tle)
    times = 0.0:step_s:duration_s
    n = length(times)

    positions  = Vector{Vec3}(undef, n)
    velocities = Vector{Vec3}(undef, n)

    @inbounds for (i, t) in enumerate(times)
        r, v = Propagators.propagate!(orbp, t)
        positions[i]  = Vec3(r) .* 1e-3   # m → km
        velocities[i] = Vec3(v) .* 1e-3   # m/s → km/s
    end

    return collect(times), positions, velocities
end

"""
    propagate_orbit!(pos_out, vel_out, orbp, times)

In-place propagation — zero allocation on the hot path.
`orbp` must be a pre-initialized propagator (call `Propagators.init` once).
"""
function propagate_orbit!(
    pos_out::Vector{Vec3},
    vel_out::Vector{Vec3},
    orbp,
    times::AbstractVector{Float64},
)
    @inbounds for (i, t) in enumerate(times)
        r, v = Propagators.propagate!(orbp, t)
        pos_out[i] = Vec3(r) .* 1e-3   # m → km
        vel_out[i] = Vec3(v) .* 1e-3   # m/s → km/s
    end
    return pos_out, vel_out
end
