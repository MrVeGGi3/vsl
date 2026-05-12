module VSLSolver

using Dates
using LinearAlgebra
using StaticArrays
using SatelliteToolboxTle
using SatelliteToolboxPropagators
using SatelliteToolboxCelestialBodies

const Vec3 = SVector{3, Float64}  # position / velocity (km, km/s)
const Vec6 = SVector{6, Float64}  # orbital state [r; v]
const Quat = SVector{4, Float64}  # attitude quaternion

include("orbital/propagation.jl")
include("orbital/maneuvers.jl")
include("orbital/access.jl")
include("mission/eclipse.jl")
include("mission/power_budget.jl")
include("mission/link_budget.jl")
include("mission/report.jl")
include("mdo/engine.jl")
include("export/c_api.jl")

# 6-DOF sounding rocket trajectory
include("trajectory/propulsion.jl")
include("trajectory/atmosphere.jl")
include("trajectory/aerodynamics.jl")
include("trajectory/sixdof.jl")

export Vec3, Vec6, Quat
export propagate_orbit, propagate_orbit!
export hohmann_transfer, lambert_problem
export gmst_from_jd, latlon_to_ecef, ground_track, access_windows
export eclipse_fraction, eclipse_periods, in_eclipse
export power_budget
export link_budget
export MissionReport, mission_report, to_json
export ThrustCurve, thrust_at
export AtmosphereState, nrlmsise00_at
export AeroTable, aero_forces
export SixDOFCache, SixDOFParams, sixdof!, sixdof_cache
export VslThrustCurveData, VslAeroTableData

end # module VSLSolver
