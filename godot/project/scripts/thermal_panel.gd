extends PanelContainer

const PANEL_W := 265.0
const PANEL_H := 420.0

var _params: Dictionary = {}
var _dragging := false
var _drag_offset := Vector2.ZERO

var _material_field:  LineEdit
var _thick_field:     LineEdit
var _emiss_field:     LineEdit
var _tmax_field:      LineEdit
var _tmin_field:      LineEdit

var _mach_label:      Label
var _alt_label:       Label
var _tatm_label:      Label
var _tstag_label:     Label
var _margin_label:    Label

var _status_label: Label

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

	_build_structure_section(inner)
	_build_analysis_section(inner)

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
	var y = clamp(position.y, 40.0, max(40.0, vp.y - h))
	set_position(Vector2(560.0, y))

func _build_header(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 26)
	hbox.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(hbox)

	var title := Label.new()
	title.text = "THERMAL"
	title.add_theme_font_size_override("font_size", 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_child(title)

	var refresh_btn := Button.new()
	refresh_btn.text = "↺"
	refresh_btn.flat = true
	refresh_btn.focus_mode = Control.FOCUS_NONE
	refresh_btn.pressed.connect(_refresh_analysis)
	hbox.add_child(refresh_btn)

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

func _build_structure_section(parent: VBoxContainer) -> void:
	_section_label(parent, "STRUCTURE")
	var grid := _new_grid(parent)
	_material_field = _field_row(grid, "Material",     "—")
	_thick_field    = _field_row(grid, "Wall thick.",  "mm")
	_emiss_field    = _field_row(grid, "Emissivity",   "—")
	_tmax_field     = _field_row(grid, "T max struct", "°C")
	_tmin_field     = _field_row(grid, "T min struct", "°C")
	parent.add_child(HSeparator.new())

func _build_analysis_section(parent: VBoxContainer) -> void:
	_section_label(parent, "AEROHEATING (ISA + ISENTROPIC)")
	var grid := _new_grid(parent)
	_mach_label   = _display_row(grid, "Mach @ max-Q",    "—", "—")
	_alt_label    = _display_row(grid, "Alt. @ max-Q",    "—", "m")
	_tatm_label   = _display_row(grid, "T_atm (ISA)",     "—", "K")
	_tstag_label  = _display_row(grid, "T_stagnation",    "—", "K")
	_margin_label = _display_row(grid, "Structural margin","—", "°C")
	parent.add_child(HSeparator.new())

func _load_and_populate() -> void:
	_params = MissionParamsIO.load_params()
	if _params.is_empty():
		_set_status("No params file")
		return
	var th: Dictionary = _params.get("thermal", {})
	_material_field.text = str(th.get("material",              "aluminum_6061"))
	_thick_field.text    = str(float(th.get("wall_thickness_mm",       2.0)))
	_emiss_field.text    = str(float(th.get("emissivity",              0.15)))
	_tmax_field.text     = str(float(th.get("temp_max_structural_c", 130.0)))
	_tmin_field.text     = str(float(th.get("temp_min_structural_c", -40.0)))
	_set_status("")
	_refresh_analysis()

func _refresh_analysis() -> void:
	var bridge := get_node_or_null("/root/Main/SolverBridge")
	if bridge == null or not bridge.has_method("get_trajectory_summary"):
		_mach_label.text   = "—"
		_alt_label.text    = "—"
		_tatm_label.text   = "—"
		_tstag_label.text  = "—"
		_margin_label.text = "—"
		return
	var traj: Dictionary = bridge.get_trajectory_summary()
	if traj.is_empty():
		_mach_label.text   = "—"
		_alt_label.text    = "—"
		_tatm_label.text   = "—"
		_tstag_label.text  = "—"
		_margin_label.text = "—"
		return

	var mach := float(traj.get("max_q_mach",       0.0))
	var alt  := float(traj.get("max_q_altitude_m", 0.0))

	var t_atm := _isa_temperature(alt)
	var t_stag := t_atm * (1.0 + 0.2 * mach * mach)

	var t_max_c := float(_tmax_field.text) if _tmax_field.text.is_valid_float() else 130.0
	var t_stag_c := t_stag - 273.15
	var margin := t_max_c - t_stag_c

	_mach_label.text   = "%.3f" % mach
	_alt_label.text    = "%.0f" % alt
	_tatm_label.text   = "%.1f" % t_atm
	_tstag_label.text  = "%.1f (%.1f °C)" % [t_stag, t_stag_c]
	_margin_label.text = "%.1f" % margin

func _isa_temperature(alt_m: float) -> float:
	# Standard ISA troposphere and lower stratosphere
	if alt_m < 11000.0:
		return 288.15 - 0.0065 * alt_m
	return 216.65  # isothermal layer up to 20 km

func _on_apply() -> void:
	if _params.is_empty():
		_params = MissionParamsIO.load_params()
	if not _params.has("thermal"):
		_params["thermal"] = {}
	_params["thermal"]["material"]              = _material_field.text
	_params["thermal"]["wall_thickness_mm"]     = float(_thick_field.text)
	_params["thermal"]["emissivity"]            = float(_emiss_field.text)
	_params["thermal"]["temp_max_structural_c"] = float(_tmax_field.text)
	_params["thermal"]["temp_min_structural_c"] = float(_tmin_field.text)
	if MissionParamsIO.save_params(_params):
		_set_status("Saved ✓")
		_refresh_analysis()
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

func _display_row(grid: GridContainer, name_: String, val_: String, unit_: String) -> Label:
	var n := Label.new()
	n.text = name_
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(n)
	var v := Label.new()
	v.text = val_
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(v)
	var u := Label.new()
	u.text = " " + unit_
	grid.add_child(u)
	return v

func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
