@tool
extends Node3D

## Cell terrain type constants (must mirror MapResource)
const CELL_GROUND := 0
const CELL_HIGH_GROUND := 1
const CELL_WATER := 2
const CELL_SLOPE := 3
const CELL_WATER_SLOPE := 4

@export var size = Vector2(50, 50):
	set(a_size):
		size = a_size

## Vector2i -> bool || Enums.OccupationType (occupied)
var _grid: Dictionary = {}

## Per-cell height values (populated from MapResource at load time)
var height_grid: PackedFloat32Array = PackedFloat32Array()

## Per-cell terrain type (CELL_GROUND, CELL_HIGH_GROUND, CELL_WATER, CELL_SLOPE)
var cell_type_grid: PackedByteArray = PackedByteArray()

@onready var terrain_system = $Geometry/TerrainSystem


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


func occupy_area(cell: Vector2i, footprint: Vector2i, _type: Enums.OccupationType) -> void:
	for x in range(footprint.x):
		for y in range(footprint.y):
			var c := Vector2i(cell.x + x, cell.y + y)
			_grid[c] = _type || true


func clear_area(cell: Vector2i, footprint: Vector2i) -> void:
	for x in range(footprint.x):
		for y in range(footprint.y):
			var c := Vector2i(cell.x + x, cell.y + y)
			_grid.erase(c)


func is_world_area_free(world_pos: Vector3, footprint: Vector2i) -> bool:
	var cell := world_to_cell(world_pos)
	return is_area_free(cell, footprint)


func occupy_world_area(
	world_pos: Vector3, footprint: Vector2i, _type: Enums.OccupationType
) -> void:
	var cell := world_to_cell(world_pos)
	occupy_area(cell, footprint, _type)


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


# ============================================================
# Height / Cell Type queries
# ============================================================


func _is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(size.x) and cell.y < int(size.y)


func get_height_at_cell(cell: Vector2i) -> float:
	"""Return the terrain height at a grid cell. 0.0 if no height data."""
	if height_grid.is_empty() or not _is_cell_in_bounds(cell):
		return 0.0
	return height_grid[cell.y * int(size.x) + cell.x]


func get_height_at_world(world_pos: Vector3) -> float:
	"""Return terrain height at an arbitrary world position.
	Uses bilinear interpolation when all four surrounding cells share the
	same height plateau. At cliff edges (height discontinuities between
	non-slope cells) it snaps to the height of the cell the position is in,
	preventing units from visually climbing cliff walls."""
	if height_grid.is_empty():
		return 0.0

	# Continuous grid coordinates
	var gx: float = world_pos.x
	var gz: float = world_pos.z

	# Integer cell corners
	var x0 := int(floor(gx))
	var z0 := int(floor(gz))
	var x1 := x0 + 1
	var z1 := z0 + 1

	# Clamp to grid bounds
	var cx0 := clampi(x0, 0, int(size.x) - 1)
	var cz0 := clampi(z0, 0, int(size.y) - 1)
	var cx1 := clampi(x1, 0, int(size.x) - 1)
	var cz1 := clampi(z1, 0, int(size.y) - 1)

	# Sample four corners
	var h00 := get_height_at_cell(Vector2i(cx0, cz0))
	var h10 := get_height_at_cell(Vector2i(cx1, cz0))
	var h01 := get_height_at_cell(Vector2i(cx0, cz1))
	var h11 := get_height_at_cell(Vector2i(cx1, cz1))

	# Check cell types — only interpolate when all corners are slope-compatible.
	# If any pair of adjacent corners forms a cliff edge (different heights,
	# neither is a slope), snap to the height of the cell the position is in.
	var ct00 := get_cell_type_at_cell(Vector2i(cx0, cz0))
	var ct10 := get_cell_type_at_cell(Vector2i(cx1, cz0))
	var ct01 := get_cell_type_at_cell(Vector2i(cx0, cz1))
	var ct11 := get_cell_type_at_cell(Vector2i(cx1, cz1))

	var has_cliff: bool = (
		_is_cliff_edge_pair(h00, ct00, h10, ct10)
		or _is_cliff_edge_pair(h00, ct00, h01, ct01)
		or _is_cliff_edge_pair(h10, ct10, h11, ct11)
		or _is_cliff_edge_pair(h01, ct01, h11, ct11)
	)

	if has_cliff:
		# Snap to the cell the position is actually in (no blending)
		return get_height_at_cell(Vector2i(cx0, cz0))

	# Fractional part for bilinear interpolation
	var fx := gx - float(x0)
	var fz := gz - float(z0)
	var h_top := lerpf(h00, h10, fx)
	var h_bot := lerpf(h01, h11, fx)
	return lerpf(h_top, h_bot, fz)


