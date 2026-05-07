extends Node3D

const MAX_POINTS    := 16384
const COLOR_SUNLIT  := Color(0.2, 0.6, 1.0)
const COLOR_ECLIPSE := Color(0.45, 0.1, 0.7)
const COLOR_ACCESS  := Color(0.2, 0.9, 0.3)
const GS_LINE_COLOR := Color(1.0, 0.85, 0.0)

var _positions: PackedVector3Array
var _colors:    PackedColorArray
var _point_count:   int   = 0
var _last_frame_id: int   = -1

var _orbit_start_t_s: float = 0.0
var _orbit_step_s:    float = 10.0

var _eclipse_starts: PackedFloat64Array = PackedFloat64Array()
var _eclipse_ends:   PackedFloat64Array = PackedFloat64Array()
var _access_windows: Array = []

var _orbit_multimesh: MultiMeshInstance3D
var _gs_line_mesh:     ImmediateMesh
var _gs_line_instance: MeshInstance3D
var _gs_marker_ref:    Node3D = null

func _ready() -> void:
	_positions = PackedVector3Array()
	_positions.resize(MAX_POINTS)
	_colors = PackedColorArray()
	_colors.resize(MAX_POINTS)
	for i in MAX_POINTS:
		_colors[i] = COLOR_SUNLIT

	# MultiMesh with spheres — PRIMITIVE_LINE_STRIP is 1px on Vulkan and invisible
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.025
	dot_mesh.height = 0.05
	dot_mesh.radial_segments = 4
	dot_mesh.rings = 2
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.vertex_color_use_as_albedo = true
	dot_mat.emission_enabled = true
	dot_mat.emission_energy_multiplier = 2.0
	dot_mesh.surface_set_material(0, dot_mat)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = dot_mesh
	mm.instance_count = MAX_POINTS
	mm.visible_instance_count = 0

	_orbit_multimesh = MultiMeshInstance3D.new()
	_orbit_multimesh.multimesh = mm
	add_child(_orbit_multimesh)

	# Hide the legacy OrbitLine node (replaced by MultiMesh)
	var orbit_line := $OrbitLine as MeshInstance3D
	if orbit_line:
		orbit_line.visible = false

	_gs_line_mesh = ImmediateMesh.new()
	_gs_line_instance = MeshInstance3D.new()
	_gs_line_instance.mesh = _gs_line_mesh
	var gs_mat := StandardMaterial3D.new()
	gs_mat.albedo_color = GS_LINE_COLOR
	gs_mat.emission_enabled = true
	gs_mat.emission = GS_LINE_COLOR
	gs_mat.emission_energy_multiplier = 2.5
	gs_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gs_mat.no_depth_test = true
	_gs_line_instance.material_override = gs_mat
	add_child(_gs_line_instance)

func _process(_delta: float) -> void:
	var bridge := get_node_or_null("/root/Main/SolverBridge")
	if bridge == null:
		return

	_update_gs_line(bridge)

	if not bridge.has_method("has_new_data"):
		return
	if not bridge.has_new_data(_last_frame_id):
		return

	_point_count   = bridge.get_point_count()
	_last_frame_id = bridge.get_frame_id()
	bridge.copy_positions_to(_positions, _point_count)
	_fetch_analysis_data(bridge)
	_compute_colors()
	_draw_orbit()

func _fetch_analysis_data(bridge: Node) -> void:
	if bridge.has_method("get_orbit_start_t_s"):
		_orbit_start_t_s = bridge.get_orbit_start_t_s()
	if bridge.has_method("get_orbit_step_s"):
		_orbit_step_s = bridge.get_orbit_step_s()
	if bridge.has_method("get_eclipse_result"):
		var ecl: Dictionary = bridge.get_eclipse_result()
		if ecl.has("period_starts"):
			_eclipse_starts = ecl["period_starts"] as PackedFloat64Array
			_eclipse_ends   = ecl["period_ends"]   as PackedFloat64Array
	if bridge.has_method("get_access_windows"):
		_access_windows = bridge.get_access_windows()

func _compute_colors() -> void:
	for i in _point_count:
		var t := _orbit_start_t_s + float(i) * _orbit_step_s
		_colors[i] = _classify(t)

func _classify(t: float) -> Color:
	for w in _access_windows:
		if t >= float(w["t_start_s"]) and t <= float(w["t_end_s"]):
			return COLOR_ACCESS
	var n := _eclipse_starts.size()
	for i in n:
		if t >= _eclipse_starts[i] and t <= _eclipse_ends[i]:
			return COLOR_ECLIPSE
	return COLOR_SUNLIT

func _draw_orbit() -> void:
	var mm := _orbit_multimesh.multimesh as MultiMesh
	mm.visible_instance_count = _point_count
	for i in _point_count:
		mm.set_instance_transform(i, Transform3D(Basis(), _positions[i]))
		var c := _colors[i]
		mm.set_instance_color(i, Color(c.r * 2.0, c.g * 2.0, c.b * 2.0))

func _update_gs_line(bridge: Node) -> void:
	_gs_line_mesh.clear_surfaces()

	if _gs_marker_ref == null:
		_gs_marker_ref = get_node_or_null("/root/Main/Earth/GSMarker") as Node3D
	if _gs_marker_ref == null or _point_count == 0:
		return

	if not bridge.has_method("get_sim_time_s"):
		return
	var t_now: float = bridge.get_sim_time_s()

	var in_pass := false
	for w in _access_windows:
		if t_now >= float(w["t_start_s"]) and t_now <= float(w["t_end_s"]):
			in_pass = true
			break
	if not in_pass:
		return

	var idx := clampi(int((t_now - _orbit_start_t_s) / _orbit_step_s), 0, _point_count - 1)
	var sat_pos := _positions[idx]
	var gs_pos  := _gs_marker_ref.global_transform.origin

	_gs_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_gs_line_mesh.surface_add_vertex(gs_pos)
	_gs_line_mesh.surface_add_vertex(sat_pos)
	_gs_line_mesh.surface_end()

func invalidate_gs_marker() -> void:
	_gs_marker_ref = null

func get_current_sat_position() -> Vector3:
	if _point_count <= 0:
		return Vector3.ZERO
	var bridge := get_node_or_null("/root/Main/SolverBridge")
	if bridge == null or not bridge.has_method("get_sim_time_s"):
		return _positions[0]
	var t_now := bridge.get_sim_time_s() as float
	var idx := clampi(int((t_now - _orbit_start_t_s) / _orbit_step_s), 0, _point_count - 1)
	return _positions[idx]
