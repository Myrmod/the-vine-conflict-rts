extends SubViewport

const CAM_OFFSET := Vector3(0, 0.6, 1.2)
const BASE_SIZE := 1.8
const BASE_DIST := 2.0
const BASE_RADIUS := 0.9

var _portrait_unit: Node3D = null
var _local_camera: Camera3D = null
var _size_scale: float = 1.0


func _ready():
	_local_camera = Camera3D.new()
	_local_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_local_camera.size = BASE_SIZE
	_local_camera.current = true
	add_child(_local_camera)


func show_unit(unit: Node3D) -> void:
	_portrait_unit = unit
	world_3d = unit.get_world_3d()
	var settings = unit.find_child("PortraitSettings", false, false)
	if settings and settings.camera_size > 0.0:
		_size_scale = settings.camera_size / BASE_SIZE
	else:
		var visual_size := _estimate_visual_size(unit)
		_size_scale = maxf(visual_size / BASE_RADIUS, 0.01)
	_local_camera.size = BASE_SIZE * _size_scale
	_update_camera()


func _estimate_visual_size(unit: Node3D) -> float:
	for child in unit.get_children():
		if child is ModelHolder:
			var aabb := _get_recursive_aabb(child)
			var extent := aabb.size
			return maxf(maxf(extent.x, extent.y), extent.z) * 0.5
	# Fallback to navigation radius
	if "radius" in unit and unit.radius != null:
		return unit.radius
	return BASE_RADIUS


func _get_recursive_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in node.get_children():
		if child is VisualInstance3D:
			var child_aabb: AABB = child.global_transform * child.get_aabb()
			if first:
				result = child_aabb
				first = false
			else:
				result = result.merge(child_aabb)
		if child is Node3D:
			var sub := _get_recursive_aabb(child)
			if sub.size != Vector3.ZERO:
				if first:
					result = sub
					first = false
				else:
					result = result.merge(sub)
	return result


func clear() -> void:
	_portrait_unit = null


func _update_camera() -> void:
	if not _portrait_unit or not is_instance_valid(_portrait_unit):
		return
	var pos := _portrait_unit.global_position
	var dir := CAM_OFFSET.normalized()
	var dist_mult := 1.0
	var height_offset := 0.15
	var settings = _portrait_unit.find_child("PortraitSettings", false, false)
	if settings:
		dist_mult = settings.camera_distance
		height_offset = settings.camera_height
	var cam_pos := pos + dir * BASE_DIST * _size_scale * dist_mult
	var look_target := pos + Vector3(0, height_offset * _size_scale, 0)
	if cam_pos.is_equal_approx(look_target):
		return
	_local_camera.global_position = cam_pos
	_local_camera.look_at(look_target)


func _process(_delta: float) -> void:
	_update_camera()
