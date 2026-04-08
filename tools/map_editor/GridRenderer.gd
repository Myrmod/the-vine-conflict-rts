class_name GridRenderer

extends Node3D

## Renders a grid visualization using MultiMeshInstance3D
## Used to show the map grid in the editor

var grid_size: Vector2i = Vector2i(50, 50)
var grid_color: Color = Color(1, 1, 1, 0.2)

var _multimesh_instance: MultiMeshInstance3D
var _cell_mesh: PlaneMesh


func _ready():
	_setup_multimesh()


func _setup_multimesh():
	"""Create and configure the multimesh for grid rendering"""
	# Create the cell mesh (flat square)
	_cell_mesh = PlaneMesh.new()
	_cell_mesh.size = Vector2(
		FeatureFlags.grid_cell_size * 0.95, FeatureFlags.grid_cell_size * 0.95
	)  # Slightly smaller for gaps

	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = grid_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cell_mesh.material = material

	# Create multimesh
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _cell_mesh
	multimesh.instance_count = grid_size.x * grid_size.y

	# Position each grid cell
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var index = y * grid_size.x + x
			var _transform = Transform3D()
			_transform.origin = Vector3(
				x * FeatureFlags.grid_cell_size + FeatureFlags.grid_cell_size / 2.0,
				0.01,
				y * FeatureFlags.grid_cell_size + FeatureFlags.grid_cell_size / 2.0
			)
			multimesh.set_instance_transform(index, _transform)

	# Create and add the multimesh instance
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = multimesh
	add_child(_multimesh_instance)


func set_grid_size(size: Vector2i):
	"""Update the grid size"""
	grid_size = size
	if _multimesh_instance:
		_multimesh_instance.queue_free()
	_setup_multimesh()


func set_grid_color(color: Color):
	"""Update the grid color"""
	grid_color = color
	if _cell_mesh and _cell_mesh.material:
		_cell_mesh.material.albedo_color = color


func set_visible_range(_min_pos: Vector2i, _max_pos: Vector2i):
	"""Show only a specific range of grid cells (for large maps)"""
	# For optimization on very large maps
	# This would update which instances are visible
	pass
