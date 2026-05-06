extends Control

const BTN_AREA_W  := 180.0
const BAR_Y       := 12.0
const BAR_H       := 22.0
const LABEL_SIZE  := 10

var _eclipse_starts: PackedFloat64Array = PackedFloat64Array()
var _eclipse_ends:   PackedFloat64Array = PackedFloat64Array()
var _access_windows: Array = []
var _duration_s: float = 86400.0
var _t_now:      float = 0.0

var _frame_tick: int = 0

func _ready() -> void:
	set_anchor_and_offset(SIDE_LEFT,   0.0,    0.0)
	set_anchor_and_offset(SIDE_RIGHT,  1.0,    0.0)
	set_anchor_and_offset(SIDE_TOP,    1.0,  -68.0)
	set_anchor_and_offset(SIDE_BOTTOM, 1.0,    0.0)

	_build_speed_buttons()

func _build_speed_buttons() -> void:
	var hbox := HBoxContainer.new()
	hbox.set_anchor_and_offset(SIDE_LEFT,   1.0, -BTN_AREA_W)
	hbox.set_anchor_and_offset(SIDE_RIGHT,  1.0,           0.0)
	hbox.set_anchor_and_offset(SIDE_TOP,    0.0,           0.0)
	hbox.set_anchor_and_offset(SIDE_BOTTOM, 1.0,           0.0)
	add_child(hbox)

	var speed_label := Label.new()
	speed_label.text = " Speed:"
	hbox.add_child(speed_label)

	for speed in [1, 10, 100, 1000]:
		var btn := Button.new()
		btn.text = "×%d" % speed
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var s: int = speed  # capture for closure
		btn.pressed.connect(func(): _set_speed(s))
		hbox.add_child(btn)

func _set_speed(speed: int) -> void:
	var bridge := get_node_or_null("/root/Main/SolverBridge")
	if bridge and bridge.has_method("set_sim_speed"):
		bridge.set_sim_speed(float(speed))

func _process(_delta: float) -> void:
	_frame_tick += 1
	if _frame_tick % 30 != 0:
		return

	var bridge := get_node_or_null("/root/Main/SolverBridge")
	if bridge == null:
		return

	var dirty := false

	if bridge.has_method("get_sim_time_s"):
		var t: float = bridge.get_sim_time_s()
		if t != _t_now:
			_t_now = t
			dirty  = true

	if bridge.has_method("get_mission_summary"):
		var s: Dictionary = bridge.get_mission_summary()
		if s.has("duration_s"):
			var d := float(s["duration_s"])
			if d != _duration_s:
				_duration_s = d
				dirty = true

	if bridge.has_method("get_eclipse_result"):
		var ecl: Dictionary = bridge.get_eclipse_result()
		if ecl.has("period_starts"):
			_eclipse_starts = ecl["period_starts"] as PackedFloat64Array
			_eclipse_ends   = ecl["period_ends"]   as PackedFloat64Array
			dirty = true

	if bridge.has_method("get_access_windows"):
		_access_windows = bridge.get_access_windows()
		dirty = true

	if dirty:
		queue_redraw()

func _draw() -> void:
	var bar_w := size.x - BTN_AREA_W - 8.0
	if bar_w <= 8.0:
		return

	# Background strip
	draw_rect(Rect2(0, 0, bar_w, size.y), Color(0.08, 0.08, 0.12, 0.92))

	if _duration_s <= 0.0:
		return

	# Sunlit baseline
	draw_rect(Rect2(2, BAR_Y, bar_w - 4, BAR_H), Color(0.2, 0.6, 1.0, 0.55))

	# Eclipse periods (purple)
	for i in _eclipse_starts.size():
		var x0 := _to_x(_eclipse_starts[i], bar_w)
		var x1 := _to_x(_eclipse_ends[i],   bar_w)
		draw_rect(Rect2(x0, BAR_Y, maxf(x1 - x0, 1.0), BAR_H), Color(0.45, 0.1, 0.7, 0.75))

	# Access windows (green)
	for w in _access_windows:
		var x0 := _to_x(float(w["t_start_s"]), bar_w)
		var x1 := _to_x(float(w["t_end_s"]),   bar_w)
		draw_rect(Rect2(x0, BAR_Y, maxf(x1 - x0, 2.0), BAR_H), Color(0.2, 0.9, 0.3, 0.85))

	# Time cursor
	var cx := _to_x(_t_now, bar_w)
	draw_line(Vector2(cx, 0), Vector2(cx, size.y), Color(1, 1, 1, 0.9), 2.0)

	# Labels
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(4, BAR_Y - 2),
		"t=%.0fs" % _t_now, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Color.WHITE)
	draw_string(font, Vector2(bar_w - 4, BAR_Y - 2),
		"%.0fs" % _duration_s, HORIZONTAL_ALIGNMENT_RIGHT, -1, LABEL_SIZE, Color(0.7, 0.7, 0.7))

	# Legend
	var ly := BAR_Y + BAR_H + 4.0
	draw_rect(Rect2(4,  ly, 10, 8), Color(0.2, 0.6, 1.0, 0.7))
	draw_string(font, Vector2(18, ly + 8), "sunlit", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Color.WHITE)
	draw_rect(Rect2(60, ly, 10, 8), Color(0.45, 0.1, 0.7, 0.8))
	draw_string(font, Vector2(74, ly + 8), "eclipse", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Color.WHITE)
	draw_rect(Rect2(124, ly, 10, 8), Color(0.2, 0.9, 0.3, 0.85))
	draw_string(font, Vector2(138, ly + 8), "access", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Color.WHITE)

func _to_x(t: float, bar_w: float) -> float:
	return clampf(t / _duration_s * (bar_w - 4.0) + 2.0, 2.0, bar_w - 2.0)
