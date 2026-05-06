using StaticArrays

const MU_EARTH = 398600.4418  # km³/s²

"""
    hohmann_transfer(r1_km, r2_km) -> (dv1, dv2, tof_s)

Delta-v burns (km/s) and time of flight (s) for a Hohmann transfer
between circular orbits at radii r1_km and r2_km.
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

# ── Stumpff universal-variable functions ─────────────────────────────────────

function _stumpff_C(z::Float64)::Float64
    z >  1e-6 && return (1.0 - cos(sqrt(z))) / z
    z < -1e-6 && return (cosh(sqrt(-z)) - 1.0) / (-z)
    return 0.5 + z * (-1.0/24.0 + z / 720.0)  # Taylor series
end

function _stumpff_S(z::Float64)::Float64
    z >  1e-6 && return (sqrt(z) - sin(sqrt(z))) / z^1.5
    z < -1e-6 && return (sinh(sqrt(-z)) - sqrt(-z)) / (-z)^1.5
    return 1.0/6.0 + z * (-1.0/120.0 + z / 5040.0)  # Taylor series
end

function _lambert_y(z::Float64, r1n::Float64, r2n::Float64, A::Float64)::Float64
    C = _stumpff_C(z)
    S = _stumpff_S(z)
    return r1n + r2n + A * (z * S - 1.0) / sqrt(C)
end

# F(z) = 0 is the Lambert time-of-flight equation (Curtis §5.3)
function _lambert_F(z::Float64, r1n::Float64, r2n::Float64, A::Float64,
                    tof::Float64, mu::Float64)::Float64
    y = _lambert_y(z, r1n, r2n, A)
    C = _stumpff_C(z)
    S = _stumpff_S(z)
    return (y / C)^1.5 * S / sqrt(mu) + A * sqrt(y / mu) - tof
end

"""
    lambert_problem(r1, r2, tof; prograde=true, mu=MU_EARTH) -> (v1, v2)

Solve Lambert's problem: find departure velocity v1 and arrival velocity v2
(km/s) for a transfer from position r1 to r2 (km) in time tof (s).

Uses the universal-variable method (Curtis, "Orbital Mechanics for Engineering
Students", Algorithm 5.2). Elliptic transfers only; degenerate cases
(Δν ≈ 0° or 180°) are not supported.
"""
function lambert_problem(
    r1::Vec3,
    r2::Vec3,
    tof::Float64;
    prograde::Bool = true,
    mu::Float64    = MU_EARTH,
)
    @assert tof > 0.0 "time of flight must be positive"

    r1n = norm(r1)
    r2n = norm(r2)

    cos_dnu = clamp(dot(r1, r2) / (r1n * r2n), -1.0, 1.0)
    dnu     = acos(cos_dnu)

    c12 = cross(r1, r2)
    if prograde
        c12[3] < 0.0 && (dnu = 2π - dnu)
    else
        c12[3] >= 0.0 && (dnu = 2π - dnu)
    end

    sin_dnu       = sin(dnu)
    one_minus_cos = 1.0 - cos_dnu
    @assert one_minus_cos > 1e-10 "Transfer angle too close to 0° or 360° — degenerate case"
    @assert abs(sin_dnu) > 1e-6  "Transfer angle too close to 180° — use hohmann_transfer instead"

    A = sin_dnu * sqrt(r1n * r2n / one_minus_cos)

    # Newton-Raphson on F(z) = 0
    z = 0.0
    for _ in 1:100
        F  = _lambert_F(z, r1n, r2n, A, tof, mu)
        Fp = _lambert_F(z + 1e-6, r1n, r2n, A, tof, mu)
        Fm = _lambert_F(z - 1e-6, r1n, r2n, A, tof, mu)
        dF = (Fp - Fm) / 2e-6
        abs(dF) < 1e-30 && break
        dz = -F / dF
        z  = max(z + dz, -4π^2 + 0.01)  # keep z from diverging to -∞
        abs(dz) < 1e-8 && break
    end

    y  = _lambert_y(z, r1n, r2n, A)
    f  = 1.0 - y / r1n
    g  = A * sqrt(y / mu)
    gd = 1.0 - y / r2n

    v1 = (r2 - f * r1) / g
    v2 = (gd * r2 - r1) / g

    return v1, v2
end
