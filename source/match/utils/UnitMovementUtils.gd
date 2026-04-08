const DISTANCE_REDUCTION_BY_DIVISION_ITERATIONS_MAX = 10
const DISTANCE_REDUCTION_BY_SUBTRACTION_ITERATIONS_MAX = 10

# crowd - group of units
# pivot - pivot point, central point of crowd


static func crowd_moved_to_new_pivot(units, new_pivot):
	"""calculates new unit positions relative to new_pivot"""
	if units.is_empty():
		return []
	if units.size() == 1:
		return [[units[0], new_pivot]]
	var old_pivot = calculate_aabb_crowd_pivot_yless(units)
	var yless_unit_offsets_from_old_pivot = _calculate_yless_unit_offsets_from_old_pivot(
		units, old_pivot
	)
	var new_unit_positions = _calculate_new_unit_positions(
		yless_unit_offsets_from_old_pivot, new_pivot
	)
	var condensed_unit_positions = _attract_unit_positions_towards_pivot(
		new_unit_positions, new_pivot, UnitConstants.ADHERENCE_MARGIN_M * 2
	)
	return condensed_unit_positions


## Spread units in a circle pattern around a target point, avoiding all
## existing units/structures.  Units are sorted by distance to target
## (closest first) so the nearest unit gets the best spot.
## Returns Array of [unit, Vector3] pairs — deterministic (no randomness).
static func circle_spread(units: Array, target: Vector3) -> Array:
	if units.is_empty():
		return []

	var target_yless := Vector3(target.x, 0.0, target.z)

	if units.size() == 1:
		return [[units[0], target_yless]]

	# Sort units by distance to target (ascending) — deterministic tiebreak by id.
	var sorted_units := units.duplicate()
	sorted_units.sort_custom(
		func(a, b):
			var da: float = a.global_position.distance_squared_to(target_yless)
			var db: float = b.global_position.distance_squared_to(target_yless)
			if absf(da - db) < 0.001:
				return a.id < b.id
			return da < db
	)

	var margin: float = UnitConstants.ADHERENCE_MARGIN_M
	# Collect obstacle discs from all existing units not in our move group.
	var obstacle_discs: Array = _collect_obstacle_discs(sorted_units)
	# The target point itself is the center "disc" with radius 0.
	var placed_discs: Array = []

	var result: Array = []
	for unit in sorted_units:
		var r: float = unit.radius if unit.radius else 0.5
		var pos: Vector3 = _find_closest_free_position(
			target_yless, r, placed_discs, obstacle_discs, margin
		)
		placed_discs.append([pos, r])
		result.append([unit, pos])
	return result


## Gather [position, radius] discs for all existing units that are NOT
## in the units_to_move array.
static func _collect_obstacle_discs(units_to_move: Array) -> Array:
	var move_set := {}
	for u in units_to_move:
		move_set[u.get_instance_id()] = true
	var discs: Array = []
	for unit_id in EntityRegistry.entities:
		var unit = EntityRegistry.entities[unit_id]
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.get_instance_id() in move_set:
			continue
		var r = unit.radius
		if r == null or r <= 0.0:
			continue
		var pos := Vector3(unit.global_position.x, 0.0, unit.global_position.z)
		discs.append([pos, r])
	return discs


## Find the closest unoccupied position to `center` for a disc of `radius`.
## Tries the center first, then scans outward in concentric rings.
static func _find_closest_free_position(
	center: Vector3, radius: float, placed: Array, obstacles: Array, margin: float
) -> Vector3:
	# Try the center point first.
	if (
		not _disc_collides_with_others([center, radius], placed, margin)
		and not _disc_collides_with_others([center, radius], obstacles, margin)
	):
		return center

	# Scan concentric rings outward.
	var ring_step: float = radius * 0.8 + margin
	var max_rings: int = 20
	for ring in range(1, max_rings + 1):
		var ring_radius: float = ring_step * float(ring)
		# More candidates on larger rings.
		var candidate_count: int = maxi(6, ring * 6)
		for i in range(candidate_count):
			var angle: float = TAU * float(i) / float(candidate_count)
			var candidate := Vector3(
				center.x + cos(angle) * ring_radius,
				0.0,
				center.z + sin(angle) * ring_radius,
			)
			if (
				not _disc_collides_with_others([candidate, radius], placed, margin)
				and not _disc_collides_with_others([candidate, radius], obstacles, margin)
			):
				return candidate
	# Fallback — should rarely happen with 20 rings.
	return center


