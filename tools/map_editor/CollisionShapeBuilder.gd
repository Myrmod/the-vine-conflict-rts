class_name CollisionShapeBuilder

extends RefCounted

## Generates merged 3D collision shape data from a MapResource.
## Used for both editor visualization and runtime export.
##
## Instead of per-cell collision tiles, this builder produces:
## - Large merged rectangular blocks for high-ground / water areas
## - Continuous vertical walls for cliff edges
## - Tilted collision surfaces for slopes (configurable angle)
## - Separate group identifiers for water slopes
##
## Shape dictionary format:
## {
##   "type":      SHAPE_BOX | SHAPE_WALL | SHAPE_SLOPE,
##   "group":     GROUP_* constant,
##   "position":  Vector3  – world-space centre,
##   "size":      Vector3  – dimensions,
##   "angle_deg": float    – tilt angle for slopes (degrees from horizontal),
##   "direction": Vector2i – slope tilt direction (toward higher neighbour),
##   "rect":      Rect2i   – grid rectangle covered,
## }

# Shape types
const SHAPE_BOX := "box"
const SHAPE_WALL := "wall"
const SHAPE_SLOPE := "slope"

# Collision groups – used to tag shapes for runtime filtering
const GROUP_HIGH_GROUND := "high_ground"
const GROUP_WATER := "water"
const GROUP_CLIFF := "cliff"
const GROUP_SLOPE := "slope"
const GROUP_WATER_SLOPE := "water_slope"
const GROUP_MANUAL := "manual"
const GROUP_GROUND := "ground"


## Build every collision shape for a given map.
static func build_all(map: MapResource) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []

	# 0. Base ground plane — covers the entire map so nothing clips through
	shapes.append_array(_build_ground_plane(map))

	# 1. Merged blocks for high-ground plateaus
	shapes.append_array(_build_height_blocks(map, MapResource.CELL_HIGH_GROUND, GROUP_HIGH_GROUND))

	# 2. Merged blocks for water basins
	shapes.append_array(_build_height_blocks(map, MapResource.CELL_WATER, GROUP_WATER))

	# 3. Cliff walls at height transitions (no slope in between)
	shapes.append_array(_build_cliff_walls(map))

	# 4. Tilted slope shapes (ground ↔ high-ground)
	shapes.append_array(_build_slope_shapes(map, MapResource.CELL_SLOPE, GROUP_SLOPE))

	# 4b. Side walls for slope ramps (perpendicular to slope direction)
	shapes.append_array(_build_slope_side_walls(map, MapResource.CELL_SLOPE))

	# 5. Tilted water-slope shapes (separate group for passability rules)
	shapes.append_array(_build_slope_shapes(map, MapResource.CELL_WATER_SLOPE, GROUP_WATER_SLOPE))

	# 5b. Side walls for water-slope ramps
	shapes.append_array(_build_slope_side_walls(map, MapResource.CELL_WATER_SLOPE))

	# 6. Manually painted collision on ground-level cells
	shapes.append_array(_build_manual_collision(map))

	return shapes


# ================================================================
# Ground plane   (default collision covering the whole map)
# ================================================================


static func _build_ground_plane(map: MapResource) -> Array[Dictionary]:
	var cs: float = FeatureFlags.grid_cell_size
	var ground_thickness: float = 0.1
	return [
		{
			"type": SHAPE_BOX,
			"group": GROUP_GROUND,
			"position":
			Vector3(
				map.size.x * cs * 0.5,
				-ground_thickness * 0.5,
				map.size.y * cs * 0.5,
			),
			"size": Vector3(map.size.x * cs, ground_thickness, map.size.y * cs),
			"rect": Rect2i(0, 0, map.size.x, map.size.y),
		}
	]


# ================================================================
# Height blocks   (greedy rectangle merging)
# ================================================================


