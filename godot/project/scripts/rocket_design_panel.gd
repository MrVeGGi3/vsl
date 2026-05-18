extends PanelContainer

const PANEL_W := 265.0
const PANEL_H := 560.0
const G0      := 9.80665

var _params: Dictionary = {}
var _dragging := false
var _drag_offset := Vector2.ZERO

var _fmax_field:      LineEdit
var _isp_field:       LineEdit
var _tb_field:        LineEdit
var _mass_dry_field:  LineEdit
var _mass_wet_field:  LineEdit
var _impulse_label:   Label

var _diam_field:      LineEdit
var _len_field:       LineEdit
var _nose_option:     OptionButton
var _nose_len_field:  LineEdit

var _fin_n_field:     LineEdit
var _fin_cr_field:    LineEdit
var _fin_ct_field:    LineEdit
var _fin_s_field:     LineEdit
var _fin_sweep_field: LineEdit
var _fin_xf_field:    LineEdit

var _xcp_field:       LineEdit
var _xcg_field:       LineEdit
var _stability_label: Label

var _i_lat_field:     LineEdit
var _i_ax_field:      LineEdit

var _status_label:    Label

var _cad_status_label: Label
var _export_btn:       Button
var _generate_btn:     Button
var _cad_mesh:         ArrayMesh = null
var _preview_window:   Window    = null
var _cad_thread:       Thread    = null
var _aero_thread:      Thread    = null

var _cam:          Camera3D = null
var _orbit_center: Vector3  = Vector3.ZERO
var _orbit_r:      float    = 1.0
var _orbit_r_min:  float    = 0.05
var _orbit_r_max:  float    = 10.0
var _orbit_quat:   Quaternion = Quaternion.IDENTITY
var _cad_gizmo:    Control  = null

func _ready() -> void:
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)

	var outer := VBoxContainer.new()
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(outer)

	_build_header(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE
	outer.add_child(scroll)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	_build_propulsion_section(inner)
	_build_body_section(inner)
	_build_fin_section(inner)
	_build_aero_section(inner)
	_build_inertia_section(inner)
	_build_cad_section(inner)

	var apply_btn := Button.new()
	apply_btn.text = "Apply & Save"
	apply_btn.focus_mode = Control.FOCUS_NONE
	apply_btn.pressed.connect(_on_apply)
	inner.add_child(apply_btn)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 10)
	inner.add_child(_status_label)

	_load_and_populate()

func _fit_to_viewport() -> void:
	var vp := get_viewport_rect().size
	var h = min(PANEL_H, vp.y - 44.0)
	set_size(Vector2(PANEL_W, h))
	var x = clamp(290.0, 0.0, max(0.0, vp.x - PANEL_W))
	var y = clamp(position.y, 40.0, max(40.0, vp.y - h))
	set_position(Vector2(x, y))

func _build_header(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 26)
	hbox.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(hbox)

	var title := Label.new()
	title.text = "ROCKET DESIGN"
	title.add_theme_font_size_override("font_size", 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(24, 0)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): visible = false)
	hbox.add_child(close_btn)

	parent.add_child(HSeparator.new())
	hbox.gui_input.connect(_on_titlebar_input)

func _on_titlebar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_drag_offset = get_global_mouse_position() - global_position
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		get_viewport().set_input_as_handled()

func _build_propulsion_section(parent: VBoxContainer) -> void:
	_section_label(parent, "PROPULSION")
	var grid := _new_grid(parent)
	_fmax_field     = _field_row(grid, "F max", "N")
	_isp_field      = _field_row(grid, "Isp", "s")
	_tb_field       = _field_row(grid, "Burn time", "s")
	_mass_dry_field = _field_row(grid, "Mass dry", "kg")
	_mass_wet_field = _field_row(grid, "Mass wet", "kg")
	var grid2 := _new_grid(parent)
	_impulse_label = _display_row(grid2, "I total", "N·s")
	_fmax_field.text_changed.connect(_update_derived_propulsion.unbind(1))
	_tb_field.text_changed.connect(_update_derived_propulsion.unbind(1))
	parent.add_child(HSeparator.new())

