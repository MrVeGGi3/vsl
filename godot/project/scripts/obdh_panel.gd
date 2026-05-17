extends PanelContainer

const PANEL_W := 260.0
const PANEL_H := 360.0

var _params: Dictionary = {}
var _dragging := false
var _drag_offset := Vector2.ZERO

var _mass_field:      LineEdit
var _processor_field: LineEdit
var _rate_field:      LineEdit
var _storage_field:   LineEdit
var _power_field:     LineEdit

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

	_build_hardware_section(inner)
	_build_data_section(inner)
	_build_power_section(inner)

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
	title.text = "OBDH"
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

func _build_hardware_section(parent: VBoxContainer) -> void:
	_section_label(parent, "HARDWARE")
	var grid := _new_grid(parent)
	_mass_field      = _field_row(grid, "Mass",      "kg")
	_processor_field = _field_row(grid, "Processor", "—")
	parent.add_child(HSeparator.new())

func _build_data_section(parent: VBoxContainer) -> void:
	_section_label(parent, "DATA")
	var grid := _new_grid(parent)
	_rate_field    = _field_row(grid, "Data rate", "kbps")
	_storage_field = _field_row(grid, "Storage",   "MB")
	parent.add_child(HSeparator.new())

func _build_power_section(parent: VBoxContainer) -> void:
	_section_label(parent, "POWER")
	var grid := _new_grid(parent)
	_power_field = _field_row(grid, "Avg consumption", "W")
	parent.add_child(HSeparator.new())

func _load_and_populate() -> void:
	_params = MissionParamsIO.load_params()
	if _params.is_empty():
		_set_status("No params file")
		return
	var o: Dictionary = _params.get("obdh", {})
	_mass_field.text      = str(float(o.get("mass_kg",        0.5)))
	_processor_field.text = str(o.get("processor",            "STM32H7"))
	_rate_field.text      = str(float(o.get("data_rate_kbps", 100.0)))
	_storage_field.text   = str(float(o.get("storage_mb",     128.0)))
	_power_field.text     = str(float(o.get("power_avg_w",    3.0)))
	_set_status("")

func _on_apply() -> void:
	if _params.is_empty():
		_params = MissionParamsIO.load_params()
	if not _params.has("obdh"):
		_params["obdh"] = {}
	_params["obdh"]["mass_kg"]        = float(_mass_field.text)
	_params["obdh"]["processor"]      = _processor_field.text
	_params["obdh"]["data_rate_kbps"] = float(_rate_field.text)
	_params["obdh"]["storage_mb"]     = float(_storage_field.text)
	_params["obdh"]["power_avg_w"]    = float(_power_field.text)
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
