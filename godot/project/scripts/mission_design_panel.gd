extends PanelContainer

const PANEL_W := 260.0

var _params: Dictionary = {}

var _apogee_field:      LineEdit
var _sim_dur_field:     LineEdit
var _payload_mass_field: LineEdit
var _payload_maxg_field: LineEdit
var _payload_diam_field: LineEdit
var _payload_len_field:  LineEdit
var _lat_field:          LineEdit
var _lon_field:          LineEdit
var _azimuth_field:      LineEdit
var _elevation_field:    LineEdit
var _atm_option:         OptionButton
var _f107a_field:        LineEdit
var _f107_field:         LineEdit
var _ap_field:           LineEdit
var _status_label:       Label

func _do_layout() -> void:
	var vp := get_viewport_rect().size
	set_position(Vector2(0.0, 0.0))
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

	_build_mission_section(inner)
	_build_payload_section(inner)
	_build_launch_section(inner)
	_build_atmosphere_section(inner)

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
	title.text = "MISSION DESIGN"
	title.add_theme_font_size_override("font_size", 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title)
	parent.add_child(HSeparator.new())

func _build_mission_section(parent: VBoxContainer) -> void:
	_section_label(parent, "MISSION")
	var grid := _new_grid(parent)
	_apogee_field  = _field_row(grid, "H* apogee", "km")
	_sim_dur_field = _field_row(grid, "Sim duration", "s")
	parent.add_child(HSeparator.new())

func _build_payload_section(parent: VBoxContainer) -> void:
	_section_label(parent, "PAYLOAD")
	var grid := _new_grid(parent)
	_payload_mass_field = _field_row(grid, "Mass", "kg")
	_payload_maxg_field = _field_row(grid, "Max-G", "g")
	_payload_diam_field = _field_row(grid, "Diameter", "cm")
	_payload_len_field  = _field_row(grid, "Length", "cm")
	parent.add_child(HSeparator.new())

func _build_launch_section(parent: VBoxContainer) -> void:
	_section_label(parent, "LAUNCH SITE")
	var grid := _new_grid(parent)
	_lat_field       = _field_row(grid, "Latitude", "°")
	_lon_field       = _field_row(grid, "Longitude", "°")
	_azimuth_field   = _field_row(grid, "Azimuth", "°")
	_elevation_field = _field_row(grid, "Elevation", "°")
	parent.add_child(HSeparator.new())

func _build_atmosphere_section(parent: VBoxContainer) -> void:
	_section_label(parent, "ATMOSPHERE")
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)
	var lbl := Label.new()
	lbl.text = "Model"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)
	_atm_option = OptionButton.new()
	_atm_option.add_item("nrlmsise00", 0)
	_atm_option.add_item("isa", 1)
	_atm_option.focus_mode = Control.FOCUS_NONE
	hbox.add_child(_atm_option)
	var grid := _new_grid(parent)
	_f107a_field = _field_row(grid, "F10.7a", "sfu")
	_f107_field  = _field_row(grid, "F10.7",  "sfu")
	_ap_field    = _field_row(grid, "Ap",     "nT")
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
	var orb: Dictionary = _params.get("orbital", {})
	_apogee_field.text  = str(float(orb.get("target_alt_km",       600.0)))
	_sim_dur_field.text = str(float(orb.get("analysis_duration_s", 86400.0)))

	var pl: Dictionary = _params.get("payload", {})
	_payload_mass_field.text = str(float(pl.get("mass_kg", 2.0)))
	_payload_maxg_field.text = str(float(pl.get("max_g", 30.0)))
	_payload_diam_field.text = "%.1f" % (float(pl.get("diameter_m", 0.08)) * 100.0)
	_payload_len_field.text  = "%.1f" % (float(pl.get("length_m",   0.20)) * 100.0)

	var ls: Dictionary = _params.get("launch_site", {})
	_lat_field.text       = str(float(ls.get("lat_deg",       -2.37)))
	_lon_field.text       = str(float(ls.get("lon_deg",      -44.40)))
	_azimuth_field.text   = str(float(ls.get("azimuth_deg",   90.0)))
	_elevation_field.text = str(float(ls.get("elevation_deg", 90.0)))

	var atm: Dictionary = _params.get("atmosphere", {})
	_atm_option.selected = 1 if atm.get("model", "nrlmsise00") == "isa" else 0
	_f107a_field.text = str(float(atm.get("f107a_sfu", 150.0)))
	_f107_field.text  = str(float(atm.get("f107_sfu",  150.0)))
	_ap_field.text    = str(float(atm.get("ap_nt",       4.0)))

func _on_apply() -> void:
	if _params.is_empty():
		_params = MissionParamsIO.load_params()

	if not _params.has("orbital"):
		_params["orbital"] = {}
	_params["orbital"]["target_alt_km"]       = float(_apogee_field.text)
	_params["orbital"]["analysis_duration_s"] = float(_sim_dur_field.text)

	if not _params.has("payload"):
		_params["payload"] = {}
	_params["payload"]["mass_kg"]    = float(_payload_mass_field.text)
	_params["payload"]["max_g"]      = float(_payload_maxg_field.text)
	_params["payload"]["diameter_m"] = float(_payload_diam_field.text) / 100.0
	_params["payload"]["length_m"]   = float(_payload_len_field.text)  / 100.0

	if not _params.has("launch_site"):
		_params["launch_site"] = {}
	_params["launch_site"]["lat_deg"]       = float(_lat_field.text)
	_params["launch_site"]["lon_deg"]       = float(_lon_field.text)
	_params["launch_site"]["azimuth_deg"]   = float(_azimuth_field.text)
	_params["launch_site"]["elevation_deg"] = float(_elevation_field.text)

	if not _params.has("atmosphere"):
		_params["atmosphere"] = {}
	_params["atmosphere"]["model"]     = "isa" if _atm_option.selected == 1 else "nrlmsise00"
	_params["atmosphere"]["f107a_sfu"] = float(_f107a_field.text)
	_params["atmosphere"]["f107_sfu"]  = float(_f107_field.text)
	_params["atmosphere"]["ap_nt"]     = float(_ap_field.text)

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

func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
