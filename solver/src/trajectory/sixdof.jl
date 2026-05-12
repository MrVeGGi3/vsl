using StaticArrays
using LinearAlgebra
using ReferenceFrameRotations

# ── State vector layout (SVector{13,Float64}) ─────────────────────────────────
#  [1:3]   position  (m)  — ENU frame, origin at launch site
#  [4:6]   velocity  (m/s) — ENU frame
#  [7:10]  quaternion [q0,q1,q2,q3]  — body→ENU, scalar-first
#  [11:13] angular velocity [p,q,r]  (rad/s) — body frame

const _G0 = 9.80665  # m/s²

"""
    SixDOFCache

Pre-allocated mutable intermediates used by `sixdof!` to avoid heap allocation
in the no-atmosphere code path.
"""
struct SixDOFCache
    F_body::MVector{3,Float64}
    dω::MVector{3,Float64}
end

SixDOFCache() = SixDOFCache(MVector{3,Float64}(undef), MVector{3,Float64}(undef))

"""
    SixDOFParams

All parameters consumed by `sixdof!`.

Set `use_atmosphere = false` for ballistic (vacuum) simulations — NRLMSISE-00
is skipped entirely, guaranteeing a zero-allocation ODE right-hand side.
"""
struct SixDOFParams{IT}
    thrust_curve::ThrustCurve
    aero_table::AeroTable{IT}
    I_body::SMatrix{3,3,Float64,9}      # inertia tensor, body frame (kg·m²)
    I_body_inv::SMatrix{3,3,Float64,9}  # precomputed inverse
    S_ref::Float64                       # reference area (m²)
    xcp::Float64                         # center of pressure from nose (m, positive toward tail)
    xcg::Float64                         # center of gravity from nose (m, positive toward tail)
    jd_epoch::Float64                    # Julian Date at t=0
    lat0_deg::Float64                    # launch site latitude  (deg)
    lon0_deg::Float64                    # launch site longitude (deg)
    launch_alt_m::Float64                # launch site altitude  (m MSL)
    f107A::Float64                       # space weather: 81-day F10.7 average (SFU)
    f107::Float64                        # space weather: daily  F10.7 (SFU)
    ap::Float64                          # space weather: geomagnetic ap index (nT)
    use_atmosphere::Bool
    cache::SixDOFCache
end

"""
    sixdof_cache() -> SixDOFCache

Factory for a fresh pre-allocated cache.  Allocate once before the ODE solve,
then pass inside `SixDOFParams`.
"""
sixdof_cache()::SixDOFCache = SixDOFCache()

"""
    sixdof!(du, u, p, t)

In-place 6-DOF ODE right-hand side for a rigid sounding rocket.

- `du`, `u` : length-13 mutable arrays (DifferentialEquations.jl interface)
- `p`       : `SixDOFParams`
- `t`       : time (s) from launch

When `p.use_atmosphere == false` the function is allocation-free (verified by
`@allocated` in the ballistic test).  With atmosphere, `nrlmsise00` may allocate.

Forces (ENU frame):
  F_total = D · (F_thrust_body + F_aero_body) + [0, 0, −mg]

Rotation (body frame, Euler rigid-body equations):
  I · dω/dt = τ − ω × (I·ω)
  τ = aerodynamic pitch/yaw restoring moment when use_atmosphere=true, else 0

Quaternion kinematics:
  dq/dt = 0.5 · Ω(ω_body) · q      (via `dquat` from ReferenceFrameRotations)
"""
function sixdof!(du, u, p::SixDOFParams, t::Float64)
    # ── Extract states via views (no copy) ──────────────────────────────────
    r    = @view u[1:3]
    v    = @view u[4:6]
    qv   = @view u[7:10]
    ω    = @view u[11:13]

    # ── Quaternion + rotation matrix ────────────────────────────────────────
    q = Quaternion(qv[1], qv[2], qv[3], qv[4])
    D = quat_to_dcm(q)  # body→ENU, SMatrix{3,3} — zero alloc

    # ── Thrust and mass ─────────────────────────────────────────────────────
    F_thrust, m = thrust_at(p.thrust_curve, t)

    # ── Aerodynamic + atmospheric forces ────────────────────────────────────
    τ_aero_y = 0.0  # pitch/yaw restoring torque (body y-axis); 0 in vacuum
    F_aero_body = if p.use_atmosphere
        alt_m   = max(r[3] + p.launch_alt_m, 0.0)
        lat_deg = p.lat0_deg + r[2] / 111_320.0
        lon_deg = p.lon0_deg + r[1] / (111_320.0 * cos(deg2rad(p.lat0_deg)))
        atm = nrlmsise00_at(alt_m, lat_deg, lon_deg, p.jd_epoch;
                            f107A=p.f107A, f107=p.f107, ap=p.ap)
        v_enu   = SVector(v[1], v[2], v[3])
        v_body  = D' * v_enu
        v_mag   = sqrt(v[1]^2 + v[2]^2 + v[3]^2)
        mach    = (v_mag < 1.0) ? 0.0 : v_mag / atm.speed_of_sound
        aoa_rad = (v_mag < 1.0) ? 0.0 :
                  acos(clamp(v_body[3] / v_mag, -1.0, 1.0))
        q_dyn   = 0.5 * atm.density * v_mag^2
        mach_c  = clamp(mach,    p.aero_table.mach_grid[1], p.aero_table.mach_grid[end])
        aoa_c   = clamp(aoa_rad, p.aero_table.aoa_grid[1],  p.aero_table.aoa_grid[end])
        # Pitch/yaw restoring moment: τ_y = CN·q·S·(xcg−xcp); stable when xcp > xcg
        τ_aero_y = p.aero_table._itp_CN(mach_c, aoa_c) * (p.xcg - p.xcp) * q_dyn * p.S_ref
        aero_forces(p.aero_table, mach, aoa_rad, q_dyn, p.S_ref)
    else
        SVector(0.0, 0.0, 0.0)
    end
    τ_aero = SVector(0.0, τ_aero_y, 0.0)

    # ── Total body-frame force (thrust along body +z axis) ──────────────────
    F_body_total = SVector(F_aero_body[1],
                           F_aero_body[2],
                           F_aero_body[3] + F_thrust)

    # ── Translational EOM ────────────────────────────────────────────────────
    F_enu = D * F_body_total
    inv_m = 1.0 / m

    @inbounds begin
        du[1] = v[1]
        du[2] = v[2]
        du[3] = v[3]
        du[4] = F_enu[1] * inv_m
        du[5] = F_enu[2] * inv_m
        du[6] = F_enu[3] * inv_m - _G0
    end

    # ── Rotational EOM (Euler) ───────────────────────────────────────────────
    ω_svec = SVector(ω[1], ω[2], ω[3])
    Iω     = p.I_body * ω_svec
    dω_svec = p.I_body_inv * (τ_aero - cross(ω_svec, Iω))

    @inbounds begin
        du[11] = dω_svec[1]
        du[12] = dω_svec[2]
        du[13] = dω_svec[3]
    end

    # ── Quaternion kinematics ────────────────────────────────────────────────
    dq = dquat(q, ω_svec)  # zero alloc (Quaternion is immutable struct)

    @inbounds begin
        du[7]  = dq.q0
        du[8]  = dq.q1
        du[9]  = dq.q2
        du[10] = dq.q3
    end

    nothing
end
