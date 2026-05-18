# aero_geometry.jl — Aero coefficient estimation from sounding rocket geometry
# Usage: julia aero_geometry.jl --d=0.08 --nose_len=0.24 --body_len=1.2 \
#                                --n_fins=4 --cr=0.15 --ct=0.05 --span=0.10
# Outputs one key=value per line: cd0, cn_alpha, s_ref_m2

function get_f(key::String, default::Float64)::Float64
    prefix = "--$(key)="
    for a in ARGS
        startswith(a, prefix) && return parse(Float64, a[length(prefix)+1:end])
    end
    return default
end

function get_i(key::String, default::Int)::Int
    prefix = "--$(key)="
    for a in ARGS
        startswith(a, prefix) && return parse(Int, a[length(prefix)+1:end])
    end
    return default
end

function main()
    d        = get_f("d",        0.08)
    nose_len = get_f("nose_len", 0.24)
    body_len = get_f("body_len", 1.20)
    n_fins   = get_i("n_fins",   4)
    cr       = get_f("cr",       0.15)
    ct       = get_f("ct",       0.05)
    span     = get_f("span",     0.10)

    L     = nose_len + body_len
    r     = d / 2.0
    s_ref = π * r^2

    # Prandtl-Schlichting turbulent skin friction (flat plate)
    re_l = 5.0e6 * L          # Re/m × L (typical subsonic ascent)
    cf   = 0.455 / log10(re_l)^2.58

    # Body friction drag — nose approximated as 60% of cylinder of same length
    s_wet_body = π * d * body_len + 0.6 * π * d * nose_len
    cd_body    = cf * s_wet_body / s_ref

    # Base drag (empirical, subsonic)
    cd_base = 0.029 / sqrt(cf)

    # Fin drag — trapezoidal wetted area (both sides × n_fins)
    s_wet_fins = 2.0 * n_fins * (cr + ct) / 2.0 * span
    cd_fins    = cf * s_wet_fins / s_ref

    cd0 = cd_body + cd_base + cd_fins

    # Barrowman CNα (subsonic, zero AoA)
    cn_alpha_nose = 2.0
    k             = 1.0 + r / (r + span)
    ar            = 2.0 * span / (cr + ct)
    cn_alpha_fins = k * 4.0 * n_fins * (span / d)^2 / (1.0 + sqrt(1.0 + ar^2))
    cn_alpha      = cn_alpha_nose + cn_alpha_fins

    println("cd0=$(round(cd0; digits=5))")
    println("cn_alpha=$(round(cn_alpha; digits=4))")
    println("s_ref_m2=$(round(s_ref; digits=6))")
end

main()