func _is_cliff_edge_pair(h_a: float, ct_a: int, h_b: float, ct_b: int) -> bool:
	"""True when two neighbouring cells form a cliff (height gap, no slope)."""
	if absf(h_b - h_a) <= 0.1:
		return false
	return not _is_slope_cell_type(ct_a) and not _is_slope_cell_type(ct_b)


func get_cell_type_at_cell(cell: Vector2i) -> int:
	"""Return the terrain cell type constant. CELL_GROUND if no data."""
	if cell_type_grid.is_empty() or not _is_cell_in_bounds(cell):
		return CELL_GROUND
	return cell_type_grid[cell.y * int(size.x) + cell.x]


func get_cell_type_at_world(world_pos: Vector3) -> int:
	"""Return the cell type at a world position (uses nearest cell)."""
	return get_cell_type_at_cell(world_to_cell(world_pos))


func get_slope_normal_at_world(world_pos: Vector3) -> Vector3:
	"""Compute a surface normal from the height grid using central differences.
	Returns Vector3.UP for flat ground."""
	if height_grid.is_empty():
		return Vector3.UP

	var cell := world_to_cell(world_pos)
	var hL := get_height_at_cell(Vector2i(maxi(cell.x - 1, 0), cell.y))
	var hR := get_height_at_cell(Vector2i(mini(cell.x + 1, int(size.x) - 1), cell.y))
	var hD := get_height_at_cell(Vector2i(cell.x, maxi(cell.y - 1, 0)))
	var hU := get_height_at_cell(Vector2i(cell.x, mini(cell.y + 1, int(size.y) - 1)))

	# Central difference gives the gradient; cross product gives the normal
	var tangent_x := Vector3(2.0, hR - hL, 0.0)
	var tangent_z := Vector3(0.0, hU - hD, 2.0)
	var n := tangent_z.cross(tangent_x).normalized()
	if n.y < 0.0:
		n = -n  # Ensure normal points upward
	return n


func can_unit_traverse(
	world_pos: Vector3, terrain_move_type: int, from_pos: Vector3 = Vector3.INF
) -> bool:
	"""Check if a unit with the given terrain movement type can move to world_pos.
	When from_pos is supplied, also rejects cliff-edge transitions (height change
	without a slope on either side). See NavigationConstants.TerrainMoveType."""
	var ct := get_cell_type_at_world(world_pos)

	match terrain_move_type:
		NavigationConstants.TerrainMoveType.AIR:
			return true  # air units ignore all terrain
		NavigationConstants.TerrainMoveType.WATER:
			if ct != CELL_WATER and ct != CELL_SLOPE:
				return false
		NavigationConstants.TerrainMoveType.LAND:
			if (
				ct != CELL_GROUND
				and ct != CELL_HIGH_GROUND
				and ct != CELL_SLOPE
				and ct != CELL_WATER_SLOPE
			):
				return false
		_:
			if ct == CELL_WATER:
				return false

	# Cliff-edge check: block direct transitions between different flat
	# height levels unless one of the two cells is a slope (ramp).
	if from_pos != Vector3.INF:
		var ct_from := get_cell_type_at_world(from_pos)
		if ct_from != ct:
			var either_is_slope: bool = _is_slope_cell_type(ct) or _is_slope_cell_type(ct_from)
			if not either_is_slope:
				# Different cell types and no slope involved — check height gap
				var h_from := get_height_at_cell(world_to_cell(from_pos))
				var h_to := get_height_at_cell(world_to_cell(world_pos))
				if absf(h_to - h_from) > 0.1:
					return false

	return true