func _build_body_section(parent: VBoxContainer) -> void:
	_section_label(parent, "ROCKET BODY")
	var grid := _new_grid(parent)
	_diam_field     = _field_row(grid, "Diameter", "cm")
	_len_field      = _field_row(grid, "Length", "m")
	_nose_len_field = _field_row(grid, "Nose length", "cm")
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)
	var lbl := Label.new()
	lbl.text = "Nose shape"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)
	_nose_option = OptionButton.new()
	_nose_option.add_item("ogive",     0)
	_nose_option.add_item("vonkarman", 1)
	_nose_option.add_item("conical",   2)
	_nose_option.focus_mode = Control.FOCUS_NONE
	hbox.add_child(_nose_option)
	_diam_field.text_changed.connect(_update_barrowman.unbind(1))
	_nose_len_field.text_changed.connect(_update_barrowman.unbind(1))
	_nose_option.item_selected.connect(_update_barrowman.unbind(1))
	parent.add_child(HSeparator.new())

func _build_fin_section(parent: VBoxContainer) -> void:
	_section_label(parent, "FINS (Barrowman)")
	var grid := _new_grid(parent)
	_fin_n_field     = _field_row(grid, "N fins",    "")
	_fin_cr_field    = _field_row(grid, "Root chord", "cm")
	_fin_ct_field    = _field_row(grid, "Tip chord",  "cm")
	_fin_s_field     = _field_row(grid, "Semi-span",  "cm")
	_fin_sweep_field = _field_row(grid, "LE sweep",   "cm")
	_fin_xf_field    = _field_row(grid, "Root LE x",  "m")
	for f: LineEdit in [_fin_n_field, _fin_cr_field, _fin_ct_field,
						_fin_s_field, _fin_sweep_field, _fin_xf_field]:
		f.text_changed.connect(_update_barrowman.unbind(1))
	parent.add_child(HSeparator.new())

func _build_aero_section(parent: VBoxContainer) -> void:
	_section_label(parent, "AERODYNAMICS")
	var grid := _new_grid(parent)
	_xcp_field = _field_row(grid, "xCP", "m")
	_xcg_field = _field_row(grid, "xCG", "m")
	var grid2 := _new_grid(parent)
	_stability_label = _display_row(grid2, "Stability", "cal")
	_xcp_field.text_changed.connect(_update_derived_aero.unbind(1))
	_xcg_field.text_changed.connect(_update_derived_aero.unbind(1))
	_diam_field.text_changed.connect(_update_derived_aero.unbind(1))
	parent.add_child(HSeparator.new())

func _build_inertia_section(parent: VBoxContainer) -> void:
	_section_label(parent, "INERTIA")
	var grid := _new_grid(parent)
	_i_lat_field = _field_row(grid, "I lateral", "kg·m²")
	_i_ax_field  = _field_row(grid, "I axial",   "kg·m²")
	parent.add_child(HSeparator.new())

func _build_cad_section(parent: VBoxContainer) -> void:
	_section_label(parent, "CAD / STL")
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	parent.add_child(hbox)

	_generate_btn = Button.new()
	_generate_btn.text = "Gerar CAD"
	_generate_btn.focus_mode = Control.FOCUS_NONE
	_generate_btn.pressed.connect(_on_generate_cad)
	hbox.add_child(_generate_btn)

	_export_btn = Button.new()
	_export_btn.text = "Export STL"
	_export_btn.focus_mode = Control.FOCUS_NONE
	_export_btn.disabled = true
	_export_btn.pressed.connect(_on_export_stl)
	hbox.add_child(_export_btn)

	_cad_status_label = Label.new()
	_cad_status_label.add_theme_font_size_override("font_size", 10)
	parent.add_child(_cad_status_label)

# ── Data ───────────────────────────────────────────────────────────────────────

func _load_and_populate() -> void:
	_params = MissionParamsIO.load_params()
	if _params.is_empty():
		_set_status("No params file")
		return
	_populate_fields()
	_set_status("")

