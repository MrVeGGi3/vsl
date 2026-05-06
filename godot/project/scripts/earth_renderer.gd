extends Node3D

var _material:  ShaderMaterial
var _sun_light: DirectionalLight3D
var _gs_marker: MeshInstance3D = null

func _ready() -> void:
	_material = $EarthMesh.material_override as ShaderMaterial
	_load_textures()
	_sun_light = get_node_or_null("../DirectionalLight3D")

func _load_textures() -> void:
	_try_set_texture("albedo_texture", "res://textures/earth/earth_daymap.jpg")
	_try_set_texture("night_texture",  "res://textures/earth/earth_nightmap.jpg")
	_try_set_texture("cloud_texture",  "res://textures/earth/earth_clouds.jpg")

func _try_set_texture(param: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		push_warning("VSL: texture not found — " + path)
		return
	var tex := ResourceLoader.load(path, "Texture2D") as Texture2D
	if tex:
		_material.set_shader_parameter(param, tex)

func set_ground_station(lat_deg: float, lon_deg: float) -> void:
	if _gs_marker:
		_gs_marker.queue_free()
		var orbit_viewer := get_node_or_null("../OrbitViewer")
		if orbit_viewer and orbit_viewer.has_method("invalidate_gs_marker"):
			orbit_viewer.invalidate_gs_marker()

	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	const R := 6.371
	# Godot sphere: Y-up, lon=0 toward +Z, lon increases CCW from above.
	var pos := Vector3(
		R * cos(lat) * sin(lon),
		R * sin(lat),
		R * cos(lat) * cos(lon)
	)

	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	sphere.radial_segments = 8
	sphere.rings = 4

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.0)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_gs_marker = MeshInstance3D.new()
	_gs_marker.name = "GSMarker"
	_gs_marker.mesh = sphere
	_gs_marker.material_override = mat
	_gs_marker.position = pos
	add_child(_gs_marker)

func _process(delta: float) -> void:
	rotation_degrees.y += 0.00418 * delta * 3600.0
	if _sun_light and _material:
		var dir := -_sun_light.global_transform.basis.z
		_material.set_shader_parameter("sun_direction", dir)
