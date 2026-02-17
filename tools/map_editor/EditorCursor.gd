class_name EditorCursor

extends Node3D

## Visual cursor for showing brush position and affected cells

var grid_size: Vector2i = Vector2i(50, 50)
var cursor_color: Color = Color.WHITE

var _cursor_mesh_instance: MeshInstance3D
var _affected_cells_mesh: MultiMeshInstance3D


func _ready():
	_setup_cursor()


func _setup_cursor():
	"""Create the cursor visualization"""
	# Main cursor cell
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(
		FeatureFlags.grid_cell_size * 0.9, 0.3, FeatureFlags.grid_cell_size * 0.9
	)

	var material = StandardMaterial3D.new()
	material.albedo_color = cursor_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	box_mesh.material = material

	_cursor_mesh_instance = MeshInstance3D.new()
	_cursor_mesh_instance.mesh = box_mesh
	add_child(_cursor_mesh_instance)

	# Setup multimesh for affected cells (symmetry preview)
	_setup_affected_cells_multimesh()


func _setup_affected_cells_multimesh():
	"""Setup multimesh for showing symmetry-affected cells"""
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(
		FeatureFlags.grid_cell_size * 0.8, 0.2, FeatureFlags.grid_cell_size * 0.8
	)

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(cursor_color.r, cursor_color.g, cursor_color.b, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box_mesh.material = material

	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box_mesh
	multimesh.instance_count = 0  # Will be set when showing affected cells

	_affected_cells_mesh = MultiMeshInstance3D.new()
	_affected_cells_mesh.multimesh = multimesh
	add_child(_affected_cells_mesh)


func set_cursor_position(grid_pos: Vector2i):
	"""Move cursor to grid position"""
	if _cursor_mesh_instance:
		_cursor_mesh_instance.position = Vector3(
			grid_pos.x * FeatureFlags.grid_cell_size + FeatureFlags.grid_cell_size / 2.0,
			0.15,
			grid_pos.y * FeatureFlags.grid_cell_size + FeatureFlags.grid_cell_size / 2.0
		)


func set_affected_cells(positions: Array[Vector2i]):
	"""Show all cells that will be affected (for symmetry preview)"""
	if not _affected_cells_mesh:
		return

	var multimesh = _affected_cells_mesh.multimesh
	multimesh.instance_count = positions.size()

	for i in range(positions.size()):
		var pos = positions[i]
		var transform = Transform3D()
		transform.origin = Vector3(
			pos.x * FeatureFlags.grid_cell_size + FeatureFlags.grid_cell_size / 2.0,
			0.1,
			pos.y * FeatureFlags.grid_cell_size + FeatureFlags.grid_cell_size / 2.0
		)
		multimesh.set_instance_transform(i, transform)


func set_cursor_color(color: Color):
	"""Update cursor color"""
	cursor_color = color
	if _cursor_mesh_instance and _cursor_mesh_instance.mesh:
		_cursor_mesh_instance.mesh.material.albedo_color = color
	if _affected_cells_mesh and _affected_cells_mesh.multimesh.mesh:
		_affected_cells_mesh.multimesh.mesh.material.albedo_color = Color(
			color.r, color.g, color.b, 0.3
		)


func set_visible_cursor(is_visible: bool):
	"""Show or hide the cursor"""
	if _cursor_mesh_instance:
		_cursor_mesh_instance.visible = is_visible
	if _affected_cells_mesh:
		_affected_cells_mesh.visible = is_visible
