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
	_size_scale = r / BASE_RADIUS
	_local_camera.size = BASE_SIZE * _size_scale
	_update_camera()


func clear() -> void:
	_portrait_unit = null


func _update_camera() -> void:
	if not _portrait_unit or not is_instance_valid(_portrait_unit):
		return
	var pos := _portrait_unit.global_position
	var dir := CAM_OFFSET.normalized()
	_local_camera.global_position = (pos + dir * BASE_DIST * _size_scale)
	_local_camera.look_at(pos + Vector3(0, 0.15 * _size_scale, 0))


func _process(_delta: float) -> void:
	_update_camera()
