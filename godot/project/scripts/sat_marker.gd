extends MeshInstance3D

func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh = sphere

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/sat_glow.gdshader")
	mat.set_shader_parameter("glow_color", Color(1.0, 0.9, 0.2, 1.0))
	mat.set_shader_parameter("pulse_speed", 3.0)
	material_override = mat

func _process(_delta: float) -> void:
	var renderer := get_parent() as Node
	if renderer == null or not renderer.has_method("get_current_sat_position"):
		return
	global_position = renderer.get_current_sat_position()
