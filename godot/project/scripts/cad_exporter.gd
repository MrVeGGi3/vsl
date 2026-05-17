class_name CadExporter

# Output paths (inside the Godot project)
const _CAD_DIR    := "res://cad/"
const _TEMPLATE   := "res://cad/rocket_template.scad"
const _STL_PRINT  := "res://cad/rocket_print.stl"
const _STL_CFD    := "res://cad/rocket_cfd.stl"
const _META_CFD   := "res://cad/cfd_mesh_meta.json"

# ── Public API ────────────────────────────────────────────────────────────────

# generate(params) → { ok, stl_print, stl_cfd, meta, error }
# Calls openscad twice: once for print mesh (fn=64), once for CFD mesh (fn=128, solid).
static func generate(params: Dictionary) -> Dictionary:
	var rkt: Dictionary  = params.get("rocket", {})
	var fins: Dictionary = rkt.get("fins", {})
	var thm: Dictionary  = params.get("thermal", {})
	var prop: Dictionary = params.get("propulsion", {})

	var defines := _build_defines(rkt, fins, thm, prop)

	var print_path := ProjectSettings.globalize_path(_STL_PRINT)
	var cfd_path   := ProjectSettings.globalize_path(_STL_CFD)
	var tpl_path   := ProjectSettings.globalize_path(_TEMPLATE)

	var err := _run_openscad(tpl_path, print_path, defines, false, 64)
	if err != "":
		return {ok = false, error = err}

	err = _run_openscad(tpl_path, cfd_path, defines, true, 128)
	if err != "":
		return {ok = false, error = err}

	var meta := _build_cfd_meta(rkt, fins, defines)
	_save_json(ProjectSettings.globalize_path(_META_CFD), meta)

	return {
		ok        = true,
		stl_print = print_path,
		stl_cfd   = cfd_path,
		meta      = meta,
	}

# Parse binary STL → ArrayMesh (OpenSCAD coords → Godot: X stays, Y→-Z, Z→Y, mm→m)
static func load_stl_binary(path: String) -> ArrayMesh:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	f.get_buffer(80)            # skip 80-byte header
	var n_tri := f.get_32()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n_tri * 3)
	norms.resize(n_tri * 3)
	for i in n_tri:
		var nx := f.get_float(); var ny := f.get_float(); var nz := f.get_float()
		var n := Vector3(nx, nz, -ny)
		for j in 3:
			var x := f.get_float(); var y := f.get_float(); var z := f.get_float()
			verts[i * 3 + j] = Vector3(x, z, -y) * 0.001  # mm→m, Y-up
			norms[i * 3 + j] = n
		f.get_16()               # attribute byte count
	f.close()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# ── Private Helpers ───────────────────────────────────────────────────────────

static func _build_defines(rkt: Dictionary, fins: Dictionary,
		thm: Dictionary, prop: Dictionary) -> Dictionary:
	var nose_idx := 0
	match rkt.get("nose_shape", "ogive"):
		"vonkarman": nose_idx = 1
		"conical":   nose_idx = 2

	# Estimate NAR motor diameter from peak thrust
	var thrusts: Array = prop.get("thrust_curve", {}).get("thrusts_n", [2100.0])
	var fmax := 0.0
	for t in thrusts:
		fmax = maxf(fmax, float(t))
	var motor_diam_mm := 38 if fmax > 1000.0 else (29 if fmax > 300.0 else 24)

	return {
		nose_type  = nose_idx,
		nose_len   = roundi(float(rkt.get("nose_length_m",   0.24)) * 1000.0),
		body_diam  = roundi(float(rkt.get("body_diameter_m", 0.08)) * 1000.0),
		body_len   = roundi(float(rkt.get("body_length_m",   1.20)) * 1000.0),
		wall_t     = float(thm.get("wall_thickness_mm", 2.0)),
		fin_n      = int(fins.get("n_fins",             4)),
		fin_cr     = roundi(float(fins.get("root_chord_m",        0.15)) * 1000.0),
		fin_ct     = roundi(float(fins.get("tip_chord_m",         0.05)) * 1000.0),
		fin_s      = roundi(float(fins.get("semi_span_m",          0.10)) * 1000.0),
		fin_sweep  = roundi(float(fins.get("le_sweep_m",           0.05)) * 1000.0),
		fin_xf     = roundi(float(fins.get("root_le_from_nose_m",  0.95)) * 1000.0),
		motor_diam = motor_diam_mm,
	}

static func _run_openscad(tpl: String, out: String,
		defines: Dictionary, solid: bool, fn_res: int) -> String:
	var args := PackedStringArray(["-o", out, tpl])
	for key in defines:
		args.append("-D")
		args.append("%s=%s" % [key, str(defines[key])])
	args.append("-D"); args.append("solid_mode=%d" % (1 if solid else 0))
	args.append("-D"); args.append("fn_res=%d" % fn_res)

	var output: Array = []
	var code := OS.execute("openscad", args, output, true)
	if code != 0:
		return "openscad saiu com código %d" % code
	if not FileAccess.file_exists(out):
		return "openscad não gerou o arquivo %s" % out.get_file()
	return ""

static func _build_cfd_meta(rkt: Dictionary, fins: Dictionary,
		defines: Dictionary) -> Dictionary:
	var d := float(rkt.get("body_diameter_m", 0.08))
	var l := float(rkt.get("nose_length_m",   0.24)) + float(rkt.get("body_length_m", 1.20))
	var s_ref := PI * (d * 0.5) * (d * 0.5)
	return {
		ref_diameter_m     = d,
		ref_area_m2        = s_ref,
		total_length_m     = l,
		fineness_ratio     = l / d,
		n_fins             = defines.get("fin_n",     4),
		fin_semi_span_m    = float(fins.get("semi_span_m", 0.10)),
		fin_root_chord_m   = float(fins.get("root_chord_m", 0.15)),
		note               = "Surface mesh for snappyHexMesh / OpenFOAM. fn_res=128, solid_mode=1.",
	}

static func _save_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
