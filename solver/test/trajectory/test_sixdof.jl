using Test
using StaticArrays
using DifferentialEquations
using LinearAlgebra

# ── Helpers ───────────────────────────────────────────────────────────────────

function _identity_params(; m0=100.0, use_atmosphere=false)
    # Constant thrust curve — no thrust (zero everywhere), 10 s duration
    times     = [0.0, 10.0]
    thrusts   = [0.0,  0.0]
    mass_flow = [0.0,  0.0]
    tc = ThrustCurve(times, thrusts, mass_flow, m0, m0)

    # Simple AeroTable: 2×2 grid, CD=0 everywhere (no drag in ballistic test)
    mach_g = [0.0, 5.0]
    aoa_g  = [0.0, 0.5]
    CD = zeros(2, 2)
    CN = zeros(2, 2)
    at = AeroTable(mach_g, aoa_g, CD, CN)

    # Diagonal inertia tensor (symmetric rocket)
    I_diag = SMatrix{3,3,Float64,9}(diagm([10.0, 10.0, 1.0]))
    I_inv  = SMatrix{3,3,Float64,9}(diagm([1/10.0, 1/10.0, 1.0]))

    SixDOFParams(
        tc, at, I_diag, I_inv,
        0.1,       # S_ref m²
        2.0,       # xcp (m from nose) — CP aft of CG → stable
        1.5,       # xcg (m from nose)
        2451545.0, # jd_epoch (J2000)
        -15.78,    # lat0_deg  (Brasília)
        -47.93,    # lon0_deg
        1000.0,    # launch_alt_m
        150.0,     # f107A
        150.0,     # f107
        4.0,       # ap
        use_atmosphere,
        sixdof_cache(),
    )
end

# Initial state: vertical launch (body +z aligned with ENU +z), at rest
function _initial_state_vertical(; vz0=0.0, m0=100.0)
    # [x, y, z, vx, vy, vz, q0, q1, q2, q3, p, q, r]
    # Identity quaternion: body aligned with ENU
    Vector{Float64}([0.0, 0.0, 0.0,    # position (m)
                     0.0, 0.0, vz0,     # velocity (m/s)
                     1.0, 0.0, 0.0, 0.0, # quaternion (identity)
                     0.0, 0.0, 0.0])    # angular velocity
end

# ── Case 1: Ballistic — no atmosphere, no thrust, no drag ─────────────────────
@testset "6DOF ballistic (vacuum) — analytical solution" begin
    p = _identity_params(; m0=100.0, use_atmosphere=false)
    u0 = _initial_state_vertical(; vz0=100.0)  # 100 m/s upward

    # Verify zero allocation on the ODE RHS (vacuum path)
    du = zeros(13)
    sixdof!(du, u0, p, 0.0)  # warmup
    allocs = @allocated sixdof!(du, u0, p, 0.0)
    @test allocs == 0

    # Integrate 20 s
    tspan = (0.0, 20.0)
    prob  = ODEProblem(sixdof!, u0, tspan, p)
    sol   = solve(prob, Tsit5(); reltol=1e-8, abstol=1e-8, saveat=1.0)

    @test sol.retcode == ReturnCode.Success

    # Analytical: z(t) = vz0·t − 0.5·g·t²
    vz0 = 100.0
    g   = 9.80665
    for (i, t) in enumerate(sol.t)
        z_analytical = vz0 * t - 0.5 * g * t^2
        z_simulated  = sol.u[i][3]
        @test abs(z_simulated - z_analytical) < 1.0  # tolerance: 1 m
    end

    # Quaternion norm should remain 1 throughout integration
    for ui in sol.u
        qnorm = norm(ui[7:10])
        @test abs(qnorm - 1.0) < 1e-6
    end

    # No horizontal drift (no lateral forces)
    @test abs(sol.u[end][1]) < 1e-9
    @test abs(sol.u[end][2]) < 1e-9
end