static func _build_height_blocks(
	map: MapResource, cell_type: int, group: String
) -> Array[Dictionary]:
	var visited: Dictionary = {}
	var shapes: Array[Dictionary] = []
	var cs: float = FeatureFlags.grid_cell_size

	for y: int in range(map.size.y):
		for x: int in range(map.size.x):
			var pos: Vector2i = Vector2i(x, y)
			if visited.has(pos):
				continue
			if map.get_cell_type_at(pos) != cell_type:
				continue

			# --- greedy expand width ---
			var w: int = 1
			while x + w < map.size.x:
				var np: Vector2i = Vector2i(x + w, y)
				if visited.has(np) or map.get_cell_type_at(np) != cell_type:
					break
				w += 1

			# --- greedy expand height (same width) ---
			var h: int = 1
			while y + h < map.size.y:
				var row_ok: bool = true
				for dx: int in range(w):
					var np: Vector2i = Vector2i(x + dx, y + h)
					if visited.has(np) or map.get_cell_type_at(np) != cell_type:
						row_ok = false
						break
				if not row_ok:
					break
				h += 1

			# mark visited
			for dy: int in range(h):
				for dx: int in range(w):
					visited[Vector2i(x + dx, y + dy)] = true

			var cell_height: float = map.get_height_at(pos)

			# Box covers from ground-plane to the cell height
			var box_height: float
			var box_y: float
			if cell_type == MapResource.CELL_WATER:
				# water is below ground → box goes downward
				box_height = absf(cell_height) + 0.2
				box_y = cell_height / 2.0
			else:
				# high ground is above → box goes upward
				box_height = absf(cell_height) + 0.2
				box_y = cell_height / 2.0

			(
				shapes
				. append(
					{
						"type": SHAPE_BOX,
						"group": group,
						"position": Vector3((x + w * 0.5) * cs, box_y, (y + h * 0.5) * cs),
						"size": Vector3(w * cs, box_height, h * cs),
						"rect": Rect2i(x, y, w, h),
					}
				)
			)

	return shapes


# ================================================================
# Cliff walls   (continuous vertical collision at height edges)
# ================================================================


static func _build_cliff_walls(map: MapResource) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	var cs: float = FeatureFlags.grid_cell_size
	# Paper-thin wall — sits exactly on the cell boundary (90° vertical)
	var wall_thickness: float = 0.02

	# --- Horizontal edges (between row y and y+1) ---
	for y: int in range(map.size.y - 1):
		var x: int = 0
		while x < map.size.x:
			var pos_a: Vector2i = Vector2i(x, y)
			var pos_b: Vector2i = Vector2i(x, y + 1)
			var h_a: float = map.get_height_at(pos_a)
			var h_b: float = map.get_height_at(pos_b)
			var ct_a: int = map.get_cell_type_at(pos_a)
			var ct_b: int = map.get_cell_type_at(pos_b)

			if is_equal_approx(h_a, h_b) or _is_slope_type(ct_a) or _is_slope_type(ct_b):
				x += 1
				continue

			# found a cliff – extend run along X
			var start_x: int = x
			var ref_h_a: float = h_a
			var ref_h_b: float = h_b
			while x < map.size.x:
				var na: Vector2i = Vector2i(x, y)
				var nb: Vector2i = Vector2i(x, y + 1)
				var ha: float = map.get_height_at(na)
				var hb: float = map.get_height_at(nb)
				var ca: int = map.get_cell_type_at(na)
				var cb: int = map.get_cell_type_at(nb)
				if (
					not is_equal_approx(ha, ref_h_a)
					or not is_equal_approx(hb, ref_h_b)
					or _is_slope_type(ca)
					or _is_slope_type(cb)
				):
					break
				x += 1

			var run: int = x - start_x
			var min_h: float = minf(ref_h_a, ref_h_b)
			var max_h: float = maxf(ref_h_a, ref_h_b)
			var wall_h: float = max_h - min_h

			(
				shapes
				. append(
					{
						"type": SHAPE_WALL,
						"group": GROUP_CLIFF,
						"position":
						Vector3(
							(start_x + run * 0.5) * cs,
							min_h + wall_h * 0.5,
							(y + 1) * cs,
						),
						"size": Vector3(run * cs, wall_h, wall_thickness),
						"rect": Rect2i(start_x, y, run, 2),
					}
				)
			)

	# --- Vertical edges (between column x and x+1) ---
	for x: int in range(map.size.x - 1):
		var y: int = 0
		while y < map.size.y:
			var pos_a: Vector2i = Vector2i(x, y)
			var pos_b: Vector2i = Vector2i(x + 1, y)
			var h_a: float = map.get_height_at(pos_a)
			var h_b: float = map.get_height_at(pos_b)
			var ct_a: int = map.get_cell_type_at(pos_a)
			var ct_b: int = map.get_cell_type_at(pos_b)

			if is_equal_approx(h_a, h_b) or _is_slope_type(ct_a) or _is_slope_type(ct_b):
				y += 1
				continue

			var start_y: int = y
			var ref_h_a: float = h_a
			var ref_h_b: float = h_b
			while y < map.size.y:
				var na: Vector2i = Vector2i(x, y)
				var nb: Vector2i = Vector2i(x + 1, y)
				var ha: float = map.get_height_at(na)
				var hb: float = map.get_height_at(nb)
				var ca: int = map.get_cell_type_at(na)
				var cb: int = map.get_cell_type_at(nb)
				if (
					not is_equal_approx(ha, ref_h_a)
					or not is_equal_approx(hb, ref_h_b)
					or _is_slope_type(ca)
					or _is_slope_type(cb)
				):
					break
				y += 1

			var run: int = y - start_y
			var min_h: float = minf(ref_h_a, ref_h_b)
			var max_h: float = maxf(ref_h_a, ref_h_b)
			var wall_h: float = max_h - min_h

			(
				shapes
				. append(
					{
						"type": SHAPE_WALL,
						"group": GROUP_CLIFF,
						"position":
						Vector3(
							(x + 1) * cs,
							min_h + wall_h * 0.5,
							(start_y + run * 0.5) * cs,
						),
						"size": Vector3(wall_thickness, wall_h, run * cs),
						"rect": Rect2i(x, start_y, 2, run),
					}
				)
			)

	return shapes


