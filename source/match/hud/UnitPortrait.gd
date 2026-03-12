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
	var r: float = BASE_RADIUS
	if "radius" in unit and unit.radius != null:
		r = unit.radius
	_size_scale = maxf(r / BASE_RADIUS, 0.01)
	_local_camera.size = BASE_SIZE * _size_scale
	_update_camera()


func clear() -> void:
	_portrait_unit = null


func _update_camera() -> void:
	if not _portrait_unit or not is_instance_valid(_portrait_unit):
		return
	var pos := _portrait_unit.global_position
	var dir := CAM_OFFSET.normalized()
	var cam_pos := pos + dir * BASE_DIST * _size_scale
	var look_target := pos + Vector3(0, 0.15 * _size_scale, 0)
	if cam_pos.is_equal_approx(look_target):
		return
	_local_camera.global_position = cam_pos
	_local_camera.look_at(look_target)


func _process(_delta: float) -> void:
	_update_camera()
