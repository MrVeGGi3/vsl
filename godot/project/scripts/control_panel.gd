extends PanelContainer

const PANEL_W := 265.0
const PANEL_H := 420.0

var _dragging := false
var _drag_offset := Vector2.ZERO

var _xcp_label:    Label
var _xcg_label:    Label
var _stab_label:   Label

var _nfins_label:  Label
var _cr_label:     Label
var _ct_label:     Label
var _span_label:   Label
var _cna_label:    Label

var _aoa_label:    Label
var _omega_label:  Label

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

	_build_static_section(inner)
	_build_fins_section(inner)
	_build_dynamic_section(inner)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 10)
	inner.add_child(_status_label)

	_refresh_data()

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
	title.text = "CONTROL / STABILITY"
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

func _build_static_section(parent: VBoxContainer) -> void:
	_section_label(parent, "STATIC STABILITY")
	var grid := _new_grid(parent)
	_xcp_label  = _display_row(grid, "xCP",              "—", "m")
	_xcg_label  = _display_row(grid, "xCG",              "—", "m")
	_stab_label = _display_row(grid, "Stability margin", "—", "cal")
	parent.add_child(HSeparator.new())

func _build_fins_section(parent: VBoxContainer) -> void:
	_section_label(parent, "FINS (BARROWMAN)")
	var grid := _new_grid(parent)
	_nfins_label = _display_row(grid, "N fins",     "—", "—")
	_cr_label    = _display_row(grid, "Root chord", "—", "cm")
	_ct_label    = _display_row(grid, "Tip chord",  "—", "cm")
	_span_label  = _display_row(grid, "Semi-span",  "—", "cm")
	_cna_label   = _display_row(grid, "CN_α (fins)","—", "—")
	parent.add_child(HSeparator.new())

func _build_dynamic_section(parent: VBoxContainer) -> void:
	_section_label(parent, "DYNAMIC (6-DOF)")
	var grid := _new_grid(parent)
	_aoa_label   = _display_row(grid, "Max AoA",          "—", "°")
	_omega_label = _display_row(grid, "Max angular rate",  "—", "rad/s")
	parent.add_child(HSeparator.new())

func _refresh_data() -> void:
	var params := MissionParamsIO.load_params()
	if params.is_empty():
		_set_status("No params")
		return

	var rkt: Dictionary = params.get("rocket", {})
	var xcp := float(rkt.get("xcp_m",          0.85))
	var xcg := float(rkt.get("xcg_m",          0.55))
	var d   := float(rkt.get("body_diameter_m", 0.08))

	_xcp_label.text  = "%.3f" % xcp
	_xcg_label.text  = "%.3f" % xcg
	_stab_label.text = "%.2f" % ((xcp - xcg) / d) if d > 0.0 else "—"

	var fins: Dictionary = rkt.get("fins", {})
	var N  := int(float(fins.get("n_fins",        4)))
	var Cr := float(fins.get("root_chord_m",      0.15))
	var Ct := float(fins.get("tip_chord_m",       0.05))
	var s  := float(fins.get("semi_span_m",       0.10))

	_nfins_label.text = str(N)
	_cr_label.text    = "%.1f" % (Cr * 100.0)
	_ct_label.text    = "%.1f" % (Ct * 100.0)
	_span_label.text  = "%.1f" % (s  * 100.0)

	var r     := d * 0.5
	var cr_ct := Cr + Ct
	if N > 0 and cr_ct > 0.0 and d > 0.0:
		var K     := 1.0 + r / (r + s)
		var ar    := 2.0 * s / cr_ct
		var denom := 1.0 + sqrt(1.0 + ar * ar)
		_cna_label.text = "%.3f" % (K * 4.0 * float(N) * pow(s / d, 2.0) / denom)
	else:
		_cna_label.text = "—"

	var bridge := get_node_or_null("/root/Main/SolverBridge")
	if bridge == null or not bridge.has_method("get_trajectory_summary"):
		_set_status("")
		return
	var traj: Dictionary = bridge.get_trajectory_summary()
	if traj.is_empty():
		_set_status("")
		return

	_aoa_label.text   = "%.1f" % float(traj.get("max_aoa_deg",            0.0))
	_omega_label.text = "%.3f" % float(traj.get("max_angular_rate_rad_s", 0.0))
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
