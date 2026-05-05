extends Node3D

const MAX_POINTS := 16384

var _positions: PackedVector3Array
var _point_count: int = 0
var _last_frame_id: int = -1

func _ready() -> void:
	_positions = PackedVector3Array()
	_positions.resize(MAX_POINTS)

func _process(_delta: float) -> void:
	var bridge = get_node_or_null("/root/Main/SolverBridge")
	if bridge == null:
		return
	if not bridge.has_method("has_new_data"):
		return
	if not bridge.has_new_data(_last_frame_id):
		return

	_point_count = bridge.get_point_count()
	_last_frame_id = bridge.get_frame_id()
	bridge.copy_positions_to(_positions, _point_count)
	_draw_orbit()

func _draw_orbit() -> void:
	var mesh := $OrbitLine as ImmediateMesh
	if mesh == null:
		return
	mesh.clear_surfaces()
	if _point_count < 2:
		return

	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in _point_count:
		mesh.surface_add_vertex(_positions[i])
	mesh.surface_end()
