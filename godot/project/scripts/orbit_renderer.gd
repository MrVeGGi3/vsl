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
	var mesh_instance := $OrbitLine as MeshInstance3D
	if mesh_instance == null:
		return
	if not mesh_instance.mesh is ArrayMesh:
		mesh_instance.mesh = ArrayMesh.new()
	var mesh := mesh_instance.mesh as ArrayMesh
	mesh.clear_surfaces()
	if _point_count < 2:
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _positions.slice(0, _point_count)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
