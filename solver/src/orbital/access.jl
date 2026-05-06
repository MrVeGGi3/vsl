using StaticArrays

const R_EARTH_KM      = 6371.0
const OMEGA_EARTH_RADS = 7.2921150e-5  # rad/s

"""
    gmst_from_jd(jd) -> Float64

Greenwich Mean Sidereal Time (radians) from Julian Date — IAU 1982 formula.
"""
function gmst_from_jd(jd::Float64)::Float64
    T   = (jd - 2451545.0) / 36525.0
    deg = 280.46061837 + 360.98564736629 * (jd - 2451545.0) +
          0.000387933 * T^2 - T^3 / 38710000.0
    return deg2rad(mod(deg, 360.0))
end

"""
    latlon_to_ecef(lat_deg, lon_deg) -> Vec3

Spherical-Earth geodetic lat/lon (degrees) → ECEF position (km).
"""
function latlon_to_ecef(lat_deg::Float64, lon_deg::Float64)::Vec3
    lat = deg2rad(lat_deg)
    lon = deg2rad(lon_deg)
    return Vec3(
        R_EARTH_KM * cos(lat) * cos(lon),
        R_EARTH_KM * cos(lat) * sin(lon),
        R_EARTH_KM * sin(lat),
    )
end

"""
    ground_track(positions, times_s, jd_epoch) -> Vector{Tuple{Float64,Float64}}

Convert ECI positions to (lat°, lon°) using proper GMST rotation.
"""
function ground_track(
    positions::Vector{Vec3},
    times_s::Vector{Float64},
    jd_epoch::Float64,
)
    gmst0 = gmst_from_jd(jd_epoch)
    track = Vector{Tuple{Float64,Float64}}(undef, length(positions))
    @inbounds for (i, r) in enumerate(positions)
        gmst    = gmst0 + OMEGA_EARTH_RADS * times_s[i]
        lon     = atan(r[2], r[1]) - gmst
        lat     = asin(r[3] / norm(r))
        track[i] = (rad2deg(lat), rad2deg(lon))
    end
    return track
end

"""
    access_windows(positions, times_s, gs_lat_deg, gs_lon_deg, jd_epoch;
                   min_elev_deg=5.0) -> Vector{Tuple{Float64,Float64,Float64}}

Access windows (t_start_s, t_end_s, max_elev_deg) for a ground station,
accounting for Earth rotation via GMST.
"""
function access_windows(
    positions::Vector{Vec3},
    times_s::Vector{Float64},
    gs_lat_deg::Float64,
    gs_lon_deg::Float64,
    jd_epoch::Float64;
    min_elev_deg::Float64 = 5.0,
)
    min_elev = deg2rad(min_elev_deg)
    gmst0    = gmst_from_jd(jd_epoch)
    gs_ecef  = latlon_to_ecef(gs_lat_deg, gs_lon_deg)
    gs_unit  = gs_ecef / norm(gs_ecef)  # outward-pointing unit normal at GS

    windows = Tuple{Float64,Float64,Float64}[]
    in_pass = false
    t_start = 0.0
    max_e   = 0.0

    @inbounds for (i, r_eci) in enumerate(positions)
        # Rotate ECI → ECEF: R_z(-GMST)
        gmst   = gmst0 + OMEGA_EARTH_RADS * times_s[i]
        cg, sg = cos(gmst), sin(gmst)
        r_ecef = Vec3(
             cg * r_eci[1] + sg * r_eci[2],
            -sg * r_eci[1] + cg * r_eci[2],
             r_eci[3],
        )

        rho      = r_ecef - gs_ecef
        rho_norm = norm(rho)
        elev     = asin(dot(rho, gs_unit) / rho_norm)

        if elev >= min_elev
            max_e = max(max_e, elev)
            if !in_pass
                t_start = times_s[i]
                in_pass = true
            end
        elseif in_pass
            push!(windows, (t_start, times_s[i], rad2deg(max_e)))
            in_pass = false
            max_e   = 0.0
        end
    end
    in_pass && push!(windows, (t_start, times_s[end], rad2deg(max_e)))

    return windows
end
