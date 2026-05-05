extends Node3D

func _ready() -> void:
	# Earth radius = 6.371 scene units (km scale: 1 unit = 1 km)
	# Rotation matches real sidereal rate: 360° / 86164 s ≈ 0.00418°/s
	pass

func _process(delta: float) -> void:
	rotation_degrees.y += 0.00418 * delta * 3600.0  # visual speed-up x3600 for demo
