extends XRController3D

# true = right hand (laser pointer + zoom), false = left hand (grab-rotate)
@export var is_right_hand: bool = true

const RAY_LENGTH       := 10.0
const GRAB_SENSITIVITY := 100.0   # degrees per meter of controller movement
const ZOOM_SPEED       := 0.3     # scale factor per second at max thumbstick
const HAPTIC_DUR       := 0.05
const HAPTIC_AMP       := 0.3

var _vr_active    := false
var _grip_held    := false
var _zoom_axis    := 0.0
var _prev_pos     := Vector3.ZERO

var _ray_cast     : RayCast3D      = null
var _ray_mesh     : ImmediateMesh  = null
var _ray_instance : MeshInstance3D = null
var _scene_root   : Node3D         = null

func _ready() -> void:
	var main := get_node_or_null("/root/Main") as Node3D
	if main == null or not main._vr_active:
		return
	_vr_active  = true
	_scene_root = main
	_prev_pos   = global_transform.origin

	button_pressed.connect(_on_button_pressed)
	button_released.connect(_on_button_released)
	input_vector2_changed.connect(_on_thumbstick)

	if is_right_hand:
		_setup_pointer_ray()

func _setup_pointer_ray() -> void:
	_ray_cast = RayCast3D.new()
	_ray_cast.enabled = true
	_ray_cast.target_position = Vector3(0.0, 0.0, -RAY_LENGTH)
	_ray_cast.collision_mask  = 4   # layer 3 — VR UI panel
	add_child(_ray_cast)

	_ray_mesh = ImmediateMesh.new()
	_ray_instance = MeshInstance3D.new()
	_ray_instance.mesh = _ray_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 1.0, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	_ray_instance.material_override = mat
	add_child(_ray_instance)

func _process(delta: float) -> void:
	if not _vr_active:
		return

	if is_right_hand and _ray_cast != null:
		_update_ray_visual()

	if _grip_held and not is_right_hand:
		_apply_grab_rotation()

	if absf(_zoom_axis) > 0.15:
		_apply_zoom(delta)

	_prev_pos = global_transform.origin

func _update_ray_visual() -> void:
	_ray_mesh.clear_surfaces()
	_ray_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_ray_mesh.surface_add_vertex(Vector3.ZERO)
	if _ray_cast.is_colliding():
		_ray_mesh.surface_add_vertex(to_local(_ray_cast.get_collision_point()))
	else:
		_ray_mesh.surface_add_vertex(Vector3(0.0, 0.0, -RAY_LENGTH))
	_ray_mesh.surface_end()

func _apply_grab_rotation() -> void:
	var delta := global_transform.origin - _prev_pos
	if delta.length_squared() < 1e-8:
		return
	var rot_y := deg_to_rad(-delta.x * GRAB_SENSITIVITY)
	var rot_x := deg_to_rad(-delta.y * GRAB_SENSITIVITY)
	var earth := _scene_root.get_node_or_null("Earth") as Node3D
	var orbit := _scene_root.get_node_or_null("OrbitViewer") as Node3D
	if earth:
		earth.rotate_y(rot_y)
		earth.rotate_x(rot_x)
	if orbit:
		orbit.rotate_y(rot_y)
		orbit.rotate_x(rot_x)

func _apply_zoom(delta: float) -> void:
	var factor := 1.0 + _zoom_axis * ZOOM_SPEED * delta
	var earth := _scene_root.get_node_or_null("Earth") as Node3D
	var orbit := _scene_root.get_node_or_null("OrbitViewer") as Node3D
	if earth:
		var s := (earth.scale * factor).clamp(Vector3(0.1, 0.1, 0.1), Vector3(3.0, 3.0, 3.0))
		earth.scale = s
	if orbit:
		orbit.scale = earth.scale if earth else orbit.scale

func _on_button_pressed(name: String) -> void:
	match name:
		"grip_click":
			_grip_held = true
			trigger_haptic_pulse("haptic", 0.0, HAPTIC_DUR, HAPTIC_AMP, 0.0)
		"trigger_click":
			if is_right_hand:
				_try_interact()
		"by_button":
			_toggle_vr_panel()

func _on_button_released(name: String) -> void:
	if name == "grip_click":
		_grip_held = false

func _on_thumbstick(name: String, value: Vector2) -> void:
	if name == "primary" and is_right_hand:
		_zoom_axis = value.y

func _try_interact() -> void:
	if _ray_cast == null or not _ray_cast.is_colliding():
		return
	var collider := _ray_cast.get_collider()
	if collider == null:
		return
	var panel := collider.get_parent()
	if panel and panel.has_method("on_ray_select"):
		panel.on_ray_select(_ray_cast.get_collision_point())
		trigger_haptic_pulse("haptic", 0.0, HAPTIC_DUR * 0.5, HAPTIC_AMP * 0.5, 0.0)

func _toggle_vr_panel() -> void:
	if _scene_root == null:
		return
	var panel := _scene_root.get_node_or_null("VRUIPanel")
	if panel:
		panel.visible = not panel.visible
		trigger_haptic_pulse("haptic", 0.0, HAPTIC_DUR, HAPTIC_AMP * 0.4, 0.0)
