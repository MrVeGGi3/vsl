extends PanelContainer

const PANEL_W := 260.0
const PANEL_H := 420.0

var _params: Dictionary = {}
var _dragging := false
var _drag_offset := Vector2.ZERO

var _mass_field:   LineEdit
var _maxg_field:   LineEdit
var _diam_field:   LineEdit
var _len_field:    LineEdit
var _tmin_field:   LineEdit
var _tmax_field:   LineEdit

var _vol_label:    Label
var _load_label:   Label
var _g_label:      Label
var _margin_label: Label

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

	_build_requirements_section(inner)
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
	set_position(Vector2(20.0, y))

func _build_header(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 26)
	hbox.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(hbox)

	var title := Label.new()
	title.text = "PAYLOAD"
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

func _build_requirements_section(parent: VBoxContainer) -> void:
	_section_label(parent, "REQUIREMENTS")
	var grid := _new_grid(parent)
	_mass_field = _field_row(grid, "Mass",     "kg")
	_maxg_field = _field_row(grid, "Max-G",    "g")
	_diam_field = _field_row(grid, "Diameter", "cm")
	_len_field  = _field_row(grid, "Length",   "cm")
	_tmin_field = _field_row(grid, "Temp min", "°C")
	_tmax_field = _field_row(grid, "Temp max", "°C")
	parent.add_child(HSeparator.new())

func _build_analysis_section(parent: VBoxContainer) -> void:
	_section_label(parent, "STRUCTURAL ANALYSIS")
	var grid := _new_grid(parent)
	_vol_label    = _display_row(grid, "Volume",       "—", "L")
	_load_label   = _display_row(grid, "Load @ max-Q", "—", "N")
	_g_label      = _display_row(grid, "G @ max-Q",    "—", "g")
	_margin_label = _display_row(grid, "G margin",     "—", "g")
	parent.add_child(HSeparator.new())

func _load_and_populate() -> void:
	_params = MissionParamsIO.load_params()
	if _params.is_empty():
		_set_status("No params file")
		return
	var pl: Dictionary = _params.get("payload", {})
	_mass_field.text = str(float(pl.get("mass_kg",    2.0)))
	_maxg_field.text = str(float(pl.get("max_g",     30.0)))
	_diam_field.text = "%.1f" % (float(pl.get("diameter_m", 0.08)) * 100.0)
	_len_field.text  = "%.1f" % (float(pl.get("length_m",   0.20)) * 100.0)
	_tmin_field.text = str(float(pl.get("temp_min_c", -40.0)))
	_tmax_field.text = str(float(pl.get("temp_max_c",  85.0)))
	_set_status("")
	_refresh_analysis()

func _refresh_analysis() -> void:
	var d_m   := float(_diam_field.text) / 100.0 if _diam_field.text.is_valid_float() else 0.08
	var l_m   := float(_len_field.text)  / 100.0 if _len_field.text.is_valid_float()  else 0.20
	var m     := float(_mass_field.text)          if _mass_field.text.is_valid_float() else 2.0
	var max_g := float(_maxg_field.text)           if _maxg_field.text.is_valid_float() else 30.0
	const G0 := 9.80665

	_vol_label.text = "%.3f" % (PI * pow(d_m * 0.5, 2.0) * l_m * 1000.0)

	var bridge := get_node_or_null("/root/Main/SolverBridge")
	if bridge == null or not bridge.has_method("get_trajectory_summary"):
		_load_label.text   = "—"
		_g_label.text      = "—"
		_margin_label.text = "—"
		return
	var traj: Dictionary = bridge.get_trajectory_summary()
	if traj.is_empty():
		_load_label.text   = "—"
		_g_label.text      = "—"
		_margin_label.text = "—"
		return

	var s_ref  := PI * pow(d_m * 0.5, 2.0)
	var load_n := float(traj.get("max_q_pa", 0.0)) * s_ref
	var g_act  := load_n / (m * G0)

	_load_label.text   = "%.1f" % load_n
	_g_label.text      = "%.2f" % g_act
	_margin_label.text = "%.2f" % (max_g - g_act)

func _on_apply() -> void:
	if _params.is_empty():
		_params = MissionParamsIO.load_params()
	if not _params.has("payload"):
		_params["payload"] = {}
	_params["payload"]["mass_kg"]    = float(_mass_field.text)
	_params["payload"]["max_g"]      = float(_maxg_field.text)
	_params["payload"]["diameter_m"] = float(_diam_field.text) / 100.0
	_params["payload"]["length_m"]   = float(_len_field.text)  / 100.0
	_params["payload"]["temp_min_c"] = float(_tmin_field.text)
	_params["payload"]["temp_max_c"] = float(_tmax_field.text)
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