func _populate_fields() -> void:
	var prop: Dictionary = _params.get("propulsion", {})
	var tc: Dictionary   = prop.get("thrust_curve", {})
	var thrusts: Array   = tc.get("thrusts_n", [0.0, 2100.0, 1800.0, 0.0])
	var times: Array     = tc.get("times_s",   [0.0, 0.1,    3.0,    3.05])
	var f_max := 0.0
	for t in thrusts:
		f_max = maxf(f_max, float(t))
	var t_b := float(times[times.size() - 2]) if times.size() >= 2 else 3.0
	_fmax_field.text     = "%.0f" % f_max
	_isp_field.text      = str(float(prop.get("isp_s",       220.0)))
	_tb_field.text       = "%.2f" % t_b
	_mass_dry_field.text = str(float(prop.get("mass_dry_kg",   6.2)))
	_mass_wet_field.text = str(float(prop.get("mass_wet_kg",   8.0)))
	_update_derived_propulsion()

	var rkt: Dictionary = _params.get("rocket", {})
	_diam_field.text     = "%.1f" % (float(rkt.get("body_diameter_m", 0.08)) * 100.0)
	_len_field.text      = str(float(rkt.get("body_length_m",   1.20)))
	_nose_len_field.text = "%.1f" % (float(rkt.get("nose_length_m",   0.24)) * 100.0)
	var nose: String = rkt.get("nose_shape", "ogive")
	match nose:
		"vonkarman": _nose_option.selected = 1
		"conical":   _nose_option.selected = 2
		_:           _nose_option.selected = 0

	var fins: Dictionary = rkt.get("fins", {})
	_fin_n_field.text     = str(int(fins.get("n_fins", 4)))
	_fin_cr_field.text    = "%.1f" % (float(fins.get("root_chord_m", 0.15)) * 100.0)
	_fin_ct_field.text    = "%.1f" % (float(fins.get("tip_chord_m",  0.05)) * 100.0)
	_fin_s_field.text     = "%.1f" % (float(fins.get("semi_span_m",  0.10)) * 100.0)
	_fin_sweep_field.text = "%.1f" % (float(fins.get("le_sweep_m",   0.05)) * 100.0)
	_fin_xf_field.text    = str(float(fins.get("root_le_from_nose_m", 0.95)))

	var aero: Dictionary = rkt.get("aero", {})
	_xcp_field.text = str(float(aero.get("xcp_m", 0.85)))
	_xcg_field.text = str(float(aero.get("xcg_m", 0.55)))

	_update_barrowman()
	_update_derived_aero()

	_i_lat_field.text = str(float(rkt.get("inertia_lateral_kgm2", 0.96)))
	_i_ax_field.text  = str(float(rkt.get("inertia_axial_kgm2",  0.006)))

func _update_derived_propulsion() -> void:
	var f_max := float(_fmax_field.text) if _fmax_field.text.is_valid_float() else 0.0
	var t_b   := float(_tb_field.text)   if _tb_field.text.is_valid_float()   else 0.0
	_impulse_label.text = "%.0f" % (f_max * t_b)

func _update_barrowman() -> void:
	var N := int(_fin_n_field.text) if _fin_n_field.text.is_valid_int() else 0
	if N <= 0:
		return

	var Cr := float(_fin_cr_field.text)    / 100.0 if _fin_cr_field.text.is_valid_float()    else 0.0
	var Ct := float(_fin_ct_field.text)    / 100.0 if _fin_ct_field.text.is_valid_float()    else 0.0
	var s  := float(_fin_s_field.text)     / 100.0 if _fin_s_field.text.is_valid_float()     else 0.0
	var sw := float(_fin_sweep_field.text) / 100.0 if _fin_sweep_field.text.is_valid_float() else 0.0
	var xf := float(_fin_xf_field.text)             if _fin_xf_field.text.is_valid_float()    else 0.0

	var d_cm  := float(_diam_field.text)     if _diam_field.text.is_valid_float()     else 8.0
	var Ln_cm := float(_nose_len_field.text) if _nose_len_field.text.is_valid_float() else 24.0
	var d  := d_cm  / 100.0
	var Ln := Ln_cm / 100.0
	var r  := d / 2.0

	if Cr <= 0.0 or s <= 0.0 or d <= 0.0 or Ln <= 0.0:
		return

	# Nose CP (Barrowman 1966 — subsonic, zero AoA)
	var nose_k: float
	match _nose_option.selected:
		1: nose_k = 0.500  # von Kármán
		2: nose_k = 0.667  # conical
		_: nose_k = 0.466  # tangent ogive
	var xCP_nose := nose_k * Ln

	# Fin CNα
	var cr_ct := Cr + Ct
	var K     := 1.0 + r / (r + s)
	var ar    := 2.0 * s / cr_ct
	var denom := 1.0 + sqrt(1.0 + ar * ar)
	var CNa_fin := K * 4.0 * float(N) * pow(s / d, 2.0) / denom

	# Fin CP from root LE (Barrowman 1966, Eq. 4.15)
	var xf_local := sw * (Cr + 2.0 * Ct) / (3.0 * cr_ct) \
				  + (1.0 / 6.0) * (cr_ct - Cr * Ct / cr_ct)
	var xCP_fin := xf + xf_local

	# Weighted sum
	var CNa_nose := 2.0
	var xCP      := (CNa_nose * xCP_nose + CNa_fin * xCP_fin) / (CNa_nose + CNa_fin)

	_xcp_field.text = "%.3f" % xCP

