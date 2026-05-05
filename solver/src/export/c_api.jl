using SatelliteToolboxTle
using SatelliteToolboxPropagators

"""
C-callable API for the VSL main process (C++17).
All functions:
  - use Base.@ccallable
  - return Cint (0 = ok, negative = error)
  - never throw (wrap in try/catch)
  - accept only C-primitive types or Ptr{}
  - disable GC on the hot path
"""

# Phase 3: load a PackageCompiler sysimage for fast startup.
# Phase 2: bare Julia — sysimage_path is ignored, packages load from depot.
Base.@ccallable function vsl_solver_init(sysimage_path::Cstring)::Cint
    try
        path = unsafe_string(sysimage_path)
        if !isempty(path) && isfile(path)
            # PackageCompiler sysimage loading — implemented in Phase 3
            @warn "vsl_solver_init: sysimage support not yet implemented" path
        end
        return Cint(0)
    catch e
        @error "vsl_solver_init failed" exception=e
        return Cint(-1)
    end
end

Base.@ccallable function vsl_solver_shutdown()::Cvoid
    # Julia teardown is handled by jl_atexit_hook() in C++ — nothing to do here
    return nothing
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
