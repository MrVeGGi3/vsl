extends PanelContainer

const PANEL_W := 265.0
const PANEL_H := 420.0

const SPEED_OF_LIGHT := 2.997924458e8  # m/s
const BOLTZMANN_DBW  := -228.599       # 10*log10(1.38e-23)
const T_SYS_DBK      := 24.613         # 10*log10(290 K)

var _params: Dictionary = {}
var _dragging := false
var _drag_offset := Vector2.ZERO

var _freq_field:    LineEdit
var _power_field:   LineEdit
var _tx_gain_field: LineEdit
var _rx_gain_field: LineEdit
var _losses_field:  LineEdit
var _range_field:   LineEdit

var _eirp_label:    Label
var _fspl_label:    Label
var _pr_label:      Label
var _cn0_label:     Label

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

	_build_link_params_section(inner)
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
	set_position(Vector2(20.0, y))

func _build_header(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 26)
	hbox.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(hbox)

	var title := Label.new()
	title.text = "TT&C / LINK BUDGET"
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

func _build_link_params_section(parent: VBoxContainer) -> void:
	_section_label(parent, "LINK PARAMETERS")
	var grid := _new_grid(parent)
	_freq_field    = _field_row(grid, "Frequency",   "MHz")
	_power_field   = _field_row(grid, "Tx power",    "W")
	_tx_gain_field = _field_row(grid, "Tx gain",     "dBi")
	_rx_gain_field = _field_row(grid, "Rx gain",     "dBi")
	_losses_field  = _field_row(grid, "Sys losses",  "dB")
	_range_field   = _field_row(grid, "Range",       "km")

	for field: LineEdit in [_freq_field, _power_field, _tx_gain_field,
							_rx_gain_field, _losses_field, _range_field]:
		field.text_changed.connect(func(_s: String): _update_link_budget())

	parent.add_child(HSeparator.new())

func _build_budget_section(parent: VBoxContainer) -> void:
	_section_label(parent, "LINK BUDGET (FRIIS)")
	var grid := _new_grid(parent)
	_eirp_label = _display_row(grid, "EIRP",        "—", "dBW")
	_fspl_label = _display_row(grid, "Free-space loss", "—", "dB")
	_pr_label   = _display_row(grid, "Rx power",    "—", "dBW")
	_cn0_label  = _display_row(grid, "C/N₀",        "—", "dB·Hz")
	parent.add_child(HSeparator.new())

func _load_and_populate() -> void:
	_params = MissionParamsIO.load_params()
	if _params.is_empty():
		_set_status("No params file")
		return
	var t: Dictionary = _params.get("ttc", {})
	_freq_field.text    = str(float(t.get("freq_mhz",        433.0)))
	_power_field.text   = str(float(t.get("tx_power_w",        1.0)))
	_tx_gain_field.text = str(float(t.get("tx_gain_dbi",        0.0)))
	_rx_gain_field.text = str(float(t.get("rx_gain_dbi",        6.0)))
	_losses_field.text  = str(float(t.get("system_losses_db",   3.0)))
	_range_field.text   = str(float(t.get("range_km",          50.0)))
	_set_status("")
	_update_link_budget()

func _update_link_budget() -> void:
	var freq_hz  := float(_freq_field.text)  * 1.0e6  if _freq_field.text.is_valid_float()    else 433.0e6
	var p_tx_w   := float(_power_field.text)            if _power_field.text.is_valid_float()   else 1.0
	var g_tx     := float(_tx_gain_field.text)           if _tx_gain_field.text.is_valid_float() else 0.0
	var g_rx     := float(_rx_gain_field.text)           if _rx_gain_field.text.is_valid_float() else 6.0
	var losses   := float(_losses_field.text)            if _losses_field.text.is_valid_float()  else 3.0
	var range_m  := float(_range_field.text) * 1.0e3   if _range_field.text.is_valid_float()   else 50.0e3

	if p_tx_w <= 0.0 or freq_hz <= 0.0 or range_m <= 0.0:
		_eirp_label.text = "—"
		_fspl_label.text = "—"
		_pr_label.text   = "—"
		_cn0_label.text  = "—"
		return

	var eirp := 10.0 * log(p_tx_w) / log(10.0) + g_tx
	var fspl  := 20.0 * log(4.0 * PI * range_m * freq_hz / SPEED_OF_LIGHT) / log(10.0)
	var pr    := eirp - fspl + g_rx - losses
	var cn0   := pr - (BOLTZMANN_DBW + T_SYS_DBK)

	_eirp_label.text = "%.2f" % eirp
	_fspl_label.text = "%.1f" % fspl
	_pr_label.text   = "%.2f" % pr
	_cn0_label.text  = "%.1f" % cn0

func _on_apply() -> void:
	if _params.is_empty():
		_params = MissionParamsIO.load_params()
	if not _params.has("ttc"):
		_params["ttc"] = {}
	_params["ttc"]["freq_mhz"]         = float(_freq_field.text)
	_params["ttc"]["tx_power_w"]       = float(_power_field.text)
	_params["ttc"]["tx_gain_dbi"]      = float(_tx_gain_field.text)
	_params["ttc"]["rx_gain_dbi"]      = float(_rx_gain_field.text)
	_params["ttc"]["system_losses_db"] = float(_losses_field.text)
	_params["ttc"]["range_km"]         = float(_range_field.text)
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
