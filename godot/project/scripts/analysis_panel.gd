extends PanelContainer

var _apogee_val:      Label
var _apogee_t_val:    Label
var _max_v_val:       Label
var _flight_t_val:    Label
var _range_val:       Label

var _max_q_val:       Label
var _max_q_alt_val:   Label
var _max_q_mach_val:  Label
var _max_q_t_val:     Label

var _burnout_t_val:   Label
var _burnout_alt_val: Label
var _burnout_v_val:   Label
var _prop_mass_val:   Label
var _impulse_val:     Label

var _aoa_val:         Label
var _omega_val:       Label

var _status_label:    Label

func _do_layout() -> void:
	var vp := get_viewport_rect().size
	set_position(Vector2(vp.x - 270.0, 0.0))
	set_size(Vector2(270.0, vp.y - 46.0))

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

	_build_performance_section(inner)
	_build_loads_section(inner)
	_build_propulsion_section(inner)
	_build_stability_section(inner)
	_build_report_section(inner)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 10)
	inner.add_child(_status_label)

	_refresh_data()

func _build_header(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)
	var title := Label.new()
	title.text = "FLIGHT ANALYSIS"
	title.add_theme_font_size_override("font_size", 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title)
	var refresh_btn := Button.new()
	refresh_btn.text = "↺"
	refresh_btn.focus_mode = Control.FOCUS_NONE
	refresh_btn.pressed.connect(_refresh_data)
	hbox.add_child(refresh_btn)
	parent.add_child(HSeparator.new())

func _build_performance_section(parent: VBoxContainer) -> void:
	_section_label(parent, "FLIGHT PERFORMANCE")
	var grid := _new_grid(parent)
	_apogee_val   = _grid_row(grid, "Apogee",           "—", "m")
	_apogee_t_val = _grid_row(grid, "Time to apogee",   "—", "s")
	_max_v_val    = _grid_row(grid, "Max velocity",      "—", "m/s")
	_flight_t_val = _grid_row(grid, "Total flight time", "—", "s")
	_range_val    = _grid_row(grid, "Horiz. range",      "—", "m")
	parent.add_child(HSeparator.new())

func _build_loads_section(parent: VBoxContainer) -> void:
	_section_label(parent, "STRUCTURAL LOADS")
	var grid := _new_grid(parent)
	_max_q_val      = _grid_row(grid, "Max-Q",          "—", "Pa")
	_max_q_alt_val  = _grid_row(grid, "Alt. at Max-Q",  "—", "m")
	_max_q_mach_val = _grid_row(grid, "Mach at Max-Q",  "—", "")
	_max_q_t_val    = _grid_row(grid, "Time of Max-Q",  "—", "s")
	parent.add_child(HSeparator.new())

func _build_propulsion_section(parent: VBoxContainer) -> void:
	_section_label(parent, "PROPULSION")
	var grid := _new_grid(parent)
	_burnout_t_val   = _grid_row(grid, "Burnout time",     "—", "s")
	_burnout_alt_val = _grid_row(grid, "Burnout altitude", "—", "m")
	_burnout_v_val   = _grid_row(grid, "Burnout velocity", "—", "m/s")
	_prop_mass_val   = _grid_row(grid, "Propellant mass",  "—", "kg")
	_impulse_val     = _grid_row(grid, "Total impulse",    "—", "N·s")
	parent.add_child(HSeparator.new())

func _build_stability_section(parent: VBoxContainer) -> void:
	_section_label(parent, "STABILITY")
	var grid := _new_grid(parent)
	_aoa_val   = _grid_row(grid, "Max angle of attack", "—", "°")
	_omega_val = _grid_row(grid, "Max angular rate",    "—", "rad/s")
	parent.add_child(HSeparator.new())

func _build_report_section(parent: VBoxContainer) -> void:
	var btn := Button.new()
	btn.text = "Export JSON Report"
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_export_report)
	parent.add_child(btn)

# ── Refresh ────────────────────────────────────────────────────────────────────

func _refresh_data() -> void:
	var bridge := get_node_or_null("/root/Main/SolverBridge")
	if bridge == null:
		_set_status("Bridge offline")
		return
	if not bridge.has_method("get_trajectory_summary"):
		_set_status("get_trajectory_summary not available")
		return
	_set_status("")

	var d: Dictionary = bridge.get_trajectory_summary()
	if d.is_empty():
		_set_status("No trajectory data")
		return

	_apogee_val.text   = "%.0f"   % float(d.get("apogee_m",          0.0))
	_apogee_t_val.text = "%.1f"   % float(d.get("apogee_time_s",     0.0))
	var v_mps: float   = float(d.get("max_velocity_mps",  0.0))
	var v_mach: float  = float(d.get("max_velocity_mach", 0.0))
	_max_v_val.text    = "%.0f (M%.2f)" % [v_mps, v_mach]
	_flight_t_val.text = "%.1f"   % float(d.get("landing_time_s",    0.0))
	_range_val.text    = "%.0f"   % float(d.get("range_m",           0.0))

	_max_q_val.text      = "%.0f"  % float(d.get("max_q_pa",         0.0))
	_max_q_alt_val.text  = "%.0f"  % float(d.get("max_q_altitude_m", 0.0))
	_max_q_mach_val.text = "%.3f"  % float(d.get("max_q_mach",       0.0))
	_max_q_t_val.text    = "%.2f"  % float(d.get("max_q_time_s",     0.0))

	_burnout_t_val.text   = "%.2f" % float(d.get("burnout_time_s",       0.0))
	_burnout_alt_val.text = "%.0f" % float(d.get("burnout_altitude_m",   0.0))
	_burnout_v_val.text   = "%.0f" % float(d.get("burnout_velocity_mps", 0.0))
	_prop_mass_val.text   = "%.2f" % float(d.get("propellant_mass_kg",   0.0))
	_impulse_val.text     = "%.0f" % float(d.get("total_impulse_ns",     0.0))

	_aoa_val.text   = "%.1f" % float(d.get("max_aoa_deg",            0.0))
	_omega_val.text = "%.3f" % float(d.get("max_angular_rate_rad_s", 0.0))

func _export_report() -> void:
	var bridge := get_node_or_null("/root/Main/SolverBridge")
	if bridge == null or not bridge.has_method("export_report_json"):
		_set_status("export_report_json not available")
		return
	var path := "user://mission_report.json"
	bridge.export_report_json(path)
	_set_status("Saved → " + path)

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

func _grid_row(grid: GridContainer, name_: String, val_: String, unit_: String) -> Label:
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
