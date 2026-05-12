#!/usr/bin/env julia
# Run from repo root:  julia --project=solver solver/generate_trajectory_json.jl
# Runs the 6-DOF sounding-rocket solver and writes godot/project/solver_results.json.

using Pkg
Pkg.activate(joinpath(@__DIR__))

using VSLSolver
using DifferentialEquations
using StaticArrays
using LinearAlgebra
using ReferenceFrameRotations

const OUT = joinpath(@__DIR__, "..", "godot", "project", "solver_results.json")

# ── Rocket parameters (N-class motor, 80 mm airframe) ─────────────────────────
tc = ThrustCurve(
    [0.0, 0.1, 3.0, 3.05],
    [0.0, 2100.0, 1800.0, 0.0],
    [0.0, 0.60,   0.55,   0.0],
    8.0, 6.2,
)

at = AeroTable(
    [0.0, 0.5, 1.5],
    [0.0, 0.0873, 0.1745],
    [0.70 0.70 0.70; 0.55 0.58 0.65; 0.45 0.48 0.55],
    [0.0  0.20 0.40; 0.0  0.22 0.44; 0.0  0.18 0.36],
)

I_body = SMatrix{3,3,Float64,9}(diagm([0.96, 0.96, 0.006]))
I_inv  = SMatrix{3,3,Float64,9}(diagm([1/0.96, 1/0.96, 1/0.006]))

p = SixDOFParams(
    tc, at, I_body, I_inv,
    0.00503,    # S_ref m²
    0.85,       # xcp (m from nose)
    0.55,       # xcg (m from nose)
    2451545.0,  # JD epoch (J2000)
    -2.37,      # lat0 — Alcântara, MA
    -44.40,     # lon0
    6.0,        # launch_alt_m
    150.0, 150.0, 4.0,
    true,
    sixdof_cache(),
)

u0     = Float64[0, 0, 0,  0, 0, 0,  1, 0, 0, 0,  0, 0, 0]
t_end  = 120.0
n_save = 500

landing_cb = ContinuousCallback((u, t, i) -> u[3], nothing;
    affect_neg! = terminate!, save_positions = (false, false))
prob = ODEProblem(sixdof!, u0, (0.0, t_end), p)
sol  = solve(prob, Tsit5(); reltol=1e-8, abstol=1e-8, saveat=t_end / (n_save - 1),
             callback=landing_cb)

sol.retcode in (ReturnCode.Success, ReturnCode.Terminated) ||
    error("Solver failed: $(sol.retcode)")

n_pts    = length(sol.t)
alts     = [u[3] for u in sol.u]
apo_idx  = argmax(alts)
apogee_m = alts[apo_idx]
apogee_t = sol.t[apo_idx]

# ── ENU position flat array ────────────────────────────────────────────────────
traj_flat = Float64[]
sizehint!(traj_flat, n_pts * 3)
for u in sol.u
    push!(traj_flat, u[1], u[2], u[3])
end
times = collect(Float64, sol.t)

# ── Post-processing: compute performance metrics ───────────────────────────────
burnout_t = tc.times[end]
dt_sample = sol.t[2] - sol.t[1]