static func calculate_aabb_crowd_pivot_yless(units):
	"""calculates pivot which is a center of crowd AABB"""
	var unit_positions = []
	for unit in units:
		unit_positions.append(unit.global_position)
	var begin = Vector3(_calculate_min_x(unit_positions), 0.0, _calculate_min_z(unit_positions))
	var end = Vector3(_calculate_max_x(unit_positions), 0.0, _calculate_max_z(unit_positions))
	return (begin + end) / 2.0 * Vector3(1, 0, 1)


static func units_adhere(unit_a, unit_b):
	"""checks if distance between unit borders is within margin"""
	return _unit_in_range_of_other(unit_a, unit_b, UnitConstants.ADHERENCE_MARGIN_M)


static func _unit_in_range_of_other(unit_a, unit_b, b_range):
	"""checks if distance from one unit border to another is within range"""
	var unit_a_position_yless = unit_a.global_position * Vector3(1, 0, 1)
	var unit_b_position_yless = unit_b.global_position * Vector3(1, 0, 1)
	return (
		unit_a_position_yless.distance_to(unit_b_position_yless)
		<= (unit_a.radius + unit_b.radius + b_range)
	)


static func _attract_unit_positions_towards_pivot(unit_positions, pivot, interunit_threshold):
	"""takes List[Tuple[unit, point]], pivot, and interunit_threshold(min interunit dist)"""
	var new_unit_positions = {}
	var unit_distances_to_pivot = []
	for tuple in unit_positions:
		var unit = tuple[0]
		var point = tuple[1]
		new_unit_positions[unit] = point
		unit_distances_to_pivot.append([unit, point.distance_to(pivot)])
	unit_distances_to_pivot.sort_custom(func(a, b): return a[1] < b[1])
	var discs = [[pivot, 0]]
	for tuple in unit_distances_to_pivot:
		var unit = tuple[0]
		var distance = tuple[1]
		var direction_towards_pivot = (pivot - new_unit_positions[unit]).normalized()
		# reduce distance by division
		for _i in range(DISTANCE_REDUCTION_BY_DIVISION_ITERATIONS_MAX):
			var candidate_pos = new_unit_positions[unit] + direction_towards_pivot * distance / 2.0
			if not _disc_collides_with_others(
				[candidate_pos, unit.radius], discs, interunit_threshold
			):
				distance /= 2.0
				new_unit_positions[unit] = candidate_pos
			else:
				break
		# reduce distance by subtraction
		var reduction_step = max(
			distance / 2.0 / float(DISTANCE_REDUCTION_BY_SUBTRACTION_ITERATIONS_MAX),
			interunit_threshold / 2.0
		)
		for _i in range(DISTANCE_REDUCTION_BY_SUBTRACTION_ITERATIONS_MAX):
			var candidate_pos = new_unit_positions[unit] + direction_towards_pivot * reduction_step
			if not _disc_collides_with_others(
				[candidate_pos, unit.radius], discs, interunit_threshold
			):
				new_unit_positions[unit] = candidate_pos
			else:
				break
		discs.append([new_unit_positions[unit], unit.radius])
	return Utils.Dict.items(new_unit_positions)


static func _disc_collides_with_others(disc, discs, adherence_margin):
	var disc_pos = disc[0]
	var disc_radius = disc[1]
	for other_disc in discs:
		var other_disc_pos = other_disc[0]
		var other_disc_radius = other_disc[1]
		if (
			disc_pos.distance_to(other_disc_pos)
			<= disc_radius + other_disc_radius + adherence_margin
		):
			return true
	return false


static func _calculate_new_unit_positions(yless_unit_offsets_from_old_pivot, new_pivot):
	var new_unit_positions = []
	for tuple in yless_unit_offsets_from_old_pivot:
		var unit = tuple[0]
		var offset = tuple[1]
		new_unit_positions.append([unit, new_pivot + offset])
	return new_unit_positions


