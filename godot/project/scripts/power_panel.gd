extends PanelContainer

const PANEL_W := 260.0
const PANEL_H := 420.0

var _params: Dictionary = {}
var _dragging := false
var _drag_offset := Vector2.ZERO

var _capacity_field:  LineEdit
var _bat_mass_field:  LineEdit
var _payload_w_field: LineEdit
var _obdh_w_field:    LineEdit
var _ttc_w_field:     LineEdit
var _act_w_field:     LineEdit

var _total_label:     Label
var _endurance_label: Label
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

	_build_battery_section(inner)
	_build_consumers_section(inner)
	_build_budget_section(inner)

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
	set_position(Vector2(290.0, y))

func _build_header(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 26)
	hbox.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(hbox)

	var title := Label.new()
	title.text = "POWER"
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

func _build_battery_section(parent: VBoxContainer) -> void:
	_section_label(parent, "BATTERY")
	var grid := _new_grid(parent)
	_capacity_field = _field_row(grid, "Capacity", "Wh")
	_bat_mass_field = _field_row(grid, "Mass",     "kg")
	for field: LineEdit in [_capacity_field, _bat_mass_field]:
		field.text_changed.connect(func(_s: String): _update_budget())
	parent.add_child(HSeparator.new())

func _build_consumers_section(parent: VBoxContainer) -> void:
	_section_label(parent, "CONSUMERS")
	var grid := _new_grid(parent)
	_payload_w_field = _field_row(grid, "Payload",   "W")
	_obdh_w_field    = _field_row(grid, "OBDH",      "W")
	_ttc_w_field     = _field_row(grid, "TT&C",      "W")
	_act_w_field     = _field_row(grid, "Actuators", "W")
	for field: LineEdit in [_payload_w_field, _obdh_w_field, _ttc_w_field, _act_w_field]:
		field.text_changed.connect(func(_s: String): _update_budget())
	parent.add_child(HSeparator.new())

func _build_budget_section(parent: VBoxContainer) -> void:
	_section_label(parent, "POWER BUDGET")
	var grid := _new_grid(parent)
	_total_label     = _display_row(grid, "Total consumption", "—", "W")
	_endurance_label = _display_row(grid, "Endurance",         "—", "h")
	_margin_label    = _display_row(grid, "1h reserve",        "—", "%")
	parent.add_child(HSeparator.new())

func _load_and_populate() -> void:
	_params = MissionParamsIO.load_params()
	if _params.is_empty():
		_set_status("No params file")
		return
	var pw: Dictionary = _params.get("power", {})
	var c:  Dictionary = pw.get("consumers", {})
	_capacity_field.text  = str(float(pw.get("battery_capacity_wh", 20.0)))
	_bat_mass_field.text  = str(float(pw.get("battery_mass_kg",      0.3)))
	_payload_w_field.text = str(float(c.get("payload_w",             5.0)))
	_obdh_w_field.text    = str(float(c.get("obdh_w",               3.0)))
	_ttc_w_field.text     = str(float(c.get("ttc_w",                2.0)))
	_act_w_field.text     = str(float(c.get("actuators_w",           0.5)))
	_set_status("")
	_update_budget()

func _update_budget() -> void:
	var cap    := float(_capacity_field.text)  if _capacity_field.text.is_valid_float()  else 20.0
	var pl_w   := float(_payload_w_field.text) if _payload_w_field.text.is_valid_float() else 5.0
	var ob_w   := float(_obdh_w_field.text)    if _obdh_w_field.text.is_valid_float()    else 3.0
	var tt_w   := float(_ttc_w_field.text)     if _ttc_w_field.text.is_valid_float()     else 2.0
	var ac_w   := float(_act_w_field.text)     if _act_w_field.text.is_valid_float()     else 0.5

	var total := pl_w + ob_w + tt_w + ac_w
	_total_label.text = "%.2f" % total

	if total > 0.0:
		var endurance  := cap / total
		var used_1h_wh := total  # W × 1h = Wh consumed in 1 hour
		var reserve_pct := (cap - used_1h_wh) / cap * 100.0 if cap > 0.0 else 0.0
		_endurance_label.text = "%.2f" % endurance
		_margin_label.text    = "%.1f" % reserve_pct
	else:
		_endurance_label.text = "—"
		_margin_label.text    = "—"

func _on_apply() -> void:
	if _params.is_empty():
		_params = MissionParamsIO.load_params()
	if not _params.has("power"):
		_params["power"] = {}
	_params["power"]["battery_capacity_wh"] = float(_capacity_field.text)
	_params["power"]["battery_mass_kg"]     = float(_bat_mass_field.text)
	if not _params["power"].has("consumers"):
		_params["power"]["consumers"] = {}
	_params["power"]["consumers"]["payload_w"]   = float(_payload_w_field.text)
	_params["power"]["consumers"]["obdh_w"]      = float(_obdh_w_field.text)
	_params["power"]["consumers"]["ttc_w"]       = float(_ttc_w_field.text)
	_params["power"]["consumers"]["actuators_w"] = float(_act_w_field.text)
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