max_v, max_v_t, max_v_alt, max_v_mach,
max_q, max_q_t, max_q_alt, max_q_mach,
max_aoa, max_aoa_t,
max_omega, max_omega_t,
burnout_alt, burnout_v,
landing_t, range_m,
total_impulse, propellant_mass = let
    _max_v = 0.0;     _max_v_t = 0.0;  _max_v_alt = 0.0;  _max_v_mach = 0.0
    _max_q = 0.0;     _max_q_t = 0.0;  _max_q_alt = 0.0;  _max_q_mach = 0.0
    _max_aoa = 0.0;   _max_aoa_t = 0.0
    _max_omega = 0.0; _max_omega_t = 0.0
    _burnout_alt = 0.0; _burnout_v = 0.0

    for (i, t) in enumerate(sol.t)
        u = sol.u[i]
        r  = SVector(u[1], u[2], u[3])
        v  = SVector(u[4], u[5], u[6])
        qv = Quaternion(u[7], u[8], u[9], u[10])
        ω  = SVector(u[11], u[12], u[13])

        v_mag = norm(v)
        ω_mag = norm(ω)
        alt_m = max(r[3] + p.launch_alt_m, 0.0)

        lat_deg = p.lat0_deg + r[2] / 111_320.0
        lon_deg = p.lon0_deg + r[1] / (111_320.0 * cos(deg2rad(p.lat0_deg)))
        atm   = nrlmsise00_at(alt_m, lat_deg, lon_deg, p.jd_epoch;
                              f107A=p.f107A, f107=p.f107, ap=p.ap)
        mach  = v_mag < 1.0 ? 0.0 : v_mag / atm.speed_of_sound
        q_dyn = 0.5 * atm.density * v_mag^2

        D      = quat_to_dcm(qv)
        v_body = D' * v
        v_body_perp = sqrt(v_body[1]^2 + v_body[2]^2)
        aoa    = atan(v_body_perp, v_body[3])

        if abs(t - burnout_t) < dt_sample * 0.5
            _burnout_alt = r[3]
            _burnout_v   = v_mag
        end

        if v_mag > _max_v;     _max_v = v_mag; _max_v_t = t; _max_v_alt = r[3]; _max_v_mach = mach; end
        if q_dyn > _max_q;     _max_q = q_dyn; _max_q_t = t; _max_q_alt = r[3]; _max_q_mach = mach; end
        if u[6] > 0.0 && aoa   > _max_aoa;   _max_aoa = aoa; _max_aoa_t = t;   end
        if u[6] > 0.0 && ω_mag > _max_omega; _max_omega = ω_mag; _max_omega_t = t; end
    end

    _land_idx  = findlast(u -> u[3] >= 0.0, sol.u)
    _landing_t = sol.t[_land_idx]
    _land_u    = sol.u[_land_idx]
    _range_m   = sqrt(_land_u[1]^2 + _land_u[2]^2)

    _total_impulse = sum(
        0.5 * (tc.thrusts[i] + tc.thrusts[i+1]) * (tc.times[i+1] - tc.times[i])
        for i in 1:length(tc.times)-1
    )
    _propellant_mass = tc.masses[1] - tc.m_dry

    (_max_v, _max_v_t, _max_v_alt, _max_v_mach,
     _max_q, _max_q_t, _max_q_alt, _max_q_mach,
     _max_aoa, _max_aoa_t,
     _max_omega, _max_omega_t,
     _burnout_alt, _burnout_v,
     _landing_t, _range_m,
     _total_impulse, _propellant_mass)
end

@info "Trajectory" points=n_pts apogee_m=round(apogee_m; digits=1) apogee_t_s=round(apogee_t; digits=1)
@info "Max-Q" q_pa=round(max_q; digits=1) alt_m=round(max_q_alt; digits=1) mach=round(max_q_mach; digits=3) t_s=round(max_q_t; digits=2)
@info "Max velocity" mps=round(max_v; digits=1) mach=round(max_v_mach; digits=3) t_s=round(max_v_t; digits=2)
@info "Burnout" t_s=burnout_t alt_m=round(burnout_alt; digits=1) v_mps=round(burnout_v; digits=1)
@info "Stability" max_aoa_deg=round(rad2deg(max_aoa); digits=2) max_omega_rad_s=round(max_omega; digits=4)

# ── JSON serializer ────────────────────────────────────────────────────────────
fmt_f(v::Float64) = isfinite(v) ? repr(v) : "0.0"
fmt_arr_f(a)      = "[" * join(fmt_f.(a), ",") * "]"

json = """{
  "trajectory_point_count": $n_pts,
  "trajectory_apogee_m": $(fmt_f(apogee_m)),
  "trajectory_positions_flat": $(fmt_arr_f(traj_flat)),
  "trajectory_times": $(fmt_arr_f(times)),
  "apogee_time_s": $(fmt_f(apogee_t)),
  "landing_time_s": $(fmt_f(landing_t)),
  "range_m": $(fmt_f(range_m)),
  "max_velocity_mps": $(fmt_f(max_v)),
  "max_velocity_time_s": $(fmt_f(max_v_t)),
  "max_velocity_altitude_m": $(fmt_f(max_v_alt)),
  "max_velocity_mach": $(fmt_f(max_v_mach)),
  "max_q_pa": $(fmt_f(max_q)),
  "max_q_time_s": $(fmt_f(max_q_t)),
  "max_q_altitude_m": $(fmt_f(max_q_alt)),
  "max_q_mach": $(fmt_f(max_q_mach)),
  "burnout_time_s": $(fmt_f(burnout_t)),
  "burnout_altitude_m": $(fmt_f(burnout_alt)),
  "burnout_velocity_mps": $(fmt_f(burnout_v)),
  "propellant_mass_kg": $(fmt_f(propellant_mass)),
  "total_impulse_ns": $(fmt_f(total_impulse)),
  "max_aoa_deg": $(fmt_f(rad2deg(max_aoa))),
  "max_aoa_time_s": $(fmt_f(max_aoa_t)),
  "max_angular_rate_rad_s": $(fmt_f(max_omega)),
  "max_angular_rate_time_s": $(fmt_f(max_omega_t)),
  "point_count": 0,
  "positions_flat": [],
  "orbit_step_s": 10.0,
  "orbit_period_s": 0.0,
  "altitude_km": 0.0,
  "inclination_deg": 0.0,
  "eclipse_fraction": 0.0,
  "eclipse_n_periods": 0,
  "eclipse_period_starts": [],
  "eclipse_period_ends": [],
  "access_windows": []
}"""

write(OUT, json)
@info "Written" path=OUT
