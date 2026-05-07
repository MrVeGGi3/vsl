extends MeshInstance3D

func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.2)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_override = mat

func _process(_delta: float) -> void:
	var renderer := get_parent() as Node
	if renderer == null or not renderer.has_method("get_current_sat_position"):
		return
	global_position = renderer.get_current_sat_position()
