extends Node3D

const GS_BRASILIA_LAT := -15.78
const GS_BRASILIA_LON := -47.93

# XROrigin3D offset so the user "stands" at the same vantage as the desktop camera.
const VR_ORIGIN_POS := Vector3(0.0, 0.0, 20.0)
# World-space position of the VR UI panel (right side, arm's reach).
const VR_PANEL_POS  := Vector3(0.35, 1.5, 19.0)

var _vr_active  := false
var _vr_aligned := false

func _unhandled_key_input(event: InputEvent) -> void:
	if not _vr_active and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			$UILayer.visible = not $UILayer.visible

func _process(_delta: float) -> void:
	if _vr_active and not _vr_aligned:
		_try_align_xr_to_earth()

func _try_align_xr_to_earth() -> void:
	var cam := get_node_or_null("XROrigin3D/XRCamera3D")
	if cam == null or cam.transform == Transform3D.IDENTITY:
		return
	var cam_fwd: Vector3 = -cam.global_transform.basis.z
	cam_fwd.y = 0.0
	if cam_fwd.length_squared() < 0.001:
		return
	var to_earth: Vector3 = (Vector3.ZERO - $XROrigin3D.global_position).normalized()
	to_earth.y = 0.0
	if to_earth.length_squared() < 0.001:
		return
	$XROrigin3D.rotation.y += cam_fwd.normalized().signed_angle_to(
		to_earth.normalized(), Vector3.UP)
	_vr_aligned = true

func _ready() -> void:
	_vr_active = _try_init_openxr()
	if not _vr_active:
		_setup_desktop_camera()
		_hide_vr_panel()
	else:
		_attach_ui_to_world()
		_init_vr_controllers()
	_setup_ground_station()

func _init_vr_controllers() -> void:
	for ctrl in [$XROrigin3D/XRController3DLeft, $XROrigin3D/XRController3DRight]:
		ctrl.init_vr(self)

func _setup_ground_station() -> void:
	var earth := $Earth
	if earth.has_method("set_ground_station"):
		earth.set_ground_station(GS_BRASILIA_LAT, GS_BRASILIA_LON)

func _try_init_openxr() -> bool:
	var xr = XRServer.find_interface("OpenXR")
	if xr == null or not xr.initialize():
		return false
	get_viewport().use_xr = true
	get_viewport().scaling_3d_scale = 1.0  # Quest 3S: 2064×2208/eye, full quality
	$Camera3D.current = false              # XRCamera3D assumes control automatically
	return true

func _setup_desktop_camera() -> void:
	$Camera3D.position = Vector3(0.0, 2.0, 20.0)
	$Camera3D.look_at(Vector3.ZERO, Vector3.UP)

func _hide_vr_panel() -> void:
	var panel := get_node_or_null("VRUIPanel")
	if panel:
		panel.visible = false

func _attach_ui_to_world() -> void:
	# Move the 2D canvas out of VR — CanvasLayer does not composite into XR viewports.
	$UILayer.visible = false

	# Position the XR origin at the same vantage point as the desktop camera.
	$XROrigin3D.position = VR_ORIGIN_POS

	# Show the world-space UI panel (SubViewport quad) at arm's reach.
	var panel := get_node_or_null("VRUIPanel")
	if panel:
		panel.visible = true
		panel.position = VR_PANEL_POS
		panel.rotation_degrees.y = -10.0
