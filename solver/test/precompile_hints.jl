using VSLSolver
using DifferentialEquations
using StaticArrays
using LinearAlgebra
using SatelliteToolboxTle
using SatelliteToolboxPropagators

# ── Atmosphere ────────────────────────────────────────────────────────────────
nrlmsise00_at(0.0,      -2.37, -44.40, 2451545.0)
nrlmsise00_at(10_000.0, -2.37, -44.40, 2451545.0)
nrlmsise00_at(80_000.0, -2.37, -44.40, 2451545.0)

# ── ThrustCurve ───────────────────────────────────────────────────────────────
tc = ThrustCurve(
    [0.0, 5.0, 10.0],
    [0.0, 1000.0, 0.0],
    [5.0, 5.0, 0.0],
    100.0, 50.0,
)
thrust_at(tc, 0.0)
thrust_at(tc, 2.5)
thrust_at(tc, 5.0)
thrust_at(tc, 15.0)

# ── AeroTable ─────────────────────────────────────────────────────────────────
at_zero = AeroTable([0.0, 5.0], [0.0, 0.5], zeros(2, 2), zeros(2, 2))
at_real = AeroTable([0.0, 5.0], [0.0, 0.5], fill(0.3, 2, 2), fill(0.5, 2, 2))
aero_forces(at_zero, 0.0, 0.0, 1000.0, 0.1)
aero_forces(at_real, 2.0, 0.1, 1000.0, 0.1)

# ── Shared inertia ────────────────────────────────────────────────────────────
I_diag = SMatrix{3,3,Float64,9}(diagm([10.0, 10.0, 1.0]))
I_inv  = SMatrix{3,3,Float64,9}(diagm([1/10.0, 1/10.0, 1.0]))
tc0    = ThrustCurve([0.0, 30.0], [0.0, 0.0], [0.0, 0.0], 100.0, 100.0)

# ── 6-DOF vacuum ─────────────────────────────────────────────────────────────
p_vac = SixDOFParams(
    tc0, at_zero, I_diag, I_inv,
    0.1, 2.0, 1.5,
    2451545.0, -15.78, -47.93, 1000.0,
    150.0, 150.0, 4.0,
    false,
    sixdof_cache(),
)
u0 = [0.0, 0.0, 0.0,  0.0, 0.0, 100.0,  1.0, 0.0, 0.0, 0.0,  0.0, 0.0, 0.0]
solve(ODEProblem(sixdof!, u0, (0.0, 30.0), p_vac), Tsit5(); reltol=1e-8, abstol=1e-8)

# ── 6-DOF with atmosphere ─────────────────────────────────────────────────────
p_atm = SixDOFParams(
    tc0, at_real, I_diag, I_inv,
    0.1, 2.0, 1.5,
    2451545.0, -15.78, -47.93, 0.0,
    150.0, 150.0, 4.0,
    true,
    sixdof_cache(),
)
u0_atm = [0.0, 0.0, 50.0,  0.0, 0.0, 200.0,  1.0, 0.0, 0.0, 0.0,  0.0, 0.0, 0.0]
solve(ODEProblem(sixdof!, u0_atm, (0.0, 30.0), p_atm), Tsit5(); reltol=1e-6, abstol=1e-6)

# ── SGP4 orbital propagation ──────────────────────────────────────────────────
l1 = "1 25544U 98067A   24001.50000000  .00006000  00000-0  10000-3 0  9992"
l2 = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49507896 12343"
tle  = read_tle(l1, l2)
orbp = Propagators.init(Val(:SGP4), tle)
for t in 0.0:60.0:3600.0
    Propagators.propagate!(orbp, t)
end

println("precompile_hints: all hot paths exercised")
