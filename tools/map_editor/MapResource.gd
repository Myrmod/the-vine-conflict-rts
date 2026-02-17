class_name MapResource

extends Resource

## Map data format for the editor
## This stores all editable map data including terrain, collision, and entity placements

@export var size: Vector2i = Vector2i(50, 50)
@export var terrain_seed: int = 0

# Logical grid data for collision (1 byte per cell: 0=walkable, 1=blocked)
@export var collision_grid: PackedByteArray = PackedByteArray()

# Entity placements
@export var placed_entities: Array[Dictionary] = []
@export var placed_units: Array[Dictionary] = []
@export var resource_nodes: Array[Dictionary] = []

# Cosmetics (decorative tiles, not gameplay-affecting)
@export var cosmetic_tiles: Array[Dictionary] = []

# Metadata
@export var map_name: String = "Untitled Map"
@export var author: String = ""
@export var description: String = ""


func _init():
	# Initialize with default size if needed
	if collision_grid.is_empty():
		_initialize_collision_grid()


func _initialize_collision_grid():
	var grid_size = size.x * size.y
	collision_grid.resize(grid_size)
	collision_grid.fill(0)  # 0 = walkable


func resize_map(new_size: Vector2i):
	"""Resize the map, preserving existing data where possible"""
	var old_size = size
	var new_grid = PackedByteArray()
	new_grid.resize(new_size.x * new_size.y)
	new_grid.fill(0)

	# Copy old data to new grid
	for y in range(min(old_size.y, new_size.y)):
		for x in range(min(old_size.x, new_size.x)):
			var old_index = y * old_size.x + x
			var new_index = y * new_size.x + x
			new_grid[new_index] = collision_grid[old_index]

	size = new_size
	collision_grid = new_grid

	# Remove placements outside new bounds
	_remove_out_of_bounds_placements()


func _remove_out_of_bounds_placements():
	placed_entities = placed_entities.filter(func(e): return _is_in_bounds(e.pos))
	placed_units = placed_units.filter(func(u): return _is_in_bounds(u.pos))
	resource_nodes = resource_nodes.filter(func(r): return _is_in_bounds(r.pos))
	cosmetic_tiles = cosmetic_tiles.filter(func(c): return _is_in_bounds(c.pos))


func _is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < size.x and pos.y >= 0 and pos.y < size.y


func get_collision_at(pos: Vector2i) -> int:
	"""Get collision value at grid position. Returns 0=walkable, 1=blocked, -1=out of bounds"""
	if not _is_in_bounds(pos):
		return -1
	var index = pos.y * size.x + pos.x
	return collision_grid[index]


func set_collision_at(pos: Vector2i, value: int):
	"""Set collision value at grid position"""
	if not _is_in_bounds(pos):
		return
	var index = pos.y * size.x + pos.x
	collision_grid[index] = value


func add_entity(scene_path: String, grid_pos: Vector2i, player_id: int, rotation: float = 0.0):
	"""Add an entity placement"""
	placed_entities.append(
		{"scene_path": scene_path, "pos": grid_pos, "player": player_id, "rotation": rotation}
	)


func add_unit(scene_path: String, grid_pos: Vector2i, player_id: int, rotation: float = 0.0):
	"""Add a unit placement"""
	placed_units.append(
		{"scene_path": scene_path, "pos": grid_pos, "player": player_id, "rotation": rotation}
	)


func add_resource_node(
	scene_path: String, grid_pos: Vector2i, resource_type: String = "resource_a"
):
	"""Add a resource node placement"""
	resource_nodes.append(
		{"scene_path": scene_path, "pos": grid_pos, "resource_type": resource_type}
	)


func clear_all():
	"""Clear all map data"""
	_initialize_collision_grid()
	placed_entities.clear()
	placed_units.clear()
	resource_nodes.clear()
	cosmetic_tiles.clear()


func validate() -> Array[String]:
	"""Validate map data and return list of errors"""
	var errors: Array[String] = []

	if size.x < 10 or size.y < 10:
		errors.append("Map size is too small (minimum 10x10)")

	if size.x > 200 or size.y > 200:
		errors.append("Map size is too large (maximum 200x200)")

	# Check for placements outside bounds
	for entity in placed_entities:
		if not _is_in_bounds(entity.pos):
			errors.append("Entity at %s is outside map bounds" % entity.pos)

	for unit in placed_units:
		if not _is_in_bounds(unit.pos):
			errors.append("Unit at %s is outside map bounds" % unit.pos)

	for resource in resource_nodes:
		if not _is_in_bounds(resource.pos):
			errors.append("Resource at %s is outside map bounds" % resource.pos)

	return errors
