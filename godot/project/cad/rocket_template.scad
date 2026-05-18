// VSL — Parametric Rocket CAD Template
// All dimensions in mm.  Override via: openscad -D "param=value"
// Z = rocket axis (Z=0 at nose tip, +Z toward tail)

// ── Parameters ───────────────────────────────────────────────────────────────
nose_type   = 0;    // 0=ogive  1=vonkarman  2=conical
nose_len    = 240;  // nose cone length [mm]
body_diam   = 80;   // outer body diameter [mm]
body_len    = 1200; // body tube length [mm] (nose not included)
wall_t      = 2;    // wall thickness [mm]
fin_n       = 4;    // number of fins
fin_cr      = 150;  // root chord [mm]
fin_ct      = 50;   // tip chord [mm]
fin_s       = 100;  // semi-span [mm]
fin_sweep   = 50;   // leading edge sweep [mm]
fin_xf      = 950;  // root LE distance from nose tip [mm]
fin_t       = 3;    // fin thickness [mm]
motor_diam  = 38;   // motor mount inner diameter [mm] (NAR standard)
motor_len   = 120;  // motor mount length [mm]
solid_mode  = 0;    // 0=hollow body (print)  1=solid body (CFD)
fn_res      = 64;   // arc/circle resolution

// ── Derived ──────────────────────────────────────────────────────────────────
R = body_diam / 2;

// ── Nose Profile Functions ────────────────────────────────────────────────────
// Each returns a list of [r, z] points from tip (r=0,z=0) to base (r=R,z=nose_len)

function _ogive_pts(n, r, l) =
    let(rho = (r*r + l*l) / (2*r))
    [for (i = [0:n])
        let(z  = l * i / n,
            rv = sqrt(max(0, rho*rho - (l - z)*(l - z))) - (rho - r))
        [rv, z]];

function _vonkarman_pts(n, r, l) =
    [for (i = [0:n])
        let(td = (i == 0) ? 0.001 : (i == n) ? 179.999 : acos(max(-1, min(1, 1 - 2*i/n))),
            tr = td * PI / 180,
            rv = r / sqrt(PI) * sqrt(max(0, tr - sin(2 * td) * PI / 180 / 2)))
        [rv, l * i / n]];

function _cone_pts(n, r, l) =
    [for (i = [0:n]) [r * i / n, l * i / n]];

function nose_profile(t, n, r, l) =
    (t == 1) ? _vonkarman_pts(n, r, l) :
    (t == 2) ? _cone_pts(n, r, l)      :
               _ogive_pts(n, r, l);

// ── Modules ──────────────────────────────────────────────────────────────────

module nose_cone() {
    pts = nose_profile(nose_type, fn_res, R, nose_len);
    rotate_extrude($fn = fn_res)
    polygon(concat([[0, 0]], pts, [[0, nose_len]]));
}

module body_tube() {
    translate([0, 0, nose_len])
    if (solid_mode) {
        cylinder(h = body_len, r = R, $fn = fn_res);
    } else {
        difference() {
            cylinder(h = body_len, r = R, $fn = fn_res);
            translate([0, 0, -1])
            cylinder(h = body_len + 2, r = R - wall_t, $fn = fn_res);
        }
    }
}

// Fin polygon in XY (X=chord, Y=span), multmatrix orients it so that
//   chord → world Z (axial), span → world X (radial), thickness → world Y (tangential)
module _fin_shape() {
    multmatrix([[0, 1, 0, 0],
                [0, 0, 1, 0],
                [1, 0, 0, 0],
                [0, 0, 0, 1]])
    linear_extrude(fin_t, center = true)
    polygon([[0,       0    ],
             [fin_cr,  0    ],
             [fin_sweep + fin_ct, fin_s],
             [fin_sweep,          fin_s]]);
}

module fins() {
    for (i = [0 : fin_n - 1])
        rotate([0, 0, 360 / fin_n * i])
        translate([R, 0, fin_xf])
        _fin_shape();
}

module motor_mount() {
    z_pos = nose_len + body_len - motor_len;
    translate([0, 0, z_pos])
    difference() {
        cylinder(h = motor_len, r = R, $fn = fn_res);
        translate([0, 0, -1])
        cylinder(h = motor_len + 2, r = motor_diam / 2, $fn = fn_res);
    }
}

// ── Assembly ─────────────────────────────────────────────────────────────────
nose_cone();
body_tube();
fins();
motor_mount();
