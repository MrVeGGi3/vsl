#!/usr/bin/env julia
# Build a Julia sysimage for the VSL solver (local dev path).
#
# Run from solver/ with: julia --project=. scripts/build_sysimage.jl
#
# Output: build/vsl_solver.so (~200–400 MB)
# C++ init: jl_init_with_image(julia_bindir, "solver/build/vsl_solver.so")
#
# Docker/production: docker compose run julia-compile  (uses create_library instead)

using PackageCompiler

out = joinpath(@__DIR__, "..", "build", "vsl_solver.so")
mkpath(dirname(out))

@info "Building sysimage..." output=out
t0 = time()

create_sysimage(
    [:VSLSolver];
    sysimage_path = out,
    precompile_execution_file = joinpath(@__DIR__, "..", "test", "precompile_hints.jl"),
)

elapsed = round(time() - t0; digits=1)
@info "Sysimage ready" path=out elapsed_s=elapsed
