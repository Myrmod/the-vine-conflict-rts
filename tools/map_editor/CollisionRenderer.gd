class_name CollisionRenderer

extends Node3D

## Renders collision visualization using MultiMeshInstance3D
## Shows blocked/walkable cells with different colors

# Colors for different collision states
const COLOR_WALKABLE = Color(0.2, 0.8, 0.2, 0.5)  # Green
const COLOR_BLOCKED = Color(0.8, 0.2, 0.2, 0.5)  # Red

var map_resource: MapResource
var grid_size: Vector2i = Vector2i(50, 50)

var _multimesh_instance: MultiMeshInstance3D
var _cell_mesh: BoxMesh


func _init(map_res: MapResource = null):
	map_resource = map_res
	if map_res:
		grid_size = map_res.size


func _ready():
	if map_resource:
		refresh()


func set_map_resource(map_res: MapResource):
	"""Set the map resource and refresh visualization"""
	map_resource = map_res
	grid_size = map_res.size
	refresh()


func refresh():
	"""Rebuild the collision visualization from map data"""
	if _multimesh_instance:
		_multimesh_instance.queue_free()
		_multimesh_instance = null

	if not map_resource:
		return

	_setup_multimesh()


func _setup_multimesh():
	"""Create and configure the multimesh for collision rendering"""
	# Create the cell mesh (small box)
	_cell_mesh = BoxMesh.new()
	_cell_mesh.size = Vector3(
		FeatureFlags.grid_cell_size * 0.9, 0.2, FeatureFlags.grid_cell_size * 0.9
	)

	# Create multimesh
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _cell_mesh
	multimesh.instance_count = grid_size.x * grid_size.y

	# Set up each cell based on collision data
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var index = y * grid_size.x + x
			var pos = Vector2i(x, y)
			var collision_value = map_resource.get_collision_at(pos)

			# Position
			var transform = Transform3D()
			transform.origin = Vector3(
				x * FeatureFlags.grid_cell_size + FeatureFlags.grid_cell_size / 2.0,
				0.1,
				y * FeatureFlags.grid_cell_size + FeatureFlags.grid_cell_size / 2.0
			)
			multimesh.set_instance_transform(index, transform)

			# Color based on collision state
			var color = COLOR_WALKABLE if collision_value == 0 else COLOR_BLOCKED
			multimesh.set_instance_color(index, color)

	# Create material
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	_cell_mesh.material = material

	# Create and add the multimesh instance
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = multimesh
	add_child(_multimesh_instance)


func update_cell(pos: Vector2i):
	"""Update a single cell's visualization"""
	if not _multimesh_instance or not map_resource:
		return

	var index = pos.y * grid_size.x + pos.x
	var collision_value = map_resource.get_collision_at(pos)
	var color = COLOR_WALKABLE if collision_value == 0 else COLOR_BLOCKED

	_multimesh_instance.multimesh.set_instance_color(index, color)


func update_cells(positions: Array[Vector2i]):
	"""Update multiple cells' visualization"""
	for pos in positions:
		update_cell(pos)
