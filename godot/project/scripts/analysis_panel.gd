extends PanelContainer

var _period_val:       Label
var _alt_val:          Label
var _incl_val:         Label
var _eclipse_frac_val: Label
var _eclipse_n_val:    Label
var _next_pass_val:    Label
var _avg_dur_val:      Label
var _n_passes_val:     Label
var _r1_val:           float = 6778.0
var _r2_val:           float = 42164.0
var _r1_label:         Label
var _r2_label:         Label
var _dv1_val:          Label
var _dv2_val:          Label
var _tof_val:          Label
var _status_label:     Label

func _ready() -> void:
	set_anchor_and_offset(SIDE_LEFT,   1.0, -290.0)
	set_anchor_and_offset(SIDE_RIGHT,  1.0,    0.0)
	set_anchor_and_offset(SIDE_TOP,    0.0,    0.0)
	set_anchor_and_offset(SIDE_BOTTOM, 1.0,    0.0)

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

	_build_orbit_section(inner)
	_build_eclipse_section(inner)
	_build_access_section(inner)
	_build_maneuver_section(inner)
	_build_report_section(inner)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 10)
	inner.add_child(_status_label)

	_refresh_data()

func _build_header(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)
	var title := Label.new()
	title.text = "MISSION ANALYSIS"
	title.add_theme_font_size_override("font_size", 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title)
	var refresh_btn := Button.new()
	refresh_btn.text = "↺"
	refresh_btn.focus_mode = Control.FOCUS_NONE
	refresh_btn.pressed.connect(_refresh_data)
	hbox.add_child(refresh_btn)
	parent.add_child(HSeparator.new())

func _build_orbit_section(parent: VBoxContainer) -> void:
	_section_label(parent, "ORBIT")
	var grid := _new_grid(parent)
	_period_val = _grid_row(grid, "Time per orbit", "—", "min")
	_alt_val    = _grid_row(grid, "Altitude",       "—", "km")
	_incl_val   = _grid_row(grid, "Inclination",    "—", "°")
	parent.add_child(HSeparator.new())

func _build_eclipse_section(parent: VBoxContainer) -> void:
	_section_label(parent, "ECLIPSE  (24 h)")
	var grid := _new_grid(parent)
	_eclipse_frac_val = _grid_row(grid, "Time in shadow", "—", "%")
	_eclipse_n_val    = _grid_row(grid, "Shadow periods", "—", "")
	parent.add_child(HSeparator.new())

func _build_access_section(parent: VBoxContainer) -> void:
	_section_label(parent, "GROUND STATION  (Brasília, 5° mask)")
	var grid := _new_grid(parent)
	_next_pass_val = _grid_row(grid, "Next pass in",    "—", "s")
	_avg_dur_val   = _grid_row(grid, "Contact duration", "—", "min")
	_n_passes_val  = _grid_row(grid, "Passes today",    "—", "")
	parent.add_child(HSeparator.new())

func _build_maneuver_section(parent: VBoxContainer) -> void:
	_section_label(parent, "ORBITAL TRANSFER  (Hohmann)")
	_r1_label = _spin_row(parent, "From orbit", _r1_val, 100.0,
		func(v): _r1_val = v; _compute_hohmann())
	_r2_label = _spin_row(parent, "To orbit  ", _r2_val, 500.0,
		func(v): _r2_val = v; _compute_hohmann())

	var btn := Button.new()
	btn.text = "Compute ΔV"
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_compute_hohmann)
	parent.add_child(btn)

	var grid := _new_grid(parent)
	_dv1_val = _grid_row(grid, "ΔV departure", "—", "km/s")
	_dv2_val = _grid_row(grid, "ΔV arrival",   "—", "km/s")
	_tof_val = _grid_row(grid, "Transit time",  "—", "h")
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
	_set_status("")

	if bridge.has_method("get_mission_summary"):
		var d: Dictionary = bridge.get_mission_summary()
		if d.has("period_s"):
			_period_val.text = "%.1f" % (float(d["period_s"]) / 60.0)
		if d.has("altitude_km"):
			_alt_val.text = "%.0f" % float(d["altitude_km"])
		if d.has("inclination_deg"):
			_incl_val.text = "%.1f" % float(d["inclination_deg"])

	if bridge.has_method("get_eclipse_result"):
		var ecl: Dictionary = bridge.get_eclipse_result()
		if ecl.has("fraction"):
			_eclipse_frac_val.text = "%.1f" % (float(ecl["fraction"]) * 100.0)
		if ecl.has("n_periods"):
			_eclipse_n_val.text = str(int(ecl["n_periods"]))

	if bridge.has_method("get_access_windows"):
		var wins: Array = bridge.get_access_windows()
		_n_passes_val.text = str(wins.size())
		if wins.size() > 0:
			var total_dur := 0.0
			for w in wins:
				total_dur += float(w["t_end_s"]) - float(w["t_start_s"])
			_avg_dur_val.text = "%.1f" % (total_dur / wins.size() / 60.0)
			if bridge.has_method("get_sim_time_s"):
				var t_now: float = bridge.get_sim_time_s()
				var next_dt := INF
				for w in wins:
					var ts := float(w["t_start_s"])
					if ts > t_now:
						next_dt = minf(next_dt, ts - t_now)
				_next_pass_val.text = "%.0f" % next_dt if next_dt < INF else "N/A"

func _compute_hohmann() -> void:
	var bridge := get_node_or_null("/root/Main/SolverBridge")
	if bridge == null or not bridge.has_method("compute_hohmann"):
		_set_status("compute_hohmann not available")
		return
	if _r1_val <= 0.0 or _r2_val <= 0.0:
		_set_status("Invalid radii")
		return
	var res: Dictionary = bridge.compute_hohmann(_r1_val, _r2_val)
	if res.is_empty():
		_set_status("Hohmann failed")
		return
	if res.has("dv1_kms"): _dv1_val.text = "%.4f" % float(res["dv1_kms"])
	if res.has("dv2_kms"): _dv2_val.text = "%.4f" % float(res["dv2_kms"])
	if res.has("tof_s"):   _tof_val.text  = "%.2f" % (float(res["tof_s"]) / 3600.0)
	_set_status("")

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

func _make_label(parent: HBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	parent.add_child(lbl)

func _spin_row(parent: VBoxContainer, label_text: String, initial: float,
               step: float, on_change: Callable) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_make_label(row, label_text + " ")
	var btn_minus := Button.new()
	btn_minus.text = "−"
	btn_minus.focus_mode = Control.FOCUS_NONE
	btn_minus.custom_minimum_size = Vector2(28, 0)
	row.add_child(btn_minus)
	var val_lbl := Label.new()
	val_lbl.text = "%.0f km" % initial
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(val_lbl)
	var btn_plus := Button.new()
	btn_plus.text = "+"
	btn_plus.focus_mode = Control.FOCUS_NONE
	btn_plus.custom_minimum_size = Vector2(28, 0)
	row.add_child(btn_plus)
	var state := [initial]  # Array as mutable reference — float is captured by value in GDScript 4
	btn_minus.pressed.connect(func():
		state[0] = maxf(state[0] - step, 6371.0 + 100.0)
		val_lbl.text = "%.0f km" % state[0]
		on_change.call(state[0]))
	btn_plus.pressed.connect(func():
		state[0] += step
		val_lbl.text = "%.0f km" % state[0]
		on_change.call(state[0]))
	return val_lbl

func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
