### A Pluto.jl notebook ###
# v0.20.0
#
# Mission Analysis — Paper 1, Section 5
# Eclipse fraction, access windows, power and link budgets.

using Markdown
using InteractiveUtils

# ╔═╡ deps
begin
    using VSLSolver
    using SatelliteToolboxTle
    using SatelliteToolboxPropagation
    using CairoMakie
end

# ╔═╡ title
md"""
# Mission Analysis

Eclipse fraction · Ground station access · Power budget · Link budget
"""

# ╔═╡ setup
begin
    tle_line1 = "1 25544U 98067A   24001.50000000  .00006000  00000-0  10000-3 0  9999"
    tle_line2 = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49507896123456"
    tle  = read_tle(tle_line1, tle_line2)
    t, pos, vel = propagate_orbit(tle, 5400.0; step_s=10.0)
    nothing
end

# ╔═╡ eclipse
begin
    jd_epoch = 2460310.0  # approx Jan 1 2024
    ef = eclipse_fraction(pos, t, jd_epoch)
    md"Eclipse fraction: **$(round(ef * 100, digits=1))%**"
end

# ╔═╡ power
begin
    pb = power_budget(0.04, 0.30, ef)  # 400 cm², 30% efficiency
    md"""
    ## Power Budget (CubeSat 1U example)
    - Generated: $(round(pb.p_generated, digits=2)) W
    - Average: $(round(pb.p_avg, digits=2)) W
    - Sunlight: $(round(pb.sunlight_frac * 100, digits=1))%
    """
end

# ╔═╡ link
begin
    lb = link_budget(
        pt_dbw=0.0, gt_dbi=2.0, gr_dbi=10.0,
        freq_hz=437.5e6, range_km=800.0,
    )
    md"""
    ## Link Budget (UHF downlink)
    - EIRP: $(round(lb.eirp, digits=1)) dBW
    - FSPL: $(round(lb.fspl, digits=1)) dB
    - Pr: $(round(lb.pr_dbw, digits=1)) dBW
    - C/N₀: $(round(lb.cn0_dbhz, digits=1)) dBHz
    """
end
