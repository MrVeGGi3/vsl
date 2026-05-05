extends XRController3D

func _process(_delta: float) -> void:
	var main = get_node_or_null("/root/Main")
	if main == null or not main._vr_active:
		return
	# Phase 4: Quest controller input handling
