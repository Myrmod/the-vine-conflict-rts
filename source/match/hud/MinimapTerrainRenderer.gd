class_name MinimapTerrainRenderer

extends RefCounted

## Generates a 2D terrain overview Image for the minimap and map preview.
## Water is rendered blueish, high ground is lighter with dark edge markers,
## slopes show directional shading, and ground is neutral green.

# Palette
const COLOR_GROUND := Color(0.35, 0.50, 0.30)  # earthy green
const COLOR_HIGH_GROUND := Color(0.55, 0.65, 0.45)  # lighter elevated green
const COLOR_WATER := Color(0.18, 0.35, 0.65)  # deep blue
const COLOR_SLOPE := Color(0.50, 0.55, 0.38)  # transitional green-brown
const COLOR_WATER_SLOPE := Color(0.22, 0.40, 0.55)  # blue-green transition
const COLOR_CLIFF_EDGE := Color(0.20, 0.18, 0.15)  # dark edge line


static func generate_image_from_map(map_node: Node3D) -> Image:
	"""Build an RGBA8 image from a runtime Map node's height and cell-type grids.
	Each pixel = one grid cell.  Returns null if no data."""
	var map_size: Vector2 = map_node.size if "size" in map_node else Vector2(50, 50)
	var w := int(map_size.x)
	var h := int(map_size.y)

	var height_grid: PackedFloat32Array = (
		map_node.height_grid if "height_grid" in map_node else PackedFloat32Array()
	)
	var cell_type_grid: PackedByteArray = (
		map_node.cell_type_grid if "cell_type_grid" in map_node else PackedByteArray()
	)

	return _build_image(w, h, height_grid, cell_type_grid)


static func generate_image_from_resource(map_resource: MapResource) -> Image:
	"""Build an RGBA8 image from a MapResource."""
	var w := map_resource.size.x
	var h := map_resource.size.y
	return _build_image(w, h, map_resource.height_grid, map_resource.cell_type_grid)


static func _build_image(
	w: int, h: int, height_grid: PackedFloat32Array, cell_type_grid: PackedByteArray
) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(COLOR_GROUND)

	var has_height := height_grid.size() >= w * h
	var has_ct := cell_type_grid.size() >= w * h

	# ---------- pass 1: base colour per cell ----------
	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			var ct: int = cell_type_grid[idx] if has_ct else 0
			var base_color: Color

			match ct:
				MapResource.CELL_WATER:
					base_color = COLOR_WATER
				MapResource.CELL_HIGH_GROUND:
					base_color = COLOR_HIGH_GROUND
				MapResource.CELL_SLOPE:
					base_color = COLOR_SLOPE
				MapResource.CELL_WATER_SLOPE:
					base_color = COLOR_WATER_SLOPE
				_:
					base_color = COLOR_GROUND

			# Subtle height shading — lighten/darken based on elevation
			if has_height:
				var cell_h: float = height_grid[idx]
				# Normalize: ground=0, water≈-0.5, high_ground≈2
				var brightness := clampf(cell_h * 0.06, -0.08, 0.12)
				base_color = base_color.lightened(brightness)

			img.set_pixel(x, y, base_color)

	# ---------- pass 2: cliff / height edges ----------
	if has_height:
		for y in range(h):
			for x in range(w):
				var idx := y * w + x
				var cell_h: float = height_grid[idx]
				var ct: int = cell_type_grid[idx] if has_ct else 0

				# Skip slopes — they're transitional, not cliffs
				if ct == MapResource.CELL_SLOPE or ct == MapResource.CELL_WATER_SLOPE:
					_shade_slope_direction(img, x, y, w, h, height_grid)
					continue

				# Check cardinal neighbours for height discontinuity
				var is_edge := false
				for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var nx: int = x + offset.x
					var ny: int = y + offset.y
					if nx < 0 or nx >= w or ny < 0 or ny >= h:
						continue
					var n_idx := ny * w + nx
					var n_h: float = height_grid[n_idx]
					var n_ct: int = cell_type_grid[n_idx] if has_ct else 0
					# Edge if height differs AND neighbour isn't a slope
					if (
						absf(n_h - cell_h) > 0.1
						and n_ct != MapResource.CELL_SLOPE
						and n_ct != MapResource.CELL_WATER_SLOPE
					):
						is_edge = true
						break

				if is_edge:
					# Darken the pixel to show the cliff edge
					var current := img.get_pixel(x, y)
					img.set_pixel(x, y, current.lerp(COLOR_CLIFF_EDGE, 0.55))

	return img


static func _shade_slope_direction(
	img: Image, x: int, y: int, w: int, h: int, height_grid: PackedFloat32Array
) -> void:
	"""Apply directional shading to a slope cell.
	The downhill side gets slightly darker, uphill slightly lighter,
	giving a visual indication of slope direction."""
	var idx := y * w + x
	var cell_h: float = height_grid[idx]
	var current := img.get_pixel(x, y)

	# Find which direction goes downhill (lowest neighbour)
	var min_dh := 0.0
	var max_dh := 0.0
	for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or nx >= w or ny < 0 or ny >= h:
			continue
		var n_h: float = height_grid[ny * w + nx]
		var dh := n_h - cell_h
		if dh < min_dh:
			min_dh = dh
		if dh > max_dh:
			max_dh = dh

	# Total height range across this slope
	var range_h := max_dh - min_dh
	if range_h > 0.05:
		# Shift colour toward the direction indicator
		# Uphill side of slope → brighten, downhill → darken
		var shade := clampf((max_dh - absf(min_dh)) / range_h * 0.15, -0.12, 0.12)
		img.set_pixel(x, y, current.lightened(shade))
