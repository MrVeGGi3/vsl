extends Control

signal orbit_drag(delta: Vector2)
signal zoom_step(factor: float)

const GIZMO_RADIUS := 26.0
const GIZMO_MARGIN := 10.0
const AXIS_LEN     := 20.0
const LINE_W       := 2.0
const DOT_R        := 3.5
const LABEL_SIZE   := 9

var _cam:      Camera3D = null
var _dragging: bool     = false

func set_camera(cam: Camera3D) -> void:
	_cam = cam

func _get_gizmo_center() -> Vector2:
	var s: Vector2 = get_size()
	return Vector2(GIZMO_MARGIN + GIZMO_RADIUS, s.y - GIZMO_MARGIN - GIZMO_RADIUS)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_step.emit(0.9)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_step.emit(1.1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event
		orbit_drag.emit(mm.relative)
		accept_event()

func _draw() -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var center: Vector2 = _get_gizmo_center()

	draw_circle(center, GIZMO_RADIUS + 2.0, Color(0.05, 0.06, 0.10, 0.72))

	var cam_inv: Basis = _cam.global_transform.basis.inverse()

	var axes: Array = [
		{"world": Vector3.RIGHT, "color": Color(0.95, 0.25, 0.25), "label": "X"},
		{"world": Vector3.UP,    "color": Color(0.25, 0.90, 0.35), "label": "Y"},
		{"world": Vector3.BACK,  "color": Color(0.30, 0.55, 1.00), "label": "Z"},
	]

	for ax: Dictionary in axes:
		var v3: Vector3 = cam_inv * ax["world"]
		ax["screen"] = Vector2(v3.x, -v3.y) * AXIS_LEN
		ax["depth"]  = v3.z

	axes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["depth"] > b["depth"]
	)

	var font: Font = ThemeDB.fallback_font
	for ax: Dictionary in axes:
		var tip: Vector2 = center + ax["screen"]
		var alpha: float = lerpf(0.40, 1.0, clampf((-ax["depth"] + 1.0) * 0.5, 0.0, 1.0))
		var col: Color = ax["color"]
		col.a = alpha
		draw_line(center, tip, col, LINE_W)
		draw_circle(tip, DOT_R, col)
		draw_string(font, tip + Vector2(4.0, 3.0), ax["label"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, col)
