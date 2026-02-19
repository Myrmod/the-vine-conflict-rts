@tool
extends Node3D

# TODO: add editor-only 2nd pass shader to 'Terrain' mesh highlighting map boundries

const EXTRA_MARGIN = 2

@export var size = Vector2(50, 50):
	set(a_size):
		size = a_size
		find_child("Terrain").mesh.size = size + Vector2(EXTRA_MARGIN, EXTRA_MARGIN) * 2
		find_child("Terrain").mesh.center_offset = Vector3(size.x, 0.0, size.y) / 2.0

## Vector2i -> bool (occupied)
var _grid: Dictionary = {}


func get_topdown_polygon_2d():
	return [Vector2(0, 0), Vector2(size.x, 0), size, Vector2(0, size.y)]


func world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(world_pos.x)), int(floor(world_pos.z)))


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x, 0.0, cell.y)


func is_cell_free(world_pos: Vector3) -> bool:
	var cell := world_to_cell(world_pos)

	# Bounds check
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return false

	return not _grid.has(cell)


func set_cell_occupied(world_pos: Vector3) -> void:
	var cell := world_to_cell(world_pos)

	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		push_warning("Trying to occupy out-of-bounds cell %s" % cell)
		return

	_grid[cell] = true


func clear_cell(world_pos: Vector3) -> void:
	var cell := world_to_cell(world_pos)
	_grid.erase(cell)


func is_area_free(cell: Vector2i, footprint: Vector2i) -> bool:
	for x in range(footprint.x):
		for y in range(footprint.y):
			var check_cell := Vector2i(cell.x + x, cell.y + y)

			# Bounds check
			if check_cell.x < 0 or check_cell.y < 0:
				return false
			if check_cell.x >= size.x or check_cell.y >= size.y:
				return false

			# Occupied check
			if _grid.has(check_cell):
				return false

	return true


func occupy_area(cell: Vector2i, footprint: Vector2i) -> void:
	for x in range(footprint.x):
		for y in range(footprint.y):
			var c := Vector2i(cell.x + x, cell.y + y)
			_grid[c] = true


func clear_area(cell: Vector2i, footprint: Vector2i) -> void:
	for x in range(footprint.x):
		for y in range(footprint.y):
			var c := Vector2i(cell.x + x, cell.y + y)
			_grid.erase(c)


func is_world_area_free(world_pos: Vector3, footprint: Vector2i) -> bool:
	var cell := world_to_cell(world_pos)
	return is_area_free(cell, footprint)


func occupy_world_area(world_pos: Vector3, footprint: Vector2i) -> void:
	var cell := world_to_cell(world_pos)
	occupy_area(cell, footprint)


func find_nearest_free_area(origin_cell: Vector2i, footprint: Vector2i, max_radius: int = 50):
	# First try the origin
	if is_area_free(origin_cell, footprint):
		return origin_cell

	for radius in range(1, max_radius + 1):
		# Scan square ring around origin
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				# Only check perimeter of the square (the "ring")
				if abs(x) != radius and abs(y) != radius:
					continue

				var candidate := origin_cell + Vector2i(x, y)

				if is_area_free(candidate, footprint):
					return candidate

	return null
