class_name AssemblyEffect
extends Node3D
## Reusable build/sell visual effect for structures.
## Displays a refraction-glass plane sized to the structure's visual bounds.
## The structure itself stays fully visible at all times.
##
## Call show_effect() to start, hide_effect() to stop.

const REFRACTION_SHADER = preload("res://source/shaders/3d/refraction_glass.gdshader")

var _plane: MeshInstance3D = null
var _shader_mat: ShaderMaterial = null
var _is_setup: bool = false
var _cached_aabb: AABB
var _cached_center_local: Vector3


func _ready() -> void:
	call_deferred("_deferred_setup")


func _deferred_setup() -> void:
	var target := get_parent() as Node3D
	if target == null:
		return

	var aabb := _compute_combined_aabb(target)
	if aabb.size.is_zero_approx():
		return

	_cached_aabb = aabb
	_cached_center_local = aabb.position + aabb.size * 0.5

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = REFRACTION_SHADER
	_shader_mat.render_priority = 1

	# Size the plane to cover the structure (XZ footprint → width, Y → height).
	var plane_width: float = maxf(aabb.size.x, aabb.size.z) * 1.3
	var plane_height: float = aabb.size.y * 1.3

	var quad := QuadMesh.new()
	quad.size = Vector2(plane_width, plane_height)
	# FACE_Z puts normals along +Z; after look_at the node's -Z faces the
	# camera, so we need the mesh to face -Z instead. Flip via orientation.
	quad.orientation = PlaneMesh.FACE_Z
	quad.flip_faces = true

	_plane = MeshInstance3D.new()
	_plane.mesh = quad
	_plane.material_override = _shader_mat
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plane.visible = false

	# Position at centre of the structure AABB, facing the camera.
	# top_level so it stays in world-space even if the parent transforms.
	_plane.top_level = true
	add_child(_plane)

	_is_setup = true

	# Auto-show if already under construction.
	if target.has_method("is_under_construction") and target.is_under_construction():
		show_effect()


func _process(_delta: float) -> void:
	if _plane == null or not _plane.visible:
		return
	_orient_plane_to_camera()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


func show_effect() -> void:
	if not _is_setup:
		return
	_orient_plane_to_camera()
	_plane.visible = true


func hide_effect() -> void:
	if _plane != null:
		_plane.visible = false


func clear() -> void:
	hide_effect()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------


func _orient_plane_to_camera() -> void:
	var target := get_parent() as Node3D
	if target == null:
		return

	var center: Vector3 = target.global_transform * _cached_center_local

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	# Offset the plane toward the camera so it sits in front of the structure.
	var to_cam := (cam.global_position - center).normalized()
	var half_depth := maxf(_cached_aabb.size.x, _cached_aabb.size.z) * 0.5
	var plane_pos := center + to_cam * (half_depth + 0.2)

	_plane.global_position = plane_pos
	_plane.look_at(cam.global_position, Vector3.UP)


func _compute_combined_aabb(target: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var meshes: Array[MeshInstance3D] = []
	if target is MeshInstance3D:
		meshes.append(target)
	for child in target.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child as MeshInstance3D)
	for m in meshes:
		var local_aabb := m.get_aabb()
		# Transform mesh AABB corners into the target's local space.
		var rel_xform := target.global_transform.inverse() * m.global_transform
		var transformed := AABB(rel_xform * local_aabb.position, Vector3.ZERO)
		for xi in range(2):
			for yi in range(2):
				for zi in range(2):
					var corner := (
						local_aabb.position
						+ Vector3(
							local_aabb.size.x * xi, local_aabb.size.y * yi, local_aabb.size.z * zi
						)
					)
					transformed = transformed.expand(rel_xform * corner)
		if first:
			result = transformed
			first = false
		else:
			result = result.merge(transformed)
	return result
