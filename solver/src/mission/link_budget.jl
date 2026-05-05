"""
    link_budget(; pt_dbw, gt_dbi, gr_dbi, freq_hz, range_km, losses_db=0.0) -> NamedTuple

Friis link budget in dB.
Returns `(eirp, fspl, pr_dbw, cn0)` — all in dB or dBHz.
"""
function link_budget(;
    pt_dbw::Float64,
    gt_dbi::Float64,
    gr_dbi::Float64,
    freq_hz::Float64,
    range_km::Float64,
    losses_db::Float64=0.0,
)
    lambda   = 3e8 / freq_hz                    # wavelength (m)
    fspl     = 20log10(4π * range_km * 1e3 / lambda)  # free-space path loss (dB)
    eirp     = pt_dbw + gt_dbi
    pr_dbw   = eirp - fspl + gr_dbi - losses_db
    noise_k  = -228.6                           # Boltzmann (dBW/K/Hz)
    # C/N0 requires system noise temperature — placeholder
    cn0      = pr_dbw - noise_k                 # approximate (T_sys=0 dBK)

    return (eirp=eirp, fspl=fspl, pr_dbw=pr_dbw, cn0_dbhz=cn0)
end