# ============================================================
# Cliff collision walls
# ============================================================

const CLIFF_WALL_THICKNESS: float = 0.4
const CLIFF_WALL_HEIGHT: float = 4.0


func build_cliff_collision() -> void:
	"""Create StaticBody3D wall segments at every cliff edge so the navmesh
	is carved and units physically cannot clip through cliff faces.
	A cliff edge is a boundary between two adjacent cells that have
	different heights and neither cell is a slope."""
	if height_grid.is_empty() or cell_type_grid.is_empty():
		return

	# Remove any previously generated walls
	var old_walls: Node3D = find_child("CliffWalls")
	if old_walls:
		old_walls.queue_free()

	var walls_parent := Node3D.new()
	walls_parent.name = "CliffWalls"
	add_child(walls_parent)

	var sx: int = int(size.x)
	var sy: int = int(size.y)
	var wall_idx: int = 0

	# Scan horizontal edges (between cell (x,y) and (x+1,y))
	for y in range(sy):
		for x in range(sx - 1):
			var cell_a := Vector2i(x, y)
			var cell_b := Vector2i(x + 1, y)
			if _is_cliff_edge(cell_a, cell_b):
				var h_a := get_height_at_cell(cell_a)
				var h_b := get_height_at_cell(cell_b)
				# Wall sits at x+1 boundary, spans the full cell in Z
				var wall_x: float = float(x + 1)
				var wall_z: float = float(y) + 0.5
				var wall_y: float = (minf(h_a, h_b) + maxf(h_a, h_b)) / 2.0
				var wall_height: float = absf(h_b - h_a) + CLIFF_WALL_HEIGHT
				_add_wall_body(
					walls_parent,
					Vector3(wall_x, wall_y, wall_z),
					Vector3(CLIFF_WALL_THICKNESS, wall_height, 1.0),
					wall_idx
				)
				wall_idx += 1

	# Scan vertical edges (between cell (x,y) and (x,y+1))
	for y in range(sy - 1):
		for x in range(sx):
			var cell_a := Vector2i(x, y)
			var cell_b := Vector2i(x, y + 1)
			if _is_cliff_edge(cell_a, cell_b):
				var h_a := get_height_at_cell(cell_a)
				var h_b := get_height_at_cell(cell_b)
				# Wall sits at y+1 boundary, spans the full cell in X
				var wall_x: float = float(x) + 0.5
				var wall_z: float = float(y + 1)
				var wall_y: float = (minf(h_a, h_b) + maxf(h_a, h_b)) / 2.0
				var wall_height: float = absf(h_b - h_a) + CLIFF_WALL_HEIGHT
				_add_wall_body(
					walls_parent,
					Vector3(wall_x, wall_y, wall_z),
					Vector3(1.0, wall_height, CLIFF_WALL_THICKNESS),
					wall_idx
				)
				wall_idx += 1


func _is_cliff_edge(cell_a: Vector2i, cell_b: Vector2i) -> bool:
	"""True when the two adjacent cells have a height difference and
	neither cell is a slope (slopes are ramps, not cliffs)."""
	var ct_a := get_cell_type_at_cell(cell_a)
	var ct_b := get_cell_type_at_cell(cell_b)
	if _is_slope_cell_type(ct_a) or _is_slope_cell_type(ct_b):
		return false
	var h_a := get_height_at_cell(cell_a)
	var h_b := get_height_at_cell(cell_b)
	return absf(h_b - h_a) > 0.1


func _is_slope_cell_type(ct: int) -> bool:
	return ct == CELL_SLOPE or ct == CELL_WATER_SLOPE


func _add_wall_body(parent: Node3D, pos: Vector3, extents: Vector3, idx: int) -> void:
	var body := StaticBody3D.new()
	body.name = "CliffWall%d" % idx
	body.transform.origin = pos
	# Layer 2 so the terrain NavigationMesh (geometry_collision_mask) detects us
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("terrain_navigation_input")

	var shape := BoxShape3D.new()
	shape.size = extents

	var col := CollisionShape3D.new()
	col.shape = shape

	body.add_child(col)
	parent.add_child(body)
