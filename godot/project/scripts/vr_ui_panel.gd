extends Node3D

const PANEL_W_M := 0.6
const PANEL_H_M := 0.8
const VP_W      := 600
const VP_H      := 800

var _viewport  : SubViewport
var _mesh_inst : MeshInstance3D

func _ready() -> void:
	_setup_viewport()
	_setup_mesh()
	_setup_collision()

func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(VP_W, VP_H)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var panel: Control = load("res://scenes/analysis_panel.tscn").instantiate()
	_viewport.add_child(panel)
	# Override desktop right-side anchor so panel fills the full SubViewport.
	# Without this, the panel occupies only x=[310,600] while the quad maps
	# UV across the full 600px — causing clicks to land on the wrong element.
	panel.set_anchor_and_offset(SIDE_LEFT,   0.0, 0.0)
	panel.set_anchor_and_offset(SIDE_RIGHT,  1.0, 0.0)
	panel.set_anchor_and_offset(SIDE_TOP,    0.0, 0.0)
	panel.set_anchor_and_offset(SIDE_BOTTOM, 1.0, 0.0)

func _setup_mesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(PANEL_W_M, PANEL_H_M)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.flags_do_not_receive_shadows = true

	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = quad
	_mesh_inst.material_override = mat
	add_child(_mesh_inst)

func _setup_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 4   # layer 3 — detected by VR ray cast (mask=4)
	body.collision_mask  = 0
	add_child(body)

	var shape := CollisionShape3D.new()
	var box   := BoxShape3D.new()
	box.size  = Vector3(PANEL_W_M, PANEL_H_M, 0.01)
	shape.shape = box
	body.add_child(shape)

# Called by vr_controller.gd when the laser pointer selects this panel.
func on_ray_select(world_pos: Vector3) -> void:
	var local_pos := to_local(world_pos)
	var u := clampf(local_pos.x / PANEL_W_M + 0.5, 0.0, 1.0)
	var v := clampf(0.5 - local_pos.y / PANEL_H_M, 0.0, 1.0)
	var pixel := Vector2(u * VP_W, v * VP_H)
	# Hover first — without this, Button ignores press if cursor wasn't on it
	var hover := InputEventMouseMotion.new()
	hover.position = pixel
	_viewport.push_input(hover, true)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pixel
	_viewport.push_input(press, true)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = pixel
	_viewport.push_input(release, true)

	# Move cursor away so no button stays in hover/pressed visual state
	var move_away := InputEventMouseMotion.new()
	move_away.position = Vector2(-10.0, -10.0)
	_viewport.push_input(move_away, true)
