class_name GlobalBuildGrid
extends Node3D

## Single authoritative grid overlay for the entire map.
##
## Two display modes, each with its own MeshInstance3D child:
##   1. **Debug grid** (_full_mesh_instance) — every cell colour-coded by terrain
##      type. Toggled via the F2 debug HUD.
##   2. **Build-radius grid** (_radius_mesh_instance) — shows only the cells
##      covered by the union of all active (completed, own/allied) build-radii
##      during structure placement. Automatically shown/hidden when placement
##      starts/ends.
##
## Colour key:
##   Green  = buildable land  (GROUND / HIGH_GROUND)
##   Blue   = water
##   Red    = impassable      (SLOPE / WATER_SLOPE)

const Map = preload("res://source/match/Map.gd")
const GRID_SHADER = preload("res://source/shaders/3d/global_grid_shader.gdshader")
const Human = preload("res://source/match/players/human/Human.gd")

const COLOR_LAND := Color(0.2, 0.85, 0.2)
const COLOR_WATER := Color(0.3, 0.7, 1.0)
const COLOR_BLOCKED := Color(0.9, 0.2, 0.2)

var _map: Node = null
var _full_mesh_instance: MeshInstance3D = null
var _radius_mesh_instance: MeshInstance3D = null


func _ready():
	# The node itself is always visible — children control their own visibility.
	visible = true
	MatchSignals.structure_placement_started.connect(_on_placement_started)
	MatchSignals.structure_placement_ended.connect(_on_placement_ended)


## Call once the Map node is ready (after terrain data is loaded).
func build(map: Node) -> void:
	if _full_mesh_instance:
		_full_mesh_instance.queue_free()
		_full_mesh_instance = null

	_map = map
	if map == null:
		return

	var cell_size: float = FeatureFlags.grid_cell_size
	var sx: int = int(map.size.x)
	var sy: int = int(map.size.y)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for z in range(sy):
		for x in range(sx):
			var cell := Vector2i(x, z)
			var h: float = map.get_height_at_cell(cell) + 0.05
			var color := _effective_color(cell)
			_add_cell_quad(st, float(x) * cell_size, float(z) * cell_size, h, cell_size, color)

	st.generate_normals()
	var mesh := st.commit()

	var mat := ShaderMaterial.new()
	mat.shader = GRID_SHADER
	mat.render_priority = -1
	mat.set_shader_parameter("cell_size", cell_size)
	mesh.surface_set_material(0, mat)

	_full_mesh_instance = MeshInstance3D.new()
	_full_mesh_instance.name = "GlobalGridMesh"
	_full_mesh_instance.mesh = mesh
	_full_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_full_mesh_instance.visible = false  # toggled via F2 debug HUD
	add_child(_full_mesh_instance)


## Toggle the full debug grid (called from F2 debug HUD).
func toggle_debug_grid() -> void:
	if _full_mesh_instance:
		_full_mesh_instance.visible = not _full_mesh_instance.visible


static func color_for_cell_type(ct: int) -> Color:
	match ct:
		Map.CELL_GROUND, Map.CELL_HIGH_GROUND:
			return COLOR_LAND
		Map.CELL_WATER:
			return COLOR_WATER
		_:
			return COLOR_BLOCKED


## Returns the terrain zone for a cell type:
##   0 = land (GROUND / HIGH_GROUND)
##   1 = water
##   2 = impassable (SLOPE / WATER_SLOPE)
static func _terrain_zone(ct: int) -> int:
	match ct:
		Map.CELL_GROUND, Map.CELL_HIGH_GROUND:
			return 0
		Map.CELL_WATER:
			return 1
		_:
			return 2


## Checks if a cell sits at a terrain-zone boundary (e.g. land↔water).
## Boundary cells are impassable because partial tiles can't be built on.
static func _is_boundary_cell(cell: Vector2i, map: Node) -> bool:
	var ct: int = map.get_cell_type_at_cell(cell)
	var zone: int = _terrain_zone(ct)
	# Already impassable — no need to check neighbors
	if zone == 2:
		return false
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor: Vector2i = cell + dir
		var nct: int = map.get_cell_type_at_cell(neighbor)
		var nzone: int = _terrain_zone(nct)
		# Treat out-of-bounds neighbors (returned as CELL_GROUND / zone 0) as same-zone
		if not map._is_cell_in_bounds(neighbor):
			continue
		if nzone != zone and nzone != 2:
			return true
	return false


## Returns the display color for a cell, accounting for boundary detection.
## Cells at terrain-zone boundaries are colored red (impassable).
func _effective_color(cell: Vector2i) -> Color:
	var ct: int = _map.get_cell_type_at_cell(cell)
	if _is_boundary_cell(cell, _map):
		return COLOR_BLOCKED
	return color_for_cell_type(ct)


