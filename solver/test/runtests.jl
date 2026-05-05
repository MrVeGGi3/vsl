using Test
using VSLSolver
using SatelliteToolboxTle
using SatelliteToolboxPropagators
using BenchmarkTools

@testset "VSLSolver" begin
    include("orbital/test_propagation.jl")
    include("orbital/test_maneuvers.jl")
end