static func _calculate_yless_unit_offsets_from_old_pivot(units, old_pivot):
	var old_pivot_yless = old_pivot * Vector3(1, 0, 1)
	var yless_unit_offsets_from_old_pivot = []
	for unit in units:
		var unit_position_yless = unit.global_position * Vector3(1, 0, 1)
		(
			yless_unit_offsets_from_old_pivot
			. append(
				[
					unit,
					unit_position_yless - old_pivot_yless,
				]
			)
		)
	return yless_unit_offsets_from_old_pivot


static func _calculate_min_x(positions):
	return _calculate_extremum(positions, Vector3(1, 0, 0), true)


static func _calculate_min_z(positions):
	return _calculate_extremum(positions, Vector3(0, 0, 1), true)


static func _calculate_max_x(positions):
	return _calculate_extremum(positions, Vector3(1, 0, 0), false)


static func _calculate_max_z(positions):
	return _calculate_extremum(positions, Vector3(0, 0, 1), false)


static func _calculate_extremum(positions, axis, minimum):
	var extremum = null
	for position in positions:
		var value = position.x if axis.x == 1 else position.z
		if extremum == null:
			extremum = value
			continue
		if (minimum and value < extremum) or (not minimum and value > extremum):
			extremum = value
	return extremum


## Spread units in a grid formation perpendicular to the drag direction.
## The drag vector (start_pos → end_pos) defines the "forward" facing;
## units are placed on rows rotated 90° from it, centred on the midpoint.
## Drag length controls the width: short drag = narrow = more rows,
## long drag = wide = fewer rows.  Row spacing uses the average unit radius.
## Returns Array of [unit, Vector3] pairs.
static func line_spread(units: Array, start_pos: Vector3, end_pos: Vector3) -> Array:
	if units.is_empty():
		return []

	var mid := (start_pos + end_pos) * 0.5
	mid.y = 0.0

	if units.size() == 1:
		return [[units[0], mid]]

	var drag_dir: Vector3 = end_pos - start_pos
	drag_dir.y = 0.0
	var drag_len: float = drag_dir.length()
	if drag_len < 0.01:
		return [[units[0], mid]]

	# Forward direction (the drag direction) and perpendicular spread axis.
	var forward_dir: Vector3 = drag_dir.normalized()
	var spread_dir: Vector3 = Vector3(-drag_dir.z, 0.0, drag_dir.x).normalized()

	# Average unit radius for spacing.
	var total_r: float = 0.0
	for u in units:
		total_r += u.radius if u.radius else 0.5
	var avg_r: float = total_r / float(units.size())
	var spacing: float = avg_r * 2.5

	# How many columns fit in the drag width?
	var cols: int = maxi(1, int(drag_len / spacing))
	# Clamp so we don't have more columns than units.
	cols = mini(cols, units.size())
	var rows: int = ceili(float(units.size()) / float(cols))

	# Sort units by their projection onto the spread axis so spatial
	# order is preserved (left-most unit → left end of line, etc.)
	var sorted_units := units.duplicate()
	sorted_units.sort_custom(
		func(a, b):
			var pa: float = a.global_position.dot(spread_dir)
			var pb: float = b.global_position.dot(spread_dir)
			return pa < pb
	)

	# Compute actual spread width from cols (not drag_len) so positions
	# are centred and evenly spaced.
	var spread_width: float = float(cols - 1) * spacing if cols > 1 else 0.0
	var row_depth: float = float(rows - 1) * spacing if rows > 1 else 0.0

	var result: Array = []
	var idx: int = 0
	for row in range(rows):
		# Row offset: first row is frontmost, subsequent rows are behind.
		var row_offset: Vector3 = -forward_dir * (float(row) * spacing - row_depth * 0.5)
		for col in range(cols):
			if idx >= sorted_units.size():
				break
			var col_t: float = 0.5
			if cols > 1:
				col_t = float(col) / float(cols - 1)
			var col_offset: Vector3 = spread_dir * (col_t * spread_width - spread_width * 0.5)
			var pos: Vector3 = mid + row_offset + col_offset
			pos.y = 0.0
			result.append([sorted_units[idx], pos])
			idx += 1
	return result