func _update_derived_aero() -> void:
	var xcp  := float(_xcp_field.text)  if _xcp_field.text.is_valid_float()  else 0.0
	var xcg  := float(_xcg_field.text)  if _xcg_field.text.is_valid_float()  else 0.0
	var d_cm := float(_diam_field.text) if _diam_field.text.is_valid_float() else 8.0
	var d_m  := d_cm / 100.0
	_stability_label.text = "%.2f" % ((xcp - xcg) / d_m) if d_m > 0.0 else "—"

func _on_apply() -> void:
	if _params.is_empty():
		_params = MissionParamsIO.load_params()

	var f_max     := float(_fmax_field.text)
	var isp       := float(_isp_field.text)
	var t_b       := float(_tb_field.text)
	var mass_flow := f_max / (isp * G0) if isp > 0.0 else 0.0

	if not _params.has("propulsion"):
		_params["propulsion"] = {}
	_params["propulsion"]["isp_s"]       = isp
	_params["propulsion"]["mass_dry_kg"] = float(_mass_dry_field.text)
	_params["propulsion"]["mass_wet_kg"] = float(_mass_wet_field.text)
	_params["propulsion"]["thrust_curve"] = {
		"times_s":        [0.0, 0.1, t_b, t_b + 0.05],
		"thrusts_n":      [0.0, f_max, f_max, 0.0],
		"mass_flows_kgs": [0.0, mass_flow, mass_flow, 0.0],
	}

	var d_m := float(_diam_field.text) / 100.0
	if not _params.has("rocket"):
		_params["rocket"] = {}
	_params["rocket"]["body_diameter_m"]      = d_m
	_params["rocket"]["body_length_m"]        = float(_len_field.text)
	_params["rocket"]["nose_length_m"]        = float(_nose_len_field.text) / 100.0
	_params["rocket"]["nose_shape"]           = ["ogive", "vonkarman", "conical"][_nose_option.selected]
	_params["rocket"]["inertia_lateral_kgm2"] = float(_i_lat_field.text)
	_params["rocket"]["inertia_axial_kgm2"]   = float(_i_ax_field.text)

	_params["rocket"]["fins"] = {
		"n_fins":              int(_fin_n_field.text)     if _fin_n_field.text.is_valid_int()       else 0,
		"root_chord_m":       float(_fin_cr_field.text)    / 100.0 if _fin_cr_field.text.is_valid_float()    else 0.0,
		"tip_chord_m":        float(_fin_ct_field.text)    / 100.0 if _fin_ct_field.text.is_valid_float()    else 0.0,
		"semi_span_m":        float(_fin_s_field.text)     / 100.0 if _fin_s_field.text.is_valid_float()     else 0.0,
		"le_sweep_m":         float(_fin_sweep_field.text) / 100.0 if _fin_sweep_field.text.is_valid_float() else 0.0,
		"root_le_from_nose_m": float(_fin_xf_field.text)            if _fin_xf_field.text.is_valid_float()   else 0.0,
	}

	if not _params["rocket"].has("aero"):
		_params["rocket"]["aero"] = {}
	_params["rocket"]["aero"]["xcp_m"]    = float(_xcp_field.text)
	_params["rocket"]["aero"]["xcg_m"]    = float(_xcg_field.text)
	_params["rocket"]["aero"]["s_ref_m2"] = PI * (d_m * 0.5) * (d_m * 0.5)

	if MissionParamsIO.save_params(_params):
		_set_status("Saved ✓")
	else:
		_set_status("Save failed")

# ── CAD ────────────────────────────────────────────────────────────────────────

func _on_generate_cad() -> void:
	if _cad_thread != null and _cad_thread.is_started():
		return
	_cad_status_label.text = "Gerando…"
	_generate_btn.disabled = true
	_on_apply()
	var params := MissionParamsIO.load_params()
	_cad_thread = Thread.new()
	_cad_thread.start(_cad_worker.bind(params))

func _cad_worker(params: Dictionary) -> void:
	var result := CadExporter.generate(params)
	call_deferred("_on_cad_done", result)

