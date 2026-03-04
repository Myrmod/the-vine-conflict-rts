class_name EditorCursor

extends Node3D

## Visual cursor for showing brush position and affected cells

const CIRCLE_SEGMENTS: int = 64
const CIRCLE_Y: float = 0.2

var grid_size: Vector2i = Vector2i(50, 50)
var cursor_color: Color = Color.WHITE

var _cursor_mesh_instance: MeshInstance3D
var _affected_cells_mesh: MultiMeshInstance3D
var _circle_mesh_instance: MeshInstance3D
var _circle_radius: float = 0.5


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

	# Setup circle outline for brush radius
	_setup_circle_outline()


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


func _setup_circle_outline():
	"""Create a circle ring mesh to outline the brush area."""
	var im := ImmediateMesh.new()
	_rebuild_circle(im, _circle_radius)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_receive_shadows = true
	mat.no_depth_test = true

	_circle_mesh_instance = MeshInstance3D.new()
	_circle_mesh_instance.mesh = im
	_circle_mesh_instance.material_override = mat
	add_child(_circle_mesh_instance)


func _rebuild_circle(im: ImmediateMesh, radius: float) -> void:
	"""Build a line-strip circle on the XZ plane."""
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(CIRCLE_SEGMENTS + 1):
		var angle: float = TAU * float(i) / float(CIRCLE_SEGMENTS)
		var px: float = cos(angle) * radius
		var pz: float = sin(angle) * radius
		im.surface_add_vertex(Vector3(px, CIRCLE_Y, pz))
	im.surface_end()


func set_cursor_position(grid_pos: Vector2i):
	"""Move cursor to grid position"""
	var world_pos := Vector3(
		grid_pos.x * FeatureFlags.grid_cell_size + FeatureFlags.grid_cell_size / 2.0,
		0.15,
		grid_pos.y * FeatureFlags.grid_cell_size + FeatureFlags.grid_cell_size / 2.0
	)
	if _cursor_mesh_instance:
		_cursor_mesh_instance.position = world_pos
	if _circle_mesh_instance:
		_circle_mesh_instance.position = Vector3(world_pos.x, 0.0, world_pos.z)


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


func set_brush_radius(cell_radius: int) -> void:
	"""Update the circle outline to match the brush radius in cells."""
	# Radius in world units — half-cell extra to enclose the outer edge of cells
	_circle_radius = (float(cell_radius) + 0.5) * FeatureFlags.grid_cell_size
	if _circle_mesh_instance and _circle_mesh_instance.mesh is ImmediateMesh:
		_rebuild_circle(_circle_mesh_instance.mesh as ImmediateMesh, _circle_radius)


func set_cursor_color(color: Color):
	"""Update cursor color"""
	cursor_color = color
	if _cursor_mesh_instance and _cursor_mesh_instance.mesh:
		_cursor_mesh_instance.mesh.material.albedo_color = color
	if _affected_cells_mesh and _affected_cells_mesh.multimesh.mesh:
		_affected_cells_mesh.multimesh.mesh.material.albedo_color = Color(
			color.r, color.g, color.b, 0.3
		)
	if _circle_mesh_instance and _circle_mesh_instance.material_override:
		_circle_mesh_instance.material_override.albedo_color = Color(color.r, color.g, color.b, 0.8)


func set_visible_cursor(is_visible: bool):
	"""Show or hide the cursor"""
	if _cursor_mesh_instance:
		_cursor_mesh_instance.visible = is_visible
	if _affected_cells_mesh:
		_affected_cells_mesh.visible = is_visible
	if _circle_mesh_instance:
		_circle_mesh_instance.visible = is_visible
