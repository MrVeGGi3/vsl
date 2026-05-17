extends PanelContainer

const PANEL_W := 275.0
const PANEL_H := 500.0

var _dragging := false
var _drag_offset := Vector2.ZERO

var _propellant_label:  Label
var _structure_label:   Label
var _payload_label:     Label
var _obdh_label:        Label
var _battery_label:     Label
var _wet_label:         Label
var _prop_frac_label:   Label

var _target_label:      Label
var _actual_label:      Label
var _apogee_mg_label:   Label

var _power_total_label: Label
var _capacity_label:    Label
var _endurance_label:   Label

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

	_build_mass_section(inner)
	_build_flight_section(inner)
	_build_power_section(inner)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 10)
	inner.add_child(_status_label)

	_refresh_data()

func _fit_to_viewport() -> void:
	var vp := get_viewport_rect().size
	var h = min(PANEL_H, vp.y - 44.0)
	set_size(Vector2(PANEL_W, h))
	var x = clamp(vp.x - PANEL_W - 20.0, 0.0, vp.x - PANEL_W)
	var y = clamp(position.y, 40.0, max(40.0, vp.y - h))
	set_position(Vector2(x, y))

func _build_header(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 26)
	hbox.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(hbox)

	var title := Label.new()
	title.text = "BUDGET"
	title.add_theme_font_size_override("font_size", 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_child(title)

	var refresh_btn := Button.new()
	refresh_btn.text = "↺"
	refresh_btn.flat = true
	refresh_btn.focus_mode = Control.FOCUS_NONE
	refresh_btn.pressed.connect(_refresh_data)
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

func _build_mass_section(parent: VBoxContainer) -> void:
	_section_label(parent, "MASS BUDGET")
	var grid := _new_grid(parent)
	_propellant_label = _display_row(grid, "Propellant",      "—", "kg")
	_structure_label  = _display_row(grid, "Structure",       "—", "kg")
	_payload_label    = _display_row(grid, "Payload",         "—", "kg")
	_obdh_label       = _display_row(grid, "OBDH",            "—", "kg")
	_battery_label    = _display_row(grid, "Battery",         "—", "kg")
	_wet_label        = _display_row(grid, "Total wet",       "—", "kg")
	_prop_frac_label  = _display_row(grid, "Propellant frac", "—", "%")
	parent.add_child(HSeparator.new())

func _build_flight_section(parent: VBoxContainer) -> void:
	_section_label(parent, "FLIGHT PERFORMANCE")
	var grid := _new_grid(parent)
	_target_label    = _display_row(grid, "Target H*",     "—", "km")
	_actual_label    = _display_row(grid, "Actual apogee", "—", "m")
	_apogee_mg_label = _display_row(grid, "Apogee margin", "—", "m")
	parent.add_child(HSeparator.new())

func _build_power_section(parent: VBoxContainer) -> void:
	_section_label(parent, "POWER SUMMARY")
	var grid := _new_grid(parent)
	_power_total_label = _display_row(grid, "Total consumption", "—", "W")
	_capacity_label    = _display_row(grid, "Battery capacity",  "—", "Wh")
	_endurance_label   = _display_row(grid, "Endurance",         "—", "h")
	parent.add_child(HSeparator.new())

func _refresh_data() -> void:
	var params := MissionParamsIO.load_params()
	if params.is_empty():
		_set_status("No params")
		return

	# mass budget
	var pr:  Dictionary = params.get("propulsion", {})
	var pl:  Dictionary = params.get("payload",    {})
	var ob:  Dictionary = params.get("obdh",       {})
	var pw:  Dictionary = params.get("power",      {})
	var orb: Dictionary = params.get("orbital",    {})

	var m_wet    := float(pr.get("mass_wet_kg", 8.0))
	var m_dry    := float(pr.get("mass_dry_kg", 6.2))
	var m_prop   := m_wet - m_dry
	var m_pl     := float(pl.get("mass_kg",          2.0))
	var m_obdh   := float(ob.get("mass_kg",          0.5))
	var m_bat    := float(pw.get("battery_mass_kg",  0.3))
	var m_struct := m_dry - (m_pl + m_obdh + m_bat)

	_propellant_label.text = "%.2f" % m_prop
	_structure_label.text  = "%.2f" % m_struct
	_payload_label.text    = "%.2f" % m_pl
	_obdh_label.text       = "%.2f" % m_obdh
	_battery_label.text    = "%.2f" % m_bat
	_wet_label.text        = "%.2f" % m_wet
	_prop_frac_label.text  = "%.1f" % (m_prop / m_wet * 100.0) if m_wet > 0.0 else "—"

	# flight performance
	var target_km := float(orb.get("target_alt_km", 600.0))
	_target_label.text = "%.1f" % target_km

	var bridge := get_node_or_null("/root/Main/SolverBridge")
	if bridge != null and bridge.has_method("get_trajectory_summary"):
		var traj: Dictionary = bridge.get_trajectory_summary()
		if not traj.is_empty():
			var actual := float(traj.get("apogee_m", 0.0))
			_actual_label.text    = "%.0f" % actual
			_apogee_mg_label.text = "%.0f" % (actual - target_km * 1000.0)
		else:
			_actual_label.text    = "—"
			_apogee_mg_label.text = "—"
	else:
		_actual_label.text    = "—"
		_apogee_mg_label.text = "—"

	# power summary
	var c:  Dictionary = pw.get("consumers", {})
	var total_w := (float(c.get("payload_w",   5.0)) + float(c.get("obdh_w",      3.0))
				  + float(c.get("ttc_w",       2.0)) + float(c.get("actuators_w", 0.5)))
	var cap_wh  := float(pw.get("battery_capacity_wh", 20.0))

	_power_total_label.text = "%.2f" % total_w
	_capacity_label.text    = "%.1f" % cap_wh
	_endurance_label.text   = "%.2f" % (cap_wh / total_w) if total_w > 0.0 else "—"

	_set_status("")

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