func _on_cad_done(result: Dictionary) -> void:
	_cad_thread.wait_to_finish()
	_generate_btn.disabled = false
	if not result.ok:
		_cad_status_label.text = "Erro: " + result.get("error", "openscad falhou")
		return
	_cad_mesh = CadExporter.load_stl_binary(result.stl_print)
	_export_btn.disabled = false
	var sz_print := FileAccess.get_file_as_bytes(result.stl_print).size()
	var sz_cfd   := FileAccess.get_file_as_bytes(result.stl_cfd).size()
	_cad_status_label.text = "OK — print %.0f KB · CFD %.0f KB · calc. CD0…" % [
		sz_print / 1024.0, sz_cfd / 1024.0]
	if _cad_mesh:
		_show_cad_preview(_cad_mesh)
	var aero_params := MissionParamsIO.load_params()
	_aero_thread = Thread.new()
	_aero_thread.start(_aero_worker.bind(aero_params, sz_print, sz_cfd))

func _aero_worker(params: Dictionary, sz_print: int, sz_cfd: int) -> void:
	var aero := _compute_aero_sync(params)
	call_deferred("_on_aero_done", aero, sz_print, sz_cfd)

func _on_aero_done(aero: Dictionary, sz_print: int, sz_cfd: int) -> void:
	_aero_thread.wait_to_finish()
	var status := "OK — print %.0f KB · CFD %.0f KB" % [sz_print / 1024.0, sz_cfd / 1024.0]
	if not aero.is_empty():
		if not _params.has("rocket"):
			_params["rocket"] = {}
		if not _params["rocket"].has("aero"):
			_params["rocket"]["aero"] = {}
		for key in aero:
			_params["rocket"]["aero"][key] = aero[key]
		MissionParamsIO.save_params(_params)
		status += " · CD0=%.4f" % aero.get("cd0", 0.0)
	else:
		status += " · CD0 N/D"
	_cad_status_label.text = status

func _compute_aero_sync(params: Dictionary) -> Dictionary:
	var rkt  = params.get("rocket", {})
	var fins = rkt.get("fins", {})
	var proj_root    := ProjectSettings.globalize_path("res://")
	var vsl_root     := proj_root.path_join("../..").simplify_path()
	var julia_script := vsl_root.path_join("solver/src/aero_geometry.jl")
	if not FileAccess.file_exists(julia_script):
		return {}
	var args := PackedStringArray([
		julia_script,
		"--d="        + str(float(rkt.get("body_diameter_m", 0.08))),
		"--nose_len=" + str(float(rkt.get("nose_length_m",  0.24))),
		"--body_len=" + str(float(rkt.get("body_length_m",  1.20))),
		"--n_fins="   + str(int(fins.get("n_fins", 4))),
		"--cr="       + str(float(fins.get("root_chord_m",  0.15))),
		"--ct="       + str(float(fins.get("tip_chord_m",   0.05))),
		"--span="     + str(float(fins.get("semi_span_m",   0.10))),
	])
	var output: Array = []
	var code := OS.execute("julia", args, output, true)
	if code != 0:
		return {}
	return _parse_julia_aero_output(output)

func _parse_julia_aero_output(output: Array) -> Dictionary:
	var result := {}
	if output.is_empty():
		return result
	for line in output[0].split("\n"):
		var parts = line.strip_edges().split("=")
		if parts.size() == 2 and parts[0].length() > 0 and parts[1].is_valid_float():
			result[parts[0]] = parts[1].to_float()
	return result

const ORBIT_SENSITIVITY := 0.005

func _update_cam_orbit() -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var cam_dir: Vector3 = _orbit_quat * Vector3(0.0, 0.0, 1.0)
	var cam_up:  Vector3 = _orbit_quat * Vector3.UP
	_cam.position = _orbit_center + cam_dir * _orbit_r
	_cam.look_at(_orbit_center, cam_up)
	if _cad_gizmo != null and is_instance_valid(_cad_gizmo):
		_cad_gizmo.queue_redraw()

func _on_orbit_drag(delta: Vector2) -> void:
	var q_yaw:    Quaternion = Quaternion(Vector3.UP, -delta.x * ORBIT_SENSITIVITY)
	var cam_right: Vector3   = _orbit_quat * Vector3.RIGHT
	var q_pitch:  Quaternion = Quaternion(cam_right, -delta.y * ORBIT_SENSITIVITY)
	_orbit_quat = (q_yaw * q_pitch * _orbit_quat).normalized()
	_update_cam_orbit()

