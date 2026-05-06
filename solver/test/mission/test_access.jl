using Test
using Dates
using VSLSolver
using SatelliteToolboxTle

ISS_ACC_L1 = "1 25544U 98067A   24001.50000000  .00006000  00000-0  10000-3 0  9992"
ISS_ACC_L2 = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49507896 12343"
ISS_ACC_JD = datetime2julian(DateTime(2024, 1, 1, 12, 0, 0))

# Brasília ground station
const GS_LAT = -15.78
const GS_LON = -47.93

@testset "gmst_from_jd — J2000 reference" begin
    # At J2000.0, GMST ≈ 280.461° (IAU 1982)
    gmst_deg = rad2deg(gmst_from_jd(2451545.0))
    @test isapprox(gmst_deg, 280.461; atol=0.1)
end

@testset "latlon_to_ecef — known positions" begin
    # Greenwich meridian, equator → (R_E, 0, 0)
    r = latlon_to_ecef(0.0, 0.0)
    @test isapprox(norm(r), 6371.0; atol=0.01)
    @test isapprox(r[1], 6371.0; atol=0.01)
    @test isapprox(r[2], 0.0; atol=1e-8)

    # North Pole → (0, 0, R_E)
    r_pole = latlon_to_ecef(90.0, 0.0)
    @test isapprox(r_pole[3], 6371.0; atol=0.01)
    @test isapprox(sqrt(r_pole[1]^2 + r_pole[2]^2), 0.0; atol=1e-6)
end

@testset "access_windows — ISS from Brasília, 1 day" begin
    tle = read_tle(ISS_ACC_L1, ISS_ACC_L2)
    t, pos, _ = propagate_orbit(tle, 86400.0; step_s=30.0)

    wins = access_windows(pos, t, GS_LAT, GS_LON, ISS_ACC_JD; min_elev_deg=5.0)

    # ISS at 51.6° inclination covers Brasília — expect at least 2 passes in 24 h
    @test length(wins) >= 2

    for (ts, te, el) in wins
        @test te > ts
        @test el >= 5.0
    end

    # Average pass duration — ISS typical 2–15 min above 5° elevation
    n_wins   = length(wins)
    avg_dur  = sum(te - ts for (ts, te, _) in wins) / n_wins
    @test 120.0 <= avg_dur <= 900.0
    @info "ISS→Brasília access windows" n=n_wins avg_min=round(avg_dur / 60; digits=1)
end

@testset "access_windows — no passes (polar exclusion)" begin
    # ISS inclination 51.6° never reaches latitude −89°
    tle  = read_tle(ISS_ACC_L1, ISS_ACC_L2)
    t, pos, _ = propagate_orbit(tle, 86400.0; step_s=30.0)
    wins = access_windows(pos, t, -89.0, 0.0, ISS_ACC_JD; min_elev_deg=5.0)
    @test isempty(wins)
end
