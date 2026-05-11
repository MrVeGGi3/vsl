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

"""
    vsl_trajectory_sixdof — C-callable 6-DOF ballistic trajectory (vacuum mode)

    Integrates a sounding rocket from t=0 to t_end_s under gravity only.
    No thrust, no drag. Writes the 13-element final state to `out_state`.

    out_state layout: [x,y,z, vx,vy,vz, q0,q1,q2,q3, p,q,r]
      positions in metres (ENU from launch site)
      velocities in m/s
      quaternion scalar-first, body→ENU

    Returns 0 on success, -1 on failure (check stderr for @error output).
"""
Base.@ccallable function vsl_trajectory_sixdof(
    x0::Cdouble,  y0::Cdouble,  z0::Cdouble,
    vx0::Cdouble, vy0::Cdouble, vz0::Cdouble,
    q00::Cdouble, q10::Cdouble, q20::Cdouble, q30::Cdouble,
    p0::Cdouble,  qr0::Cdouble, r0::Cdouble,
    mass_kg::Cdouble,
    t_end_s::Cdouble,
    out_state::Ptr{Cdouble},   # 13 Cdouble — final [x,y,z,vx,vy,vz,q0..q3,p,q,r]
    out_apogee_m::Ptr{Cdouble}, # 1  Cdouble — peak altitude (m above launch site)
)::Cint
    try
        # Minimal no-thrust, no-drag ThrustCurve (constant dry mass)
        tc = ThrustCurve(
            [0.0, t_end_s],
            [0.0, 0.0],
            [0.0, 0.0],
            mass_kg, mass_kg,
        )

        # Transparent AeroTable: 2×2 grid of zeros → no aerodynamic force
        mach_g  = [0.0, 5.0]
        aoa_g   = [0.0, 0.5]
        at = AeroTable(mach_g, aoa_g, zeros(2, 2), zeros(2, 2))

        I_diag = SMatrix{3,3,Float64,9}(diagm([1.0, 1.0, 1.0]))
        I_inv  = SMatrix{3,3,Float64,9}(diagm([1.0, 1.0, 1.0]))

        p = SixDOFParams(
            tc, at, I_diag, I_inv,
            1.0,       # S_ref — irrelevant in vacuum mode
            1.0, 0.5,  # xcp, xcg — irrelevant in vacuum mode
            2451545.0, # jd_epoch J2000
            0.0, 0.0,  # lat0, lon0 (generic launch site)
            0.0,       # launch_alt_m (sea level)
            150.0, 150.0, 4.0,  # space weather indices
            false,     # vacuum — no atmosphere
            sixdof_cache(),
        )

        u0 = [x0, y0, z0, vx0, vy0, vz0, q00, q10, q20, q30, p0, qr0, r0]
        tspan = (0.0, t_end_s)
        prob  = ODEProblem(sixdof!, u0, tspan, p)
        sol   = solve(prob, Tsit5(); reltol=1e-8, abstol=1e-8, save_everystep=true)

        if sol.retcode != ReturnCode.Success
            @error "vsl_trajectory_sixdof: solver failed" retcode=sol.retcode
            return Cint(-1)
        end

        # Write final state
        final = sol.u[end]
        for i in 1:13
            unsafe_store!(out_state, Cdouble(final[i]), i)
        end

        # Peak altitude = maximum z component across all saved steps
        apogee = maximum(u[3] for u in sol.u)
        unsafe_store!(out_apogee_m, Cdouble(apogee))

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
