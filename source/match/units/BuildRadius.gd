class_name BuildRadius

extends Node3D

## Data-only build-radius node.
##
## Defines which cells around a structure are part of the build area (land and
## water radii).  It does NOT render anything — the GlobalBuildGrid is the
## single grid implementation and draws the radius portion during placement.
##
## Responsibilities:
##   - Calculate land / water cell sets at _ready().
##   - Provide get_world_cells() so GlobalBuildGrid can collect them.
##   - Provide is_position_in_radius() for placement-gating checks.
##   - Track whether parent structure has finished construction.

const Structure = preload("res://source/match/units/Structure.gd")

## Multiplier applied to radius_in_cells for the water build radius.
## Every structure emits both a land and a water build radius; the water one is larger.
const WATER_RADIUS_MULTIPLIER := 2

@export var cell_size := 1.0

# Option A: Set a radius (in cells) to auto-generate a build area.
# If > 0, this overrides allowed_cells with all cells within this radius.
@export var radius_in_cells := 0

# If true, generates a square shape; if false, generates a circular shape
@export var use_square_shape := false

# Option B: Manually define which grid cells are buildable (used when radius_in_cells == 0)
@export var allowed_cells: Array[Vector2i] = []

## Whether the parent structure has finished construction.
## Build radii are only active (visible + counted) after construction completes.
var _construction_complete := true

# Internal cell sets (offsets relative to parent's cell)
var _land_cells: Array[Vector2i] = []
var _water_cells: Array[Vector2i] = []


func _ready():
	cell_size = FeatureFlags.grid_cell_size
	if radius_in_cells > 0:
		var land_radius = radius_in_cells
		var water_radius = radius_in_cells * WATER_RADIUS_MULTIPLIER
		if use_square_shape:
			_land_cells = _generate_square_cells(land_radius)
			_water_cells = _generate_square_cells(water_radius)
		else:
			_land_cells = _generate_circular_cells(land_radius)
			_water_cells = _generate_circular_cells(water_radius)
	# Keep allowed_cells as the land set for backward compatibility
	allowed_cells = _land_cells

	# Remove the legacy template PlaneMesh child if present
	var template_mesh = get_node_or_null("GridOverlayMesh")
	if template_mesh:
		template_mesh.queue_free()

	# Check if the parent is a structure that's still under construction
	var unit = get_parent()
	if unit is Structure and unit.is_under_construction():
		_construction_complete = false
		unit.constructed.connect(_on_structure_constructed)
	else:
		_construction_complete = true

	add_to_group("build_radii")


func _on_structure_constructed():
	_construction_complete = true


## Returns world-space cell coordinates covered by this build radius.
## GlobalBuildGrid calls this during placement to collect all cells to display.
## When placement_domains includes WATER, water cells (expanded radius) are included.
## When it includes LAND, land cells (normal radius) are included.
## Both sets are merged when the structure supports both domains.
func get_world_cells(placement_domains: Array) -> Array[Vector2i]:
	var parent_pos: Vector3 = get_parent().global_position
	var origin := Vector2i(int(floor(parent_pos.x)), int(floor(parent_pos.z)))

	var cells: Array[Vector2i]
	var has_water: bool = Enums.PlacementTypes.WATER in placement_domains
	var has_land: bool = Enums.PlacementTypes.LAND in placement_domains
	if has_water and not has_land:
		cells = _water_cells
	elif has_water and has_land:
		# Merge both sets; water_cells is a superset of land_cells so just use it
		cells = _water_cells
	else:
		cells = _land_cells

	var world_cells: Array[Vector2i] = []
	for cell in cells:
		world_cells.append(Vector2i(origin.x + cell.x, origin.y + cell.y))
	return world_cells


## Checks if a world position falls within this BuildRadius's cells for the given domain.
func is_position_in_radius(
	world_pos: Vector3, domain: Enums.PlacementTypes = Enums.PlacementTypes.LAND
) -> bool:
	var parent_pos: Vector3 = get_parent().global_position
	var local_pos := world_pos - parent_pos
	var cell := Vector2i(int(floor(local_pos.x / cell_size)), int(floor(local_pos.z / cell_size)))
	if domain == Enums.PlacementTypes.WATER:
		return cell in _water_cells
	return cell in _land_cells


## Static helper: checks if a world position is within any owned/allied build radius.
## Pass the player who is placing the structure and the placement domain to check.
static func is_position_in_any_build_radius(
	tree: SceneTree,
	world_pos: Vector3,
	placing_player,
	domain: Enums.PlacementTypes = Enums.PlacementTypes.LAND,
) -> bool:
	var build_radii = tree.get_nodes_in_group("build_radii")
	for br: BuildRadius in build_radii:
		if not br._construction_complete:
			continue
		var unit = br.get_parent()
		if unit == null or not is_instance_valid(unit):
			continue
		var owner_player = unit.player if "player" in unit else null
		if owner_player == null:
			continue
		var is_own = owner_player == placing_player
		var is_allied = owner_player != placing_player and owner_player.team == placing_player.team
		if is_own or (is_allied and FeatureFlags.allow_placement_in_allied_build_radius):
			if br.is_position_in_radius(world_pos, domain):
				return true
	return false


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