# ================================================================
# Slope shapes   (tilted collision surfaces)
# ================================================================


static func _build_slope_shapes(
	map: MapResource, cell_type: int, group: String
) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	var cs: float = FeatureFlags.grid_cell_size
	var visited: Dictionary = {}

	for y: int in range(map.size.y):
		for x: int in range(map.size.x):
			var pos: Vector2i = Vector2i(x, y)
			if visited.has(pos):
				continue
			if map.get_cell_type_at(pos) != cell_type:
				continue

			# Flood-fill to find the entire contiguous slope region first,
			# then greedily merge into rectangles.
			var region: Array[Vector2i] = _flood_fill_cell_type(map, pos, cell_type, visited)

			# Compute one overall direction for the whole region
			var direction: Vector2i = _get_region_slope_direction(map, region)

			# Greedy-merge the region into axis-aligned rectangles
			var rects: Array[Rect2i] = _greedy_merge_region(region)

			for rect: Rect2i in rects:
				# Find the min and max heights that border this rectangle.
				# The slope surface must span from low_h to high_h to
				# seamlessly connect with adjacent height blocks.
				var low_h: float = INF
				var high_h: float = -INF
				for ry: int in range(rect.position.y, rect.position.y + rect.size.y):
					for rx: int in range(rect.position.x, rect.position.x + rect.size.x):
						var cell_h: float = map.get_height_at(Vector2i(rx, ry))
						low_h = minf(low_h, cell_h)
						high_h = maxf(high_h, cell_h)
						# Also check direct neighbours for the actual connected heights
						for nd: Vector2i in [
							Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
						]:
							var nb: Vector2i = Vector2i(rx, ry) + nd
							if nb.x < 0 or nb.x >= map.size.x or nb.y < 0 or nb.y >= map.size.y:
								continue
							var nb_ct: int = map.get_cell_type_at(nb)
							if nb_ct != cell_type:
								var nb_h: float = map.get_height_at(nb)
								low_h = minf(low_h, nb_h)
								high_h = maxf(high_h, nb_h)

				if low_h == INF:
					low_h = 0.0
				if high_h == -INF:
					high_h = 0.0

				var mid_h: float = (low_h + high_h) * 0.5
				var span_h: float = high_h - low_h

				# The slope thickness along the tilt axis must cover the
				# full height span so it connects to both height blocks.
				var slope_length: float
				if absf(direction.x) > 0:
					slope_length = rect.size.x * cs
				else:
					slope_length = rect.size.y * cs
				# Compute the tilt angle from geometry so the surface
				# always reaches from low_h to high_h.
				var actual_angle: float = 0.0
				if slope_length > 0.001 and span_h > 0.001:
					actual_angle = rad_to_deg(atan2(span_h, slope_length))

				(
					shapes
					. append(
						{
							"type": SHAPE_SLOPE,
							"group": group,
							"position":
							Vector3(
								(rect.position.x + rect.size.x * 0.5) * cs,
								mid_h,
								(rect.position.y + rect.size.y * 0.5) * cs,
							),
							"size": Vector3(rect.size.x * cs, 0.1, rect.size.y * cs),
							"angle_deg": actual_angle,
							"direction": direction,
							"rect": rect,
						}
					)
				)

	return shapes


