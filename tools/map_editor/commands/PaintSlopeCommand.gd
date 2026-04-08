class_name PaintSlopeCommand

extends EditorCommand

## Command for painting slope cells with undo support.
## Slopes interpolate between adjacent height levels, clear collision
## so units can traverse them, and mark the cell type as SLOPE (or
## WATER_SLOPE) so buildings cannot be placed here.

var map_resource: MapResource
var positions: Array[Vector2i]
var is_water_slope: bool = false

# For undo
var old_heights: Array[float]
var old_collisions: Array[int]
var old_cell_types: Array[int]

# New computed values per position
var new_heights: Array[float]


func _init(map_res: MapResource, affected_positions: Array[Vector2i], water_slope: bool = false):
	map_resource = map_res
	positions = affected_positions.duplicate()
	is_water_slope = water_slope
	old_heights = []
	old_collisions = []
	old_cell_types = []
	new_heights = []

	# Store old values and compute slope heights
	for pos: Vector2i in positions:
		old_heights.append(map_res.get_height_at(pos))
		old_collisions.append(map_res.get_collision_at(pos))
		old_cell_types.append(map_res.get_cell_type_at(pos))

		# Compute the interpolated slope height from neighbours
		var slope_h: float = _compute_slope_height(map_res, pos)
		new_heights.append(slope_h)

	var tag: String = "Water Slope" if is_water_slope else "Slope"
	description = "Paint %s (%d cells)" % [tag, positions.size()]


func _compute_slope_height(map_res: MapResource, pos: Vector2i) -> float:
	## Store a midpoint height for the cell.  The actual linear ramp is
	## computed at upload time by TerrainSystem._compute_slope_heights()
	## which has visibility of the full region.  Here we just set a
	## reasonable default so navigation / collision have something close.
	var neighbours: Array[Vector2i] = [
		Vector2i(pos.x - 1, pos.y),
		Vector2i(pos.x + 1, pos.y),
		Vector2i(pos.x, pos.y - 1),
		Vector2i(pos.x, pos.y + 1),
	]

	var low_h: float = INF
	var high_h: float = -INF

	for n: Vector2i in neighbours:
		if n.x < 0 or n.x >= map_res.size.x or n.y < 0 or n.y >= map_res.size.y:
			continue
		var nh: float = map_res.get_height_at(n)
		low_h = minf(low_h, nh)
		high_h = maxf(high_h, nh)

	if low_h == INF:
		return map_res.get_height_at(pos)

	# Midpoint as fallback — _compute_slope_heights() refines this later
	return (low_h + high_h) * 0.5


func execute() -> void:
	var cell_type: int = MapResource.CELL_WATER_SLOPE if is_water_slope else MapResource.CELL_SLOPE
	for i in range(positions.size()):
		map_resource.set_height_at(positions[i], new_heights[i])
		# Slopes are always traversable
		map_resource.set_collision_at(positions[i], 0)
		map_resource.set_cell_type_at(positions[i], cell_type)


func undo() -> void:
	for i in range(positions.size()):
		map_resource.set_height_at(positions[i], old_heights[i])
		map_resource.set_collision_at(positions[i], old_collisions[i])
		map_resource.set_cell_type_at(positions[i], old_cell_types[i])
