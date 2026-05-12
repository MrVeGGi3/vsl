extends Control

const MAX_POINTS   := 1024
const MARGIN       := 28.0
const LINE_WIDTH   := 1.5

const COLOR_GROUND := Color(0.15, 0.40, 1.00)
const COLOR_APOGEE := Color(1.00, 0.25, 0.05)
const AXIS_COLOR   := Color(0.55, 0.55, 0.55, 0.70)
const BG_COLOR     := Color(0.06, 0.07, 0.12, 0.88)
const BORDER_COLOR := Color(0.28, 0.30, 0.50, 0.80)

var _positions:   PackedVector3Array  # ENU→Godot: .x=East, .y=Up, .z=-North
var _times:       PackedFloat32Array
var _point_count: int   = 0
var _loaded:      bool  = false
var _apogee_m:    float = 0.0
var _apogee_t:    float = 0.0

const PANEL_W := 300.0
const PANEL_H := 210.0

func _ready() -> void:
	_positions = PackedVector3Array()
	_positions.resize(MAX_POINTS)
	_do_layout()
	get_viewport().size_changed.connect(_do_layout)

func _do_layout() -> void:
	var vp := get_viewport_rect().size
	# Bottom-left corner, above the 46 px timeline strip
	set_position(Vector2(0.0, vp.y - PANEL_H - 46.0))
	set_size(Vector2(PANEL_W, PANEL_H))
	clip_contents = true  # prevent draw calls from escaping the panel rect

func _process(_delta: float) -> void:
	if _loaded:
		return
	var bridge := get_node_or_null("/root/Main/SolverBridge")
	if bridge == null or not bridge.has_method("get_trajectory_point_count"):
		return
	_point_count = bridge.get_trajectory_point_count()
	if _point_count <= 0:
		return
	bridge.copy_trajectory_positions_to(_positions, _point_count)
	_times    = bridge.get_trajectory_times()
	_apogee_m = bridge.get_trajectory_apogee_m()

	var max_alt := 0.0
	for i in _point_count:
		if _positions[i].y > max_alt:
			max_alt   = _positions[i].y
			_apogee_t = float(_times[i])

	_loaded = true
	queue_redraw()

func _draw() -> void:
	var sz   := get_size()
	var font := ThemeDB.fallback_font

	# Background + border
	draw_rect(Rect2(Vector2.ZERO, sz), BG_COLOR,     true)
	draw_rect(Rect2(Vector2.ZERO, sz), BORDER_COLOR, false, 1.0)

	# Title
	draw_string(font, Vector2(6.0, 13.0),
		"SOUNDING ROCKET — Altitude vs Time",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.88, 0.88, 0.95))

	if not _loaded or _point_count <= 0:
		draw_string(font, sz * 0.5, "No data",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0.45, 0.45, 0.45))
		return

	# Plot area
	var x0 := MARGIN
	var y0 := 18.0                       # top, below title
	var pw  := sz.x - MARGIN - 6.0      # plot width
	var ph  := sz.y - y0 - MARGIN       # plot height
	var origin := Vector2(x0, y0 + ph)  # bottom-left of plot axes

	# Clip trajectory to air-time only (altitude >= 0); last point underground breaks the chart
	var n_draw := _point_count
	for i in range(_point_count - 1, -1, -1):
		if _positions[i].y >= 0.0:
			n_draw = i + 1
			break

	var t_max   := maxf(float(_times[n_draw - 1]), 1.0)
	var alt_max := maxf(_apogee_m, 1.0)

	# Axes
	draw_line(origin, origin + Vector2(pw, 0),  AXIS_COLOR)
	draw_line(origin, origin + Vector2(0, -ph), AXIS_COLOR)

	# Apogee dashed horizontal reference
	var apo_y := origin.y - (_apogee_m / alt_max) * ph
	var xi := int(x0)
	while xi < int(x0 + pw):
		draw_line(Vector2(xi, apo_y), Vector2(xi + 4, apo_y),
			Color(1.0, 0.4, 0.1, 0.45))
		xi += 8

	# Trajectory polyline — only valid (above-ground) points
	var pts    := PackedVector2Array()
	var colors := PackedColorArray()
	pts.resize(n_draw)
	colors.resize(n_draw)
	for i in n_draw:
		var t_n := float(_times[i]) / t_max
		var a_n := clampf(_positions[i].y / alt_max, 0.0, 1.0)
		pts[i]    = Vector2(origin.x + t_n * pw, origin.y - a_n * ph)
		colors[i] = COLOR_GROUND.lerp(COLOR_APOGEE, a_n)
	draw_polyline_colors(pts, colors, LINE_WIDTH, true)

	# Apogee dot + label
	var apo_t_n := _apogee_t / t_max
	var apo_pt  := Vector2(origin.x + apo_t_n * pw, apo_y)
	draw_circle(apo_pt, 3.5, COLOR_APOGEE)
	draw_string(font, apo_pt + Vector2(5.0, -2.0),
		"%.0f m" % _apogee_m,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_APOGEE)

	# Axis tick labels
	draw_string(font, origin + Vector2(1.0, 11.0),
		"0", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, AXIS_COLOR)
	draw_string(font, origin + Vector2(pw - 22.0, 11.0),
		"%.0fs" % t_max, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, AXIS_COLOR)
	draw_string(font, Vector2(3.0, y0 + 8.0),
		"%.0fm" % alt_max, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, AXIS_COLOR)
