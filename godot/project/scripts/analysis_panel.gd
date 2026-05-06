extends PanelContainer

var _period_val:       Label
var _alt_val:          Label
var _incl_val:         Label
var _eclipse_frac_val: Label
var _eclipse_n_val:    Label
var _next_pass_val:    Label
var _avg_dur_val:      Label
var _n_passes_val:     Label
var _r1_edit:          LineEdit
var _r2_edit:          LineEdit
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
	refresh_btn.pressed.connect(_refresh_data)
	hbox.add_child(refresh_btn)
	parent.add_child(HSeparator.new())

func _build_orbit_section(parent: VBoxContainer) -> void:
	_section_label(parent, "ORBIT")
	var grid := _new_grid(parent)
	_period_val = _grid_row(grid, "Period",   "—", "min")
	_alt_val    = _grid_row(grid, "Altitude", "—", "km")
	_incl_val   = _grid_row(grid, "Incl.",    "—", "°")
	parent.add_child(HSeparator.new())

func _build_eclipse_section(parent: VBoxContainer) -> void:
	_section_label(parent, "ECLIPSE")
	var grid := _new_grid(parent)
	_eclipse_frac_val = _grid_row(grid, "Fraction", "—", "%")
	_eclipse_n_val    = _grid_row(grid, "Periods",  "—", "")
	parent.add_child(HSeparator.new())

func _build_access_section(parent: VBoxContainer) -> void:
	_section_label(parent, "GS ACCESS  (Brasília)")
	var grid := _new_grid(parent)
	_next_pass_val = _grid_row(grid, "Next pass",  "—", "s")
	_avg_dur_val   = _grid_row(grid, "Avg dur.",   "—", "min")
	_n_passes_val  = _grid_row(grid, "N passes",   "—", "")
	parent.add_child(HSeparator.new())

func _build_maneuver_section(parent: VBoxContainer) -> void:
	_section_label(parent, "HOHMANN TRANSFER")

	var r1_box := HBoxContainer.new()
	parent.add_child(r1_box)
	_make_label(r1_box, "r₁ ")
	_r1_edit = LineEdit.new()
	_r1_edit.text = "6778"
	_r1_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1_box.add_child(_r1_edit)
	_make_label(r1_box, " km")

	var r2_box := HBoxContainer.new()
	parent.add_child(r2_box)
	_make_label(r2_box, "r₂ ")
	_r2_edit = LineEdit.new()
	_r2_edit.text = "42164"
	_r2_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2_box.add_child(_r2_edit)
	_make_label(r2_box, " km")

	var btn := Button.new()
	btn.text = "Compute ΔV"
	btn.pressed.connect(_compute_hohmann)
	parent.add_child(btn)

	var grid := _new_grid(parent)
	_dv1_val = _grid_row(grid, "ΔV₁", "—", "km/s")
	_dv2_val = _grid_row(grid, "ΔV₂", "—", "km/s")
	_tof_val = _grid_row(grid, "ToF",  "—", "h")
	parent.add_child(HSeparator.new())

func _build_report_section(parent: VBoxContainer) -> void:
	var btn := Button.new()
	btn.text = "Export JSON Report"
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
	var r1 := _r1_edit.text.to_float()
	var r2 := _r2_edit.text.to_float()
	if r1 <= 0.0 or r2 <= 0.0:
		_set_status("Invalid radii")
		return
	var res: Dictionary = bridge.compute_hohmann(r1, r2)
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

func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
