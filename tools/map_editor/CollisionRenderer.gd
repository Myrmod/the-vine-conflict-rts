class_name CollisionRenderer

extends Node3D

## Renders collision visualization using merged shapes from CollisionShapeBuilder.
## Shows height blocks, cliff walls, tilted slopes, and manual collision
## with distinct colours per group.

# Colours keyed by collision group
const GROUP_COLORS := {
	CollisionShapeBuilder.GROUP_GROUND: Color(0.3, 0.7, 0.3, 0.25),
	CollisionShapeBuilder.GROUP_HIGH_GROUND: Color(0.7, 0.5, 0.2, 0.5),
	CollisionShapeBuilder.GROUP_WATER: Color(0.2, 0.4, 0.9, 0.5),
	CollisionShapeBuilder.GROUP_CLIFF: Color(0.9, 0.2, 0.2, 0.6),
	CollisionShapeBuilder.GROUP_SLOPE: Color(0.9, 0.7, 0.2, 0.5),
	CollisionShapeBuilder.GROUP_WATER_SLOPE: Color(0.2, 0.8, 0.8, 0.5),
	CollisionShapeBuilder.GROUP_MANUAL: Color(0.8, 0.2, 0.2, 0.5),
}

var map_resource: MapResource
var grid_size: Vector2i = Vector2i(50, 50)

# Keep references so we can free them on rebuild
var _shape_nodes: Array[Node3D] = []

# Cache materials per group to reduce allocations
var _material_cache: Dictionary = {}


func _init(map_res: MapResource = null) -> void:
	map_resource = map_res
	if map_res:
		grid_size = map_res.size


func _ready() -> void:
	if map_resource:
		refresh()


func set_map_resource(map_res: MapResource) -> void:
	"""Set the map resource and refresh visualization"""
	map_resource = map_res
	grid_size = map_res.size
	refresh()


func refresh() -> void:
	"""Rebuild the collision visualization from the merged shape data."""
	_clear_shapes()

	if not map_resource:
		return

	var shapes: Array[Dictionary] = CollisionShapeBuilder.build_all(map_resource)
	for shape: Dictionary in shapes:
		_create_shape_visual(shape)


func _clear_shapes() -> void:
	for node: Node3D in _shape_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_shape_nodes.clear()


func _create_shape_visual(shape: Dictionary) -> void:
	match shape.type:
		CollisionShapeBuilder.SHAPE_BOX:
			_create_box_visual(shape)
		CollisionShapeBuilder.SHAPE_WALL:
			_create_wall_visual(shape)
		CollisionShapeBuilder.SHAPE_SLOPE:
			_create_slope_visual(shape)


# ------------------------------------------------------------------
# Box (height blocks & manual collision)
# ------------------------------------------------------------------
func _create_box_visual(shape: Dictionary) -> void:
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = shape.size
	mesh_inst.mesh = box
	mesh_inst.position = shape.position
	mesh_inst.material_override = _get_material(shape.group)
	add_child(mesh_inst)
	_shape_nodes.append(mesh_inst)


# ------------------------------------------------------------------
# Wall (cliff edges)
# ------------------------------------------------------------------
func _create_wall_visual(shape: Dictionary) -> void:
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = shape.size
	mesh_inst.mesh = box
	mesh_inst.position = shape.position
	mesh_inst.material_override = _get_material(shape.group)
	add_child(mesh_inst)
	_shape_nodes.append(mesh_inst)


# ------------------------------------------------------------------
# Slope (tilted collision surface)
# ------------------------------------------------------------------
func _create_slope_visual(shape: Dictionary):
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(shape.size.x, 0.08, shape.size.z)
	mesh_inst.mesh = box
	mesh_inst.position = shape.position

	var dir: Vector2i = shape.get("direction", Vector2i(1, 0))
	var angle_rad: float = deg_to_rad(shape.get("angle_deg", 60.0))

	# Rotate the thin box so the surface is tilted at the configured angle
	# from horizontal, going upward in the slope direction.
	if dir == Vector2i(1, 0):
		mesh_inst.rotation.z = angle_rad
	elif dir == Vector2i(-1, 0):
		mesh_inst.rotation.z = -angle_rad
	elif dir == Vector2i(0, 1):
		mesh_inst.rotation.x = -angle_rad
	elif dir == Vector2i(0, -1):
		mesh_inst.rotation.x = angle_rad

	mesh_inst.material_override = _get_material(shape.group)
	add_child(mesh_inst)
	_shape_nodes.append(mesh_inst)


# ------------------------------------------------------------------
# Material helper
# ------------------------------------------------------------------
func _get_material(group: String) -> StandardMaterial3D:
	if _material_cache.has(group):
		return _material_cache[group]

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = GROUP_COLORS.get(group, Color(0.5, 0.5, 0.5, 0.5))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material_cache[group] = mat
	return mat


# ------------------------------------------------------------------
# Compatibility methods (called by MapEditor on per-cell updates)
# ------------------------------------------------------------------
func update_cell(_pos: Vector2i) -> void:
	"""A single cell changed – rebuild all shapes."""
	refresh()


func update_cells(_positions: Array[Vector2i]) -> void:
	"""Multiple cells changed – rebuild all shapes."""
	refresh()
