using Test
using LinearAlgebra
using VSLSolver
using SatelliteToolboxTle
using SatelliteToolboxPropagators
using BenchmarkTools

# ISS TLE (reference epoch — use for validation only, not current position)
const ISS_L1 = "1 25544U 98067A   24001.50000000  .00006000  00000-0  10000-3 0  9992"
const ISS_L2 = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49507896 12343"

@testset "SGP4 propagation" begin
    tle  = read_tle(ISS_L1, ISS_L2)
    orbp = Propagators.init(Val(:SGP4), tle)

    r, v = Propagators.propagate!(orbp, 0.0)

    # SatelliteToolboxPropagators returns meters and m/s
    # ISS LEO: |r| ≈ 6786 km = 6.786e6 m
    @test 6.5e6 < norm(r) < 7.0e6
    # ISS LEO: |v| ≈ 7.67 km/s = 7670 m/s
    @test 7.0e3 < norm(v) < 8.0e3
end

@testset "propagate_orbit output shape" begin
    tle    = read_tle(ISS_L1, ISS_L2)
    t, pos, vel = propagate_orbit(tle, 3600.0; step_s=60.0)

    @test length(t)   == 61
    @test length(pos) == 61
    @test length(vel) == 61
    @test pos[1] isa VSLSolver.Vec3
end

@testset "propagation benchmark" begin
    tle    = read_tle(ISS_L1, ISS_L2)
    orbp   = Propagators.init(Val(:SGP4), tle)
    n      = 5400  # 90 min at 1 s step
    times  = collect(Float64, 0:n-1)
    pos    = Vector{VSLSolver.Vec3}(undef, n)
    vel    = Vector{VSLSolver.Vec3}(undef, n)

    b = @benchmark propagate_orbit!($pos, $vel, $orbp, $times)
    @info "SGP4 propagation (5400 steps)" median=median(b)
    # Must complete one orbit in < 10 ms — adjust threshold after profiling
    @test median(b).time < 10e6  # 10 ms in nanoseconds
end
