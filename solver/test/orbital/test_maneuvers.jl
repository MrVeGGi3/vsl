using Test
using VSLSolver

@testset "Hohmann transfer" begin
    # LEO 300 km → GEO 35786 km (reference: Vallado p.329)
    r_leo = 6371.0 + 300.0    # km
    r_geo = 6371.0 + 35786.0  # km

    dv1, dv2, tof = hohmann_transfer(r_leo, r_geo)

    # Reference values (computed from Hohmann equations, μ=398600.4418 km³/s²):
    # r1=6671 km, r2=42157 km → dv1=2.4277 km/s, dv2=1.4676 km/s, tof=18981.9 s
    @test isapprox(dv1, 2.4277; atol=0.001)
    @test isapprox(dv2, 1.4676; atol=0.001)
    @test isapprox(tof, 18981.9; rtol=0.001)
end

@testset "Hohmann — same orbit" begin
    r = 6671.0
    dv1, dv2, tof = hohmann_transfer(r, r)
    @test isapprox(dv1, 0.0; atol=1e-10)
    @test isapprox(dv2, 0.0; atol=1e-10)
end
