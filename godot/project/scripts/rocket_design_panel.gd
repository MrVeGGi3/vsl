extends PanelContainer

const PANEL_W        := 265.0
const PANEL_OFFSET_X := 262.0
const G0             := 9.80665

var _params: Dictionary = {}

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

var _xcp_field:       LineEdit
var _xcg_field:       LineEdit
var _stability_label: Label

var _i_lat_field:     LineEdit
var _i_ax_field:      LineEdit

var _status_label:    Label

func _do_layout() -> void:
	var vp := get_viewport_rect().size
	set_position(Vector2(PANEL_OFFSET_X, 0.0))
	set_size(Vector2(PANEL_W, vp.y - 46.0))

func _ready() -> void:
	_do_layout()
	get_viewport().size_changed.connect(_do_layout)

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
	_build_aero_section(inner)
	_build_inertia_section(inner)

	var apply_btn := Button.new()
	apply_btn.text = "Apply & Save"
	apply_btn.focus_mode = Control.FOCUS_NONE
	apply_btn.pressed.connect(_on_apply)
	inner.add_child(apply_btn)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 10)
	inner.add_child(_status_label)

	_load_and_populate()

func _build_header(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)
	var title := Label.new()
	title.text = "ROCKET DESIGN"
	title.add_theme_font_size_override("font_size", 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title)
	parent.add_child(HSeparator.new())

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

	var aero: Dictionary = rkt.get("aero", {})
	_xcp_field.text = str(float(aero.get("xcp_m", 0.85)))
	_xcg_field.text = str(float(aero.get("xcg_m", 0.55)))
	_update_derived_aero()

	_i_lat_field.text = str(float(rkt.get("inertia_lateral_kgm2", 0.96)))
	_i_ax_field.text  = str(float(rkt.get("inertia_axial_kgm2",  0.006)))

func _update_derived_propulsion() -> void:
	var f_max := float(_fmax_field.text) if _fmax_field.text.is_valid_float() else 0.0
	var t_b   := float(_tb_field.text)   if _tb_field.text.is_valid_float()   else 0.0
	_impulse_label.text = "%.0f" % (f_max * t_b)

func _update_derived_aero() -> void:
	var xcp := float(_xcp_field.text)  if _xcp_field.text.is_valid_float()  else 0.0
	var xcg := float(_xcg_field.text)  if _xcg_field.text.is_valid_float()  else 0.0
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

	if not _params["rocket"].has("aero"):
		_params["rocket"]["aero"] = {}
	_params["rocket"]["aero"]["xcp_m"]    = float(_xcp_field.text)
	_params["rocket"]["aero"]["xcg_m"]    = float(_xcg_field.text)
	_params["rocket"]["aero"]["s_ref_m2"] = PI * (d_m * 0.5) * (d_m * 0.5)

	if MissionParamsIO.save_params(_params):
		_set_status("Saved ✓")
	else:
		_set_status("Save failed")

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
