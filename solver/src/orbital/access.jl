using StaticArrays

const R_EARTH_KM = 6371.0

"""
    ground_track(positions, gmst0_rad) -> Vector{Tuple{Float64,Float64}}

Convert ECI position vectors to (latitude°, longitude°) ground track.
`gmst0_rad` is the Greenwich Mean Sidereal Time at epoch (radians).
"""
function ground_track(
    positions::Vector{Vec3},
    times_s::Vector{Float64},
    gmst0_rad::Float64,
)
    OMEGA_EARTH = 7.2921150e-5  # rad/s

    track = Vector{Tuple{Float64,Float64}}(undef, length(positions))
    @inbounds for (i, r) in enumerate(positions)
        gmst   = gmst0_rad + OMEGA_EARTH * times_s[i]
        lon    = atan(r[2], r[1]) - gmst
        lat    = asin(r[3] / norm(r))
        track[i] = (rad2deg(lat), rad2deg(lon))
    end
    return track
end

"""
    access_windows(positions, times_s, gs_lat_deg, gs_lon_deg; min_elev_deg=5.0)

Return time intervals (s) during which a ground station has line-of-sight
to the satellite above `min_elev_deg` elevation.
"""
function access_windows(
    positions::Vector{Vec3},
    times_s::Vector{Float64},
    gs_ecef::Vec3;
    min_elev_deg::Float64=5.0,
)
    min_elev = deg2rad(min_elev_deg)
    windows  = Tuple{Float64,Float64}[]
    in_pass  = false
    t_start  = 0.0

    @inbounds for (i, r_eci) in enumerate(positions)
        # simplified: treat ECI ≈ ECEF for elevation check (Phase 1 approximation)
        rho   = r_eci - gs_ecef
        elev  = asin(dot(rho, gs_ecef) / (norm(rho) * norm(gs_ecef)))

        if elev >= min_elev && !in_pass
            t_start = times_s[i]
            in_pass = true
        elseif elev < min_elev && in_pass
            push!(windows, (t_start, times_s[i]))
            in_pass = false
        end
    end
    in_pass && push!(windows, (t_start, times_s[end]))

    return windows
end