# ── Case 2: NRLMSISE-00 atmosphere sanity check ───────────────────────────────
@testset "6DOF NRLMSISE-00 atmosphere — density sanity" begin
    # Direct atmosphere function test — no full ODE integration needed
    jd = 2451545.0  # J2000.0

    # Query at several altitudes (Alcântara launch site coordinates)
    alts_m = [0.0, 10_000.0, 30_000.0, 80_000.0, 200_000.0]
    densities = map(alts_m) do alt
        nrlmsise00_at(alt, -2.37, -44.40, jd).density
    end

    # Density must decrease monotonically with altitude
    @testset "density decreases with altitude" begin
        for i in 1:length(densities)-1
            @test densities[i] > densities[i+1]
        end
    end

    # Sea-level density plausible: between 0.9 and 1.4 kg/m³
    @test 0.9 < densities[1] < 1.4

    # At 200 km altitude: roughly 1e-10 to 1e-8 kg/m³
    @test 1e-11 < densities[end] < 1e-7

    # Speed of sound at sea level: between 300 and 360 m/s
    atm_sl = nrlmsise00_at(0.0, -2.37, -44.40, jd)
    @test 300.0 < atm_sl.speed_of_sound < 360.0

    # Integration with atmosphere: particle falls from 80 km, check it moves
    p = _identity_params(; m0=50.0, use_atmosphere=true)
    u0 = let
        v = _initial_state_vertical(; vz0=0.0)
        v[3] = 80_000.0  # start at 80 km altitude
        v
    end

    tspan = (0.0, 60.0)
    prob  = ODEProblem(sixdof!, u0, tspan, p)
    sol   = solve(prob, Tsit5(); reltol=1e-6, abstol=1e-6, saveat=10.0)

    @test sol.retcode == ReturnCode.Success
    # Object must fall (z decreases)
    @test sol.u[end][3] < u0[3]
end

# ── Case 3: ThrustCurve unit tests ───────────────────────────────────────────
@testset "ThrustCurve — interpolation and mass integration" begin
    # Known profile: 0→1000 N linearly over 0–5 s, then shuts off
    times     = [0.0, 5.0, 10.0]
    thrusts   = [0.0, 1000.0, 0.0]
    mass_flow = [5.0, 5.0, 0.0]   # kg/s
    m0        = 100.0
    m_dry     = 50.0
    tc = ThrustCurve(times, thrusts, mass_flow, m0, m_dry)

    # Before burn: no thrust, full initial mass
    F, m = thrust_at(tc, -1.0)
    @test F == 0.0
    @test m == m0

    # At t=0: thrust=0, mass=m0
    F0, m0v = thrust_at(tc, 0.0)
    @test F0 == 0.0
    @test m0v ≈ m0

    # At t=5 (peak thrust): 1000 N, mass = 100 − trapz(5kg/s, 5s) = 75 kg
    F5, m5 = thrust_at(tc, 5.0)
    @test F5 ≈ 1000.0
    @test m5 ≈ 75.0

    # At t=2.5 (mid ramp): thrust ≈ 500 N, mass ≈ 87.5 kg (linear interpolation)
    F25, m25 = thrust_at(tc, 2.5)
    @test F25 ≈ 500.0
    @test m25 ≈ 87.5

    # After burnout: no thrust, dry mass
    F_end, m_end = thrust_at(tc, 15.0)
    @test F_end == 0.0
    @test m_end == m_dry

    # Zero allocation (hot path must not heap-allocate)
    thrust_at(tc, 5.0)  # warmup
    @test @allocated(thrust_at(tc, 5.0)) == 0
end

