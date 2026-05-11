using Interpolations
using StaticArrays

"""
    AeroTable{IT}

Bilinear aerodynamic look-up table over (Mach, angle-of-attack [rad]).

Interpolants are created at construction time with `Gridded(Linear())` so
evaluation `_itp_CD(mach, aoa)` is allocation-free at runtime.
"""
struct AeroTable{IT}
    mach_grid::Vector{Float64}  # Mach numbers (ascending)
    aoa_grid::Vector{Float64}   # angle-of-attack (rad, ascending)
    _itp_CD::IT
    _itp_CN::IT
end

"""
    AeroTable(mach, aoa_rad, CD, CN) -> AeroTable

Build an `AeroTable` from raw coefficient matrices.

`CD` and `CN` are matrices of size `(length(mach), length(aoa_rad))`.
"""
function AeroTable(
    mach::Vector{Float64},
    aoa_rad::Vector{Float64},
    CD::Matrix{Float64},
    CN::Matrix{Float64},
)
    itp_CD = interpolate((mach, aoa_rad), CD, Gridded(Linear()))
    itp_CN = interpolate((mach, aoa_rad), CN, Gridded(Linear()))
    AeroTable(mach, aoa_rad, itp_CD, itp_CN)
end

"""
    aero_forces(table, mach, aoa_rad, q_Pa, S_ref_m2) -> SVector{3,Float64}

Aerodynamic force in the **body frame** (N).

Convention:
- Body z-axis = rocket long axis, pointing toward nose
- Velocity in body frame: v_body = |v| · [sin α, 0, cos α]
- Positive AoA α in the body xz-plane
- Returned as [Fx, 0, Fz] (y assumed zero for 2-D AoA)
"""
function aero_forces(
    table::AeroTable,
    mach::Float64,
    aoa_rad::Float64,
    q_Pa::Float64,
    S_ref_m2::Float64,
)::SVector{3,Float64}
    # Clamp to table bounds — prevents BoundsError for extreme AoA / Mach
    mach_c = clamp(mach,    table.mach_grid[1], table.mach_grid[end])
    aoa_c  = clamp(aoa_rad, table.aoa_grid[1],  table.aoa_grid[end])
    CD = table._itp_CD(mach_c, aoa_c)
    CN = table._itp_CN(mach_c, aoa_c)
    qS = q_Pa * S_ref_m2
    sα, cα = sin(aoa_rad), cos(aoa_rad)
    Fx = (-CD * sα + CN * cα) * qS
    Fz = (-CD * cα - CN * sα) * qS
    SVector(Fx, 0.0, Fz)
end
