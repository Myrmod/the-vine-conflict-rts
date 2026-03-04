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
	## Average the heights of all 4-connected neighbours to create a
	## smooth transition.  If the cell has no neighbours with different
	## heights the value stays the same as the current cell.
	var neighbours: Array[Vector2i] = [
		Vector2i(pos.x - 1, pos.y),
		Vector2i(pos.x + 1, pos.y),
		Vector2i(pos.x, pos.y - 1),
		Vector2i(pos.x, pos.y + 1),
	]

	var total: float = 0.0
	var count: int = 0

	for n: Vector2i in neighbours:
		if n.x < 0 or n.x >= map_res.size.x or n.y < 0 or n.y >= map_res.size.y:
			continue
		total += map_res.get_height_at(n)
		count += 1

	if count == 0:
		return map_res.get_height_at(pos)

	return total / float(count)


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