# ── Case 4: AeroTable unit tests ──────────────────────────────────────────────
@testset "AeroTable — bilinear lookup and zero allocation" begin
    # 2×2 grid with known CD and CN
    mach_g = [0.0, 2.0]
    aoa_g  = [0.0, π/4]
    CD = [0.3 0.4; 0.5 0.6]  # (Mach, AoA) indexing
    CN = [0.0 0.8; 0.0 1.2]
    at = AeroTable(mach_g, aoa_g, CD, CN)

    q_dyn = 1000.0  # Pa
    S_ref = 0.1     # m²

    # At AoA=0, CN=0: Fx = (-CD*sin(0) + 0*cos(0))*qS = 0; Fz = -CD*qS
    F0 = aero_forces(at, 0.0, 0.0, q_dyn, S_ref)
    @test F0[2] == 0.0                       # symmetry: no lateral force
    @test F0[1] ≈ 0.0                        # Fx = CN*cos(0) - CD*sin(0) = 0
    @test F0[3] ≈ -0.3 * q_dyn * S_ref      # Fz = -CD*cos(0) = -0.3*qS

    # At Mach=2, AoA=0: CD=0.5, CN=0
    F_m2 = aero_forces(at, 2.0, 0.0, q_dyn, S_ref)
    @test F_m2[2] == 0.0
    @test F_m2[3] ≈ -0.5 * q_dyn * S_ref

    # AoA=0 always gives Fy=0 (2D symmetry assumption)
    for mach in [0.0, 1.0, 2.0]
        @test aero_forces(at, mach, 0.0, q_dyn, S_ref)[2] == 0.0
    end

    # Zero allocation
    aero_forces(at, 1.0, 0.1, q_dyn, S_ref)  # warmup
    @test @allocated(aero_forces(at, 1.0, 0.1, q_dyn, S_ref)) == 0
end

# ── Case 5: Aerodynamic stability — fin torque sign ──────────────────────────
@testset "6DOF aerodynamic stability — pitch torque sign" begin
    # AeroTable with nonzero CN to generate pitch moment
    mach_g = [0.0, 5.0]
    aoa_g  = [0.0, 0.5]
    CD = fill(0.3, 2, 2)
    CN = fill(1.0, 2, 2)  # constant CN = 1 for all Mach/AoA
    at = AeroTable(mach_g, aoa_g, CD, CN)

    times     = [0.0, 60.0]
    thrusts   = [0.0, 0.0]
    mass_flow = [0.0, 0.0]
    tc = ThrustCurve(times, thrusts, mass_flow, 50.0, 50.0)

    I_diag = SMatrix{3,3,Float64,9}(diagm([10.0, 10.0, 1.0]))
    I_inv  = SMatrix{3,3,Float64,9}(diagm([1/10.0, 1/10.0, 1.0]))

    function _make_params(xcp, xcg)
        SixDOFParams(
            tc, at, I_diag, I_inv,
            0.1, xcp, xcg,
            2451545.0, -15.78, -47.93, 0.0,  # launch_alt=0 → denser air
            150.0, 150.0, 4.0,
            true,
            sixdof_cache(),
        )
    end

    # Stable: xcp (2.0 m) > xcg (1.0 m) → CP aft of CG
    p_stable   = _make_params(2.0, 1.0)
    # Unstable: xcp (0.5 m) < xcg (1.5 m) → CP forward of CG
    p_unstable = _make_params(0.5, 1.5)

    # 5° pitch perturbation about body y-axis (AoA in xz plane), 200 m/s upward
    θ = deg2rad(5.0)
    u_perturbed = Float64[0.0, 0.0, 0.0,             # position (sea level)
                           0.0, 0.0, 200.0,            # velocity up
                           cos(θ/2), 0.0, sin(θ/2), 0.0, # q: y-axis tilt
                           0.0, 0.0, 0.0]              # no initial angular velocity

    du_stable   = zeros(13)
    du_unstable = zeros(13)
    sixdof!(du_stable,   u_perturbed, p_stable,   0.0)
    sixdof!(du_unstable, u_perturbed, p_unstable, 0.0)

    # Stable: pitch angular acceleration (dω_y = du[12]) must be negative (restoring)
    @test du_stable[12] < 0.0

    # Unstable: pitch angular acceleration must be positive (destabilizing)
    @test du_unstable[12] > 0.0

    # Signs must be opposite
    @test sign(du_stable[12]) != sign(du_unstable[12])
end
