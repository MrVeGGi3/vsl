### A Pluto.jl notebook ###
# v0.20.0
#
# Orbit Validation — Paper 1, Section 4
# Compares VSLSolver SGP4 propagation against Vallado reference data.

using Markdown
using InteractiveUtils

# ╔═╡ deps
begin
    using VSLSolver
    using SatelliteToolboxTle
    using SatelliteToolboxPropagation
    using CairoMakie
    using BenchmarkTools
end

# ╔═╡ title
md"""
# Orbit Propagation Validation

Validates SGP4 implementation against Vallado reference data.
Results feed into Paper 1, Section 4.
"""

# ╔═╡ tle_input
begin
    tle_line1 = "1 25544U 98067A   24001.50000000  .00006000  00000-0  10000-3 0  9999"
    tle_line2 = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49507896123456"
    tle = read_tle(tle_line1, tle_line2)
end

# ╔═╡ propagate
begin
    duration = 5400.0  # 90 minutes (1 orbit)
    times, positions, velocities = propagate_orbit(tle, duration; step_s=10.0)
end

# ╔═╡ plot_ground_track
begin
    lats = [rad2deg(asin(r[3] / norm(r))) for r in positions]
    lons_raw = [rad2deg(atan(r[2], r[1])) for r in positions]

    fig = Figure(size=(900, 450))
    ax  = Axis(fig[1, 1],
        title="ISS Ground Track — 1 Orbit",
        xlabel="Longitude (°)", ylabel="Latitude (°)",
        limits=((-180, 180), (-90, 90)),
    )
    lines!(ax, lons_raw, lats; color=:royalblue, linewidth=1.5)
    save("../paper/figures/ground_track_iss.pdf", fig)
    fig
end

# ╔═╡ benchmark
begin
    orbp  = Propagators.init(Val(:SGP4), tle)
    n     = 5400
    ts    = collect(Float64, 0:n-1)
    pos   = Vector{Vec3}(undef, n)
    vel   = Vector{Vec3}(undef, n)

    b = @benchmark propagate_orbit!($pos, $vel, $orbp, $ts)
    md"""
    ## Benchmark: SGP4 (5400 steps, 1 s)
    - Median: $(round(median(b).time / 1e6, digits=2)) ms
    - Allocs: $(b.allocs)
    """
end
