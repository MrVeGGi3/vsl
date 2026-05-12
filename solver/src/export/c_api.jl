using SatelliteToolboxTle
using SatelliteToolboxPropagators
using DifferentialEquations
using StaticArrays
using LinearAlgebra

"""
C-callable API for the VSL main process (C++17).
All functions:
  - use Base.@ccallable
  - return Cint (0 = ok, negative = error)
  - never throw (wrap in try/catch)
  - accept only C-primitive types or Ptr{}
  - disable GC on the hot path
"""

# Sysimage loading happens at the C++ level via jl_init_with_image(bindir, path).
# This function is a health-check entry point called after Julia is already running.
Base.@ccallable function vsl_solver_init(::Cstring)::Cint
    return Cint(0)
end

Base.@ccallable function vsl_solver_shutdown()::Cvoid
    # Julia teardown is handled by jl_atexit_hook() in C++ — nothing to do here
    return nothing
end

# ── C-struct mirrors (layout must match julia_api.h exactly) ──────────────────

struct VslThrustCurveData
    times       :: Ptr{Cdouble}
    thrusts     :: Ptr{Cdouble}
    mass_flows  :: Ptr{Cdouble}
    mass_dry_kg :: Cdouble
    mass_wet_kg :: Cdouble
    n_points    :: Cint
end

struct VslAeroTableData
    mach_grid :: Ptr{Cdouble}
    aoa_grid  :: Ptr{Cdouble}
    cd_table  :: Ptr{Cdouble}   # row-major n_mach × n_aoa
    cn_table  :: Ptr{Cdouble}
    s_ref_m2  :: Cdouble
    xcp_m     :: Cdouble
    xcg_m     :: Cdouble
    n_mach    :: Cint
    n_aoa     :: Cint
end

# Reads a C ThrustCurveData struct and constructs a Julia ThrustCurve.
# copy() ensures Julia owns the data after C++ deallocates the struct.
function _build_thrust_curve(ptr::Ptr{VslThrustCurveData})::ThrustCurve
    d = unsafe_load(ptr)
    n = Int(d.n_points)
    ThrustCurve(
        copy(unsafe_wrap(Array, d.times,      n)),
        copy(unsafe_wrap(Array, d.thrusts,    n)),
        copy(unsafe_wrap(Array, d.mass_flows, n)),
        d.mass_wet_kg, d.mass_dry_kg,
    )
end

# Reads a C AeroTableData struct and returns (AeroTable, s_ref, xcp, xcg).
function _build_aero_table(ptr::Ptr{VslAeroTableData})
    d  = unsafe_load(ptr)
    nm = Int(d.n_mach); na = Int(d.n_aoa)
    mach = copy(unsafe_wrap(Array, d.mach_grid, nm))
    aoa  = copy(unsafe_wrap(Array, d.aoa_grid,  na))
    cd   = reshape(copy(unsafe_wrap(Array, d.cd_table, nm * na)), nm, na)
    cn   = reshape(copy(unsafe_wrap(Array, d.cn_table, nm * na)), nm, na)
    AeroTable(mach, aoa, cd, cn), d.s_ref_m2, d.xcp_m, d.xcg_m
end

# ── 6-DOF trajectory C entry point ────────────────────────────────────────────

Base.@ccallable function vsl_trajectory_sixdof(
    x0::Cdouble,  y0::Cdouble,  z0::Cdouble,
    vx0::Cdouble, vy0::Cdouble, vz0::Cdouble,
    q00::Cdouble, q10::Cdouble, q20::Cdouble, q30::Cdouble,
    p0::Cdouble,  qr0::Cdouble, r0::Cdouble,
    thrust_ptr::Ptr{VslThrustCurveData},
    aero_ptr::Ptr{VslAeroTableData},
    use_atmosphere::Cint,
    t_end_s::Cdouble,
    out_state::Ptr{Cdouble},    # 13 Cdouble — final [x,y,z,vx,vy,vz,q0..q3,p,q,r]
    out_apogee_m::Ptr{Cdouble}, # 1  Cdouble — peak altitude (m above z0)
)::Cint
    try
        tc            = _build_thrust_curve(thrust_ptr)
        at, s_ref, xcp, xcg = _build_aero_table(aero_ptr)

        # Inertia for 80 mm × 1.2 m rocket (~8 kg wet): Ix=Iy≈0.96 kg·m², Iz≈0.006 kg·m²
        I_diag = SMatrix{3,3,Float64,9}(diagm([0.96, 0.96, 0.006]))
        I_inv  = SMatrix{3,3,Float64,9}(diagm([1.0/0.96, 1.0/0.96, 1.0/0.006]))

        p = SixDOFParams(
            tc, at, I_diag, I_inv,
            s_ref, xcp, xcg,
            2451545.0,           # jd_epoch J2000
            0.0, 0.0, 0.0,       # lat0_deg, lon0_deg, launch_alt_m (sea-level)
            150.0, 150.0, 4.0,   # f107A, f107, ap (average solar activity)
            use_atmosphere != 0,
            sixdof_cache(),
        )

        u0   = [x0, y0, z0, vx0, vy0, vz0, q00, q10, q20, q30, p0, qr0, r0]
        prob = ODEProblem(sixdof!, u0, (0.0, t_end_s), p)
        sol  = solve(prob, Tsit5(); reltol=1e-8, abstol=1e-8, save_everystep=true)

        if sol.retcode != ReturnCode.Success
            @error "vsl_trajectory_sixdof: solver failed" retcode=sol.retcode
            return Cint(-1)
        end

        final = sol.u[end]
        for i in 1:13
            unsafe_store!(out_state, Cdouble(final[i]), i)
        end
        unsafe_store!(out_apogee_m, Cdouble(maximum(u[3] for u in sol.u)))
        return Cint(0)
    catch e
        @error "vsl_trajectory_sixdof failed" exception=e
        return Cint(-1)
    end
end

Base.@ccallable function vsl_propagate_orbit(
    tle_line1::Cstring,
    tle_line2::Cstring,
    duration_s::Cdouble,
    step_s::Cdouble,
    out_positions::Ptr{Cfloat},  # Float32[] x,y,z interleaved (km)
    out_count::Ptr{Cint},
)::Cint
    GC.enable(false)
    try
        l1   = unsafe_string(tle_line1)
        l2   = unsafe_string(tle_line2)
        tle  = read_tle(l1, l2)
        orbp = Propagators.init(Val(:SGP4), tle)

        times = 0.0:step_s:duration_s
        n     = length(times)
        unsafe_store!(out_count, Cint(n))

        ptr = out_positions
        @inbounds for t in times
            r, _ = Propagators.propagate!(orbp, t)
            unsafe_store!(ptr, Cfloat(r[1] * 1e-3)); ptr += sizeof(Cfloat)  # m → km
            unsafe_store!(ptr, Cfloat(r[2] * 1e-3)); ptr += sizeof(Cfloat)
            unsafe_store!(ptr, Cfloat(r[3] * 1e-3)); ptr += sizeof(Cfloat)
        end

        return Cint(0)
    catch e
        @error "vsl_propagate_orbit failed" exception=e
        return Cint(-1)
    finally
        GC.enable(true)
    end
end
