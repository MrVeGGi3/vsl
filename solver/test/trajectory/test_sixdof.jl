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
