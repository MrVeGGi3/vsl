extends Node3D

var _vr_active := false

func _ready() -> void:
	_vr_active = _try_init_openxr()
	if not _vr_active:
		_setup_desktop_camera()

func _try_init_openxr() -> bool:
	var xr = XRServer.find_interface("OpenXR")
	if xr == null or not xr.initialize():
		return false
	get_viewport().use_xr = true
	get_viewport().scaling_3d_scale = 1.0
	$Camera3D.current = false
	return true

func _setup_desktop_camera() -> void:
	$Camera3D.position = Vector3(0.0, 2.0, 20.0)
	$Camera3D.look_at(Vector3.ZERO, Vector3.UP)
