extends Node3D
class_name BuildRadius

const Human = preload("res://source/match/players/human/Human.gd")

@export var cell_size := 1.0

# Option A: Set a radius (in cells) to auto-generate a build area.
# If > 0, this overrides allowed_cells with all cells within this radius.
@export var radius_in_cells := 0

# If true, generates a square shape; if false, generates a circular shape
@export var use_square_shape := false

# Option B: Manually define which grid cells are buildable (used when radius_in_cells == 0)
@export var allowed_cells: Array[Vector2i] = []

@onready var mesh_instance: MeshInstance3D = $GridOverlayMesh

func _ready():
	cell_size = FeatureFlags.grid_cell_size
	if radius_in_cells > 0:
		if use_square_shape:
			allowed_cells = _generate_square_cells(radius_in_cells)
		else:
			allowed_cells = _generate_circular_cells(radius_in_cells)
	# Grab the material from the original PlaneMesh and duplicate it so each
	# BuildRadius instance has its own copy (avoids shared sub-resource issues)
	var original_mat: Material = null
	if mesh_instance.mesh and mesh_instance.mesh.get_surface_count() > 0:
		original_mat = mesh_instance.mesh.surface_get_material(0)
	if original_mat == null:
		original_mat = mesh_instance.material_override
	if original_mat:
		original_mat = original_mat.duplicate()
	mesh_instance.mesh = _build_mesh(original_mat)
	# Sync shader cell_size from FeatureFlags
	var mat = original_mat as ShaderMaterial
	if mat:
		mat.set_shader_parameter("cell_size", cell_size)
	# Detach from parent's rotation so the grid stays axis-aligned
	top_level = true
	global_position = get_parent().global_position
	# Hidden by default — shown when placement mode is active
	visible = false
	add_to_group("build_radii")
	MatchSignals.structure_placement_started.connect(_on_placement_started)
	MatchSignals.structure_placement_ended.connect(_on_placement_ended)


func _on_placement_started():
	# Only show for own/allied structures
	var unit = get_parent()
	if unit == null or not is_instance_valid(unit):
		return
	var player = unit.player if "player" in unit else null
	if player == null:
		return
	# Find the human player to compare ownership/alliance
	var human_players = get_tree().get_nodes_in_group("players").filter(
		func(p): return p is Human
	)
	if human_players.is_empty():
		return
	var human_player = human_players[0]
	var is_own = (player == human_player)
	var is_allied = (player != human_player and player.team == human_player.team)
	if is_own or (is_allied and FeatureFlags.allow_placement_in_allied_build_radius):
		visible = true


func _on_placement_ended():
	visible = false


func _build_mesh(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for cell in allowed_cells:
		_add_cell_quad(st, cell)

	st.generate_normals()
	var mesh = st.commit()
	if mat:
		mesh.surface_set_material(0, mat)
	return mesh


func _add_cell_quad(st: SurfaceTool, cell: Vector2i):
	var half = cell_size * 0.5
	var line_pad = cell_size * 0.05 * 0.5  # half of line_width (matching shader default)

	var cx = cell.x * cell_size
	var cz = cell.y * cell_size

	# Expand outer edges so boundary lines render at full width
	var x_min = cx - half - (line_pad if not allowed_cells.has(Vector2i(cell.x - 1, cell.y)) else 0.0)
	var x_max = cx + half + (line_pad if not allowed_cells.has(Vector2i(cell.x + 1, cell.y)) else 0.0)
	var z_min = cz - half - (line_pad if not allowed_cells.has(Vector2i(cell.x, cell.y - 1)) else 0.0)
	var z_max = cz + half + (line_pad if not allowed_cells.has(Vector2i(cell.x, cell.y + 1)) else 0.0)

	var a = Vector3(x_min, 0.005, z_min)
	var b = Vector3(x_max, 0.005, z_min)
	var c = Vector3(x_max, 0.005, z_max)
	var d = Vector3(x_min, 0.005, z_max)

	# UVs for proper texture/shader sampling
	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(b)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(c)

	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(c)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(d)


func _generate_circular_cells(radius: int) -> Array[Vector2i]:
	# First pass: collect all cells within the radius
	var candidate_cells: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			if Vector2(x, y).length() <= radius:
				candidate_cells.append(Vector2i(x, y))
	# Second pass: remove cells that have fewer than 2 cardinal neighbors
	# This eliminates single protruding cells on the edges
	var cells: Array[Vector2i] = []
	for cell in candidate_cells:
		var neighbor_count := 0
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if candidate_cells.has(cell + dir):
				neighbor_count += 1
		if neighbor_count >= 2:
			cells.append(cell)
	return cells


func _generate_square_cells(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			cells.append(Vector2i(x, y))
	return cells


## Returns the grid cell coordinate for a world position
func _world_to_cell(world_pos: Vector3) -> Vector2i:
	var local_pos = world_pos - global_position
	return Vector2i(
		roundi(local_pos.x / cell_size),
		roundi(local_pos.z / cell_size)
	)


## Checks if a world position falls within this BuildRadius's allowed cells
func is_position_in_radius(world_pos: Vector3) -> bool:
	var cell = _world_to_cell(world_pos)
	return cell in allowed_cells


## Static helper: checks if a world position is within any owned/allied build radius.
## Pass the player who is placing the structure.
static func is_position_in_any_build_radius(tree: SceneTree, world_pos: Vector3, placing_player) -> bool:
	var build_radii = tree.get_nodes_in_group("build_radii")
	for br: BuildRadius in build_radii:
		var unit = br.get_parent()
		if unit == null or not is_instance_valid(unit):
			continue
		var owner_player = unit.player if "player" in unit else null
		if owner_player == null:
			continue
		var is_own = (owner_player == placing_player)
		var is_allied = (owner_player != placing_player and owner_player.team == placing_player.team)
		if is_own or (is_allied and FeatureFlags.allow_placement_in_allied_build_radius):
			if br.is_position_in_radius(world_pos):
				return true
	return false
