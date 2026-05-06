using Test
using Dates
using VSLSolver
using SatelliteToolboxTle

# ISS TLE reused across test files — defined here without `const` to avoid
# redefinition errors when included after test_propagation.jl
ISS_ECL_L1 = "1 25544U 98067A   24001.50000000  .00006000  00000-0  10000-3 0  9992"
ISS_ECL_L2 = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49507896 12343"
ISS_ECL_JD = datetime2julian(DateTime(2024, 1, 1, 12, 0, 0))

@testset "in_eclipse — geometry checks" begin
    AU  = 1.496e8  # km
    sun = Vec3(1.0, 0.0, 0.0) * AU

    # Satellite on sun side — never in eclipse
    @test !in_eclipse(Vec3(7000.0, 0.0, 0.0), sun)

    # Satellite directly behind Earth, zero perpendicular distance — in shadow
    @test  in_eclipse(Vec3(-7000.0, 0.0, 0.0), sun)

    # Satellite behind Earth but lateral displacement > R_E — out of shadow
    @test !in_eclipse(Vec3(-1000.0, 7000.0, 0.0), sun)
end

@testset "eclipse_fraction — ISS orbit" begin
    tle  = read_tle(ISS_ECL_L1, ISS_ECL_L2)
    # 3 orbital periods at 30 s steps
    t, pos, _ = propagate_orbit(tle, 3 * 5556.0; step_s=30.0)

    frac = eclipse_fraction(pos, t, ISS_ECL_JD)

    # SMAD Ch.11: ISS at ~408 km, solar beta ≈ −23° on Jan 1
    @test 0.28 <= frac <= 0.45
    @info "ISS eclipse fraction" frac
end

@testset "eclipse_fraction — all sunlit orbit" begin
    # Artificial orbit: all positions on the sun-facing side
    n     = 120
    times = collect(Float64, 0:n-1) .* 60.0
    pos   = [Vec3(7000.0 + Float64(i), Float64(i) * 10, 0.0) for i in 1:n]

    # At J2000 the sun is roughly in the +x direction — all positions have x > 0
    frac = eclipse_fraction(pos, times, 2451545.0)
    @test frac == 0.0
end