static func _flood_fill_cell_type(
	map: MapResource,
	start: Vector2i,
	cell_type: int,
	visited: Dictionary,
) -> Array[Vector2i]:
	"""Flood-fill to find all contiguous cells of the given type."""
	var result: Array[Vector2i] = []
	var stack: Array[Vector2i] = [start]

	while stack.size() > 0:
		var pos: Vector2i = stack.pop_back()
		if visited.has(pos):
			continue
		if pos.x < 0 or pos.x >= map.size.x or pos.y < 0 or pos.y >= map.size.y:
			continue
		if map.get_cell_type_at(pos) != cell_type:
			continue

		visited[pos] = true
		result.append(pos)

		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = pos + d
			if not visited.has(n):
				stack.append(n)

	return result


static func _get_region_slope_direction(map: MapResource, region: Array[Vector2i]) -> Vector2i:
	"""Compute one dominant slope direction for an entire contiguous region."""
	var total_diff: Vector2 = Vector2.ZERO

	for pos: Vector2i in region:
		var my_h: float = map.get_height_at(pos)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = pos + d
			if n.x < 0 or n.x >= map.size.x or n.y < 0 or n.y >= map.size.y:
				continue
			# Only consider neighbours outside the region (actual height transitions)
			if map.get_cell_type_at(n) == map.get_cell_type_at(pos):
				continue
			var diff: float = map.get_height_at(n) - my_h
			total_diff += Vector2(d.x, d.y) * diff

	if total_diff.length_squared() < 0.001:
		return Vector2i(1, 0)

	# Pick the dominant axis
	if absf(total_diff.x) >= absf(total_diff.y):
		return Vector2i(1, 0) if total_diff.x > 0 else Vector2i(-1, 0)
	else:
		return Vector2i(0, 1) if total_diff.y > 0 else Vector2i(0, -1)


static func _greedy_merge_region(region: Array[Vector2i]) -> Array[Rect2i]:
	"""Greedy-merge a set of cells into axis-aligned rectangles."""
	var rects: Array[Rect2i] = []
	var remaining: Dictionary = {}
	for pos: Vector2i in region:
		remaining[pos] = true

	# Sort by y then x for deterministic row-first merging
	var sorted: Array[Vector2i] = region.duplicate()
	sorted.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x
	)

	for pos: Vector2i in sorted:
		if not remaining.has(pos):
			continue

		var x: int = pos.x
		var y: int = pos.y

		# Expand width
		var w: int = 1
		while remaining.has(Vector2i(x + w, y)):
			w += 1

		# Expand height
		var h: int = 1
		var can_expand: bool = true
		while can_expand:
			for dx: int in range(w):
				if not remaining.has(Vector2i(x + dx, y + h)):
					can_expand = false
					break
			if can_expand:
				h += 1

		# Mark consumed
		for dy: int in range(h):
			for dx: int in range(w):
				remaining.erase(Vector2i(x + dx, y + dy))

		rects.append(Rect2i(x, y, w, h))

	return rects


# ================================================================
# Slope side walls   (block the non-ramp edges of slope regions)
# ================================================================


