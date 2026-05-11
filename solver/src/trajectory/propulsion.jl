using StaticArrays

"""
    ThrustCurve

Tabulated thrust curve with precomputed mass at each sample point.

Fields:
- `times`    — time stamps from burn start (s)
- `thrusts`  — thrust force at each time stamp (N)
- `masses`   — vehicle mass at each time stamp (kg), precomputed via trapezoid
- `m_dry`    — dry mass after burnout (kg)
"""
struct ThrustCurve
    times::Vector{Float64}
    thrusts::Vector{Float64}
    masses::Vector{Float64}
    m_dry::Float64
end

"""
    ThrustCurve(times, thrusts, mass_flow, m0, m_dry)

Constructor that precomputes the mass vector from the mass_flow profile
via trapezoidal integration, so `thrust_at` is allocation-free at runtime.
"""
function ThrustCurve(
    times::Vector{Float64},
    thrusts::Vector{Float64},
    mass_flow::Vector{Float64},
    m0::Float64,
    m_dry::Float64,
)::ThrustCurve
    n = length(times)
    masses = Vector{Float64}(undef, n)
    masses[1] = m0
    for i in 2:n
        dt = times[i] - times[i-1]
        mdot_avg = 0.5 * (mass_flow[i-1] + mass_flow[i])
        masses[i] = max(masses[i-1] - mdot_avg * dt, m_dry)
    end
    ThrustCurve(times, thrusts, masses, m_dry)
end

"""
    thrust_at(tc, t) -> (F_N, mass_kg)

Zero-alloc linear interpolation of thrust and vehicle mass at time `t` (s).
Returns `(0.0, m_dry)` outside the burn window.
"""
function thrust_at(tc::ThrustCurve, t::Float64)::Tuple{Float64,Float64}
    if t < tc.times[1]
        return (0.0, tc.masses[1])
    end
    if t >= tc.times[end]
        return (0.0, tc.m_dry)
    end
    i = searchsortedfirst(tc.times, t) - 1
    i = clamp(i, 1, length(tc.times) - 1)
    frac = (t - tc.times[i]) / (tc.times[i+1] - tc.times[i])
    F = tc.thrusts[i] + frac * (tc.thrusts[i+1] - tc.thrusts[i])
    m = tc.masses[i] + frac * (tc.masses[i+1] - tc.masses[i])
    return (F, max(m, tc.m_dry))
end