# ── Placement radius display ────────────────────────────────────────


func _on_placement_started() -> void:
	if _map == null:
		return

	var placement_domains: Array = MatchSignals.current_placement_domains

	var human_players = get_tree().get_nodes_in_group("players").filter(func(p): return p is Human)
	if human_players.is_empty():
		return
	var human_player = human_players[0]

	# Collect the union of world-cells from every eligible BuildRadius
	var all_cells: Dictionary = {}  # Vector2i → true (set)
	for br in get_tree().get_nodes_in_group("build_radii"):
		if not br._construction_complete:
			continue
		var unit = br.get_parent()
		if unit == null or not is_instance_valid(unit):
			continue
		var player = unit.player if "player" in unit else null
		if player == null:
			continue
		var is_own: bool = player == human_player
		var is_allied: bool = player != human_player and player.team == human_player.team
		if is_own or (is_allied and FeatureFlags.allow_placement_in_allied_build_radius):
			for wc in br.get_world_cells(placement_domains):
				all_cells[wc] = true

	_build_radius_mesh(all_cells)


func _on_placement_ended() -> void:
	if _radius_mesh_instance:
		_radius_mesh_instance.queue_free()
		_radius_mesh_instance = null


func _build_radius_mesh(cells_dict: Dictionary) -> void:
	if _radius_mesh_instance:
		_radius_mesh_instance.queue_free()
		_radius_mesh_instance = null

	if cells_dict.is_empty():
		return

	var cell_size: float = FeatureFlags.grid_cell_size
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for cell: Vector2i in cells_dict.keys():
		var h: float = _map.get_height_at_cell(cell) + 0.05
		var color := _effective_color(cell)
		_add_radius_cell_quad(st, cell, cells_dict, h, cell_size, color)

	st.generate_normals()
	var mesh := st.commit()

	var mat := ShaderMaterial.new()
	mat.shader = GRID_SHADER
	mat.render_priority = -1
	mat.set_shader_parameter("cell_size", cell_size)
	mat.set_shader_parameter("fill_alpha", 0.18)
	mat.set_shader_parameter("line_alpha", 1.0)
	mesh.surface_set_material(0, mat)

	_radius_mesh_instance = MeshInstance3D.new()
	_radius_mesh_instance.name = "RadiusGridMesh"
	_radius_mesh_instance.mesh = mesh
	_radius_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_radius_mesh_instance)


# ── Geometry helpers ─────────────────────────────────────────────────


## Quad for the full debug grid (no border expansion).
func _add_cell_quad(
	st: SurfaceTool, px: float, pz: float, y: float, cell_size: float, color: Color
) -> void:
	var half := cell_size * 0.5

	var a := Vector3(px - half, y, pz - half)
	var b := Vector3(px + half, y, pz - half)
	var c := Vector3(px + half, y, pz + half)
	var d := Vector3(px - half, y, pz + half)

	st.set_color(color)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)
	st.set_color(color)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(b)
	st.set_color(color)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(c)

	st.set_color(color)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)
	st.set_color(color)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(c)
	st.set_color(color)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(d)


## Quad for a build-radius cell — expands outer edges so boundary grid-lines
## render at full width.
func _add_radius_cell_quad(
	st: SurfaceTool, cell: Vector2i, cells_set: Dictionary, y: float, cell_size: float, color: Color
) -> void:
	var half := cell_size * 0.5
	var line_pad := cell_size * 0.05 * 0.5

	var px := float(cell.x) * cell_size
	var pz := float(cell.y) * cell_size

	var x_min := px - half - (line_pad if not cells_set.has(Vector2i(cell.x - 1, cell.y)) else 0.0)
	var x_max := px + half + (line_pad if not cells_set.has(Vector2i(cell.x + 1, cell.y)) else 0.0)
	var z_min := pz - half - (line_pad if not cells_set.has(Vector2i(cell.x, cell.y - 1)) else 0.0)
	var z_max := pz + half + (line_pad if not cells_set.has(Vector2i(cell.x, cell.y + 1)) else 0.0)

	var a := Vector3(x_min, y, z_min)
	var b := Vector3(x_max, y, z_min)
	var c := Vector3(x_max, y, z_max)
	var d := Vector3(x_min, y, z_max)

	st.set_color(color)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)
	st.set_color(color)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(b)
	st.set_color(color)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(c)

	st.set_color(color)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)
	st.set_color(color)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(c)
	st.set_color(color)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(d)