static func _build_slope_side_walls(map: MapResource, cell_type: int) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	var cs: float = FeatureFlags.grid_cell_size
	var wall_thickness: float = 0.02
	var visited: Dictionary = {}

	for y: int in range(map.size.y):
		for x: int in range(map.size.x):
			var pos: Vector2i = Vector2i(x, y)
			if visited.has(pos):
				continue
			if map.get_cell_type_at(pos) != cell_type:
				continue

			var region: Array[Vector2i] = _flood_fill_cell_type(map, pos, cell_type, visited)
			var direction: Vector2i = _get_region_slope_direction(map, region)

			# Height range from non-slope neighbours
			var low_h: float = INF
			var high_h: float = -INF
			var region_set: Dictionary = {}
			for p: Vector2i in region:
				region_set[p] = true
			for p: Vector2i in region:
				for d: Vector2i in [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
				]:
					var n: Vector2i = p + d
					if n.x < 0 or n.x >= map.size.x or n.y < 0 or n.y >= map.size.y:
						continue
					if not region_set.has(n):
						low_h = minf(low_h, map.get_height_at(n))
						high_h = maxf(high_h, map.get_height_at(n))

			if low_h == INF or high_h == -INF:
				continue
			var wall_h: float = high_h - low_h
			if wall_h < 0.01:
				continue
			var mid_h: float = (low_h + high_h) * 0.5

			# Perpendicular directions to the slope
			var perp_dirs: Array[Vector2i]
			if abs(direction.x) > 0:
				perp_dirs = [Vector2i(0, -1), Vector2i(0, 1)]
			else:
				perp_dirs = [Vector2i(-1, 0), Vector2i(1, 0)]

			for sd: Vector2i in perp_dirs:
				for p: Vector2i in region:
					var n: Vector2i = p + sd
					if region_set.has(n):
						continue
					if sd.x != 0:
						var wx: float = (p.x + (1 if sd.x > 0 else 0)) * cs
						(
							shapes
							. append(
								{
									"type": SHAPE_WALL,
									"group": GROUP_CLIFF,
									"position": Vector3(wx, mid_h, (p.y + 0.5) * cs),
									"size": Vector3(wall_thickness, wall_h, 1.0 * cs),
									"rect": Rect2i(p.x, p.y, 1, 1),
								}
							)
						)
					else:
						var wz: float = (p.y + (1 if sd.y > 0 else 0)) * cs
						(
							shapes
							. append(
								{
									"type": SHAPE_WALL,
									"group": GROUP_CLIFF,
									"position": Vector3((p.x + 0.5) * cs, mid_h, wz),
									"size": Vector3(1.0 * cs, wall_h, wall_thickness),
									"rect": Rect2i(p.x, p.y, 1, 1),
								}
							)
						)

	return shapes


# ================================================================
# Manual collision   (ground-level cells manually blocked)
# ================================================================


static func _build_manual_collision(map: MapResource) -> Array[Dictionary]:
	var visited: Dictionary = {}
	var shapes: Array[Dictionary] = []
	var cs: float = FeatureFlags.grid_cell_size

	for y: int in range(map.size.y):
		for x: int in range(map.size.x):
			var pos: Vector2i = Vector2i(x, y)
			if visited.has(pos):
				continue
			if map.get_cell_type_at(pos) != MapResource.CELL_GROUND:
				continue
			if map.get_collision_at(pos) != 1:
				continue
			# Height-edge cells are covered by cliff walls
			if map.is_height_edge(pos):
				continue

			# greedy expand
			var w: int = 1
			while x + w < map.size.x:
				var np: Vector2i = Vector2i(x + w, y)
				if visited.has(np):
					break
				if map.get_cell_type_at(np) != MapResource.CELL_GROUND:
					break
				if map.get_collision_at(np) != 1:
					break
				if map.is_height_edge(np):
					break
				w += 1

			var h: int = 1
			while y + h < map.size.y:
				var row_ok: bool = true
				for dx: int in range(w):
					var np: Vector2i = Vector2i(x + dx, y + h)
					if visited.has(np):
						row_ok = false
						break
					if map.get_cell_type_at(np) != MapResource.CELL_GROUND:
						row_ok = false
						break
					if map.get_collision_at(np) != 1:
						row_ok = false
						break
					if map.is_height_edge(np):
						row_ok = false
						break
				if not row_ok:
					break
				h += 1

			for dy: int in range(h):
				for dx: int in range(w):
					visited[Vector2i(x + dx, y + dy)] = true

			(
				shapes
				. append(
					{
						"type": SHAPE_BOX,
						"group": GROUP_MANUAL,
						"position": Vector3((x + w * 0.5) * cs, 0.15, (y + h * 0.5) * cs),
						"size": Vector3(w * cs, 0.3, h * cs),
						"rect": Rect2i(x, y, w, h),
					}
				)
			)

	return shapes


# ================================================================
# Helpers
# ================================================================


static func _is_slope_type(cell_type: int) -> bool:
	return cell_type == MapResource.CELL_SLOPE or cell_type == MapResource.CELL_WATER_SLOPE
