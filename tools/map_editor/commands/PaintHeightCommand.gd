class_name PaintHeightCommand

extends EditorCommand

## Command for painting terrain height levels with undo support.
## Sets cell_type and computes edge-only collision: only cells at the
## boundary between different heights are blocked (cliff edges).

var map_resource: MapResource
var positions: Array[Vector2i]
var new_height: float
var height_level: int  # -1, 0, or 1 (enum value)

# For undo — stores the FULL affected region (painted cells + neighbours)
var _affected_region: Array[Vector2i]
var _old_heights: Array[float]
var _old_collisions: Array[int]
var _old_cell_types: Array[int]


func _init(
	map_res: MapResource,
	affected_positions: Array[Vector2i],
	height: float,
	level: int,
	_auto_collision: bool = true  # kept for API compat, always edge-based now
):
	map_resource = map_res
	positions = affected_positions.duplicate()
	new_height = height
	height_level = level

	# The collision recalc needs the painted cells + their immediate neighbours
	_affected_region = _compute_affected_region(positions)
	_old_heights = []
	_old_collisions = []
	_old_cell_types = []

	# Snapshot the entire affected region for reliable undo
	for pos in _affected_region:
		_old_heights.append(map_res.get_height_at(pos))
		_old_collisions.append(map_res.get_collision_at(pos))
		_old_cell_types.append(map_res.get_cell_type_at(pos))

	description = "Paint Height Level %d (%d cells)" % [level, positions.size()]


func execute():
	# 1. Set heights and cell types on the painted cells
	var cell_type: int
	match height_level:
		-1:
			cell_type = MapResource.CELL_WATER
		0:
			cell_type = MapResource.CELL_GROUND
		1:
			cell_type = MapResource.CELL_HIGH_GROUND
		_:
			cell_type = MapResource.CELL_GROUND

	for pos in positions:
		map_resource.set_height_at(pos, new_height)
		map_resource.set_cell_type_at(pos, cell_type)

	# 2. Recompute edge collision for the full affected region
	_recompute_edge_collision()


func undo():
	for i in range(_affected_region.size()):
		map_resource.set_height_at(_affected_region[i], _old_heights[i])
		map_resource.set_collision_at(_affected_region[i], _old_collisions[i])
		map_resource.set_cell_type_at(_affected_region[i], _old_cell_types[i])


func _recompute_edge_collision():
	"""Set collision=1 on edge cells (height differs from a neighbour) that
	are NOT slopes. Clear collision on non-edge cells (unless they are water)."""
	for pos: Vector2i in _affected_region:
		var ct: int = map_resource.get_cell_type_at(pos)

		# Slopes (regular and water) are always walkable — they are ramps
		if ct == MapResource.CELL_SLOPE or ct == MapResource.CELL_WATER_SLOPE:
			map_resource.set_collision_at(pos, 0)
			continue

		# Water is always blocked
		if ct == MapResource.CELL_WATER:
			map_resource.set_collision_at(pos, 1)
			continue

		# For ground / high-ground: blocked only at height edges
		if map_resource.is_height_edge(pos):
			map_resource.set_collision_at(pos, 1)
		else:
			map_resource.set_collision_at(pos, 0)


func _compute_affected_region(painted: Array[Vector2i]) -> Array[Vector2i]:
	"""Return the painted cells PLUS a 1-cell border so edge collision
	can be recalculated correctly on neighbours."""
	var region_set: Dictionary = {}
	for pos: Vector2i in painted:
		region_set[pos] = true
		for offset: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var n: Vector2i = pos + offset
			if n.x >= 0 and n.x < map_resource.size.x and n.y >= 0 and n.y < map_resource.size.y:
				region_set[n] = true

	var result: Array[Vector2i] = []
	for key in region_set.keys():
		result.append(key)
	return result
