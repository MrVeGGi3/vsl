extends Node3D

var _material: ShaderMaterial
var _sun_light: DirectionalLight3D

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

func _process(delta: float) -> void:
	rotation_degrees.y += 0.00418 * delta * 3600.0
	if _sun_light and _material:
		var dir := -_sun_light.global_transform.basis.z
		_material.set_shader_parameter("sun_direction", dir)