func _show_cad_preview(mesh: ArrayMesh) -> void:
	if _preview_window != null and is_instance_valid(_preview_window):
		_preview_window.queue_free()
		_cam       = null
		_cad_gizmo = null

	_preview_window = Window.new()
	_preview_window.title = "Rocket CAD Preview"
	_preview_window.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_SCREEN_WITH_MOUSE_FOCUS
	_preview_window.size = Vector2i(380, 480)
	_preview_window.close_requested.connect(func(): _preview_window.hide())

	var sub := SubViewport.new()
	sub.size = Vector2i(380, 480)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.own_world_3d = true

	# ── Background + ambient light ────────────────────────────────────────────
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.50, 0.65)
	env.ambient_light_energy = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	sub.add_child(world_env)

	# ── Camera auto-framed from mesh AABB ─────────────────────────────────────
	var aabb: AABB = mesh.get_aabb()
	var center: Vector3 = aabb.get_center()
	var longest: float = aabb.get_longest_axis_size()
	_cam          = Camera3D.new()
	_orbit_center = center
	_orbit_r      = longest * 1.4
	_orbit_r_min  = longest * 0.25
	_orbit_r_max  = longest * 6.0
	var init_dir: Vector3 = Vector3(longest * 0.3, 0.0, _orbit_r).normalized()
	_orbit_quat = Quaternion(Vector3(0.0, 0.0, 1.0), init_dir)
	_update_cam_orbit()
	sub.add_child(_cam)

	# ── Key light (warm, 45°) ─────────────────────────────────────────────────
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	key_light.light_energy = 1.4
	key_light.light_color = Color(1.0, 0.95, 0.88)
	sub.add_child(key_light)

	# ── Fill light (cool, back-left) ──────────────────────────────────────────
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	fill_light.light_energy = 0.45
	fill_light.light_color = Color(0.55, 0.65, 1.0)
	sub.add_child(fill_light)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	sub.add_child(mi)

	var svp_container := SubViewportContainer.new()
	svp_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svp_container.stretch = true
	svp_container.add_child(sub)
	_preview_window.add_child(svp_container)

	_cad_gizmo = load("res://scripts/cad_gizmo.gd").new()
	_cad_gizmo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cad_gizmo.mouse_filter = Control.MOUSE_FILTER_STOP
	_cad_gizmo.set_camera(_cam)
	_cad_gizmo.orbit_drag.connect(_on_orbit_drag)
	_cad_gizmo.zoom_step.connect(func(factor: float) -> void:
		_orbit_r = clampf(_orbit_r * factor, _orbit_r_min, _orbit_r_max)
		_update_cam_orbit()
	)
	_preview_window.add_child(_cad_gizmo)

	get_tree().root.add_child(_preview_window)
	_preview_window.popup_centered()

func _on_export_stl() -> void:
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.filters = PackedStringArray(["*.stl ; STL Files"])
	dlg.current_file = "rocket_print.stl"
	dlg.file_selected.connect(_do_export_stl.bind(dlg))
	dlg.canceled.connect(dlg.queue_free)
	get_tree().root.add_child(dlg)
	dlg.popup_centered(Vector2i(720, 520))

func _do_export_stl(dest: String, dlg: FileDialog) -> void:
	var src := ProjectSettings.globalize_path("res://cad/rocket_print.stl")
	var da := DirAccess.open("user://")
	if da == null:
		da = DirAccess.open("res://")
	var err := da.copy(src, dest) if da else ERR_CANT_OPEN
	_set_status("STL exportado ✓" if err == OK else "Export falhou (%d)" % err)
	dlg.queue_free()

# ── Helpers ────────────────────────────────────────────────────────────────────

func _section_label(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	parent.add_child(lbl)

func _new_grid(parent: VBoxContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	parent.add_child(grid)
	return grid

func _field_row(grid: GridContainer, label: String, unit: String) -> LineEdit:
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(lbl)
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(68.0, 0.0)
	edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(edit)
	var u := Label.new()
	u.text = " " + unit
	grid.add_child(u)
	return edit

func _display_row(grid: GridContainer, label: String, unit: String) -> Label:
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(lbl)
	var val := Label.new()
	val.text = "—"
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(val)
	var u := Label.new()
	u.text = " " + unit
	grid.add_child(u)
	return val

func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
