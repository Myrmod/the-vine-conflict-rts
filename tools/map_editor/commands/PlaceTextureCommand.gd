class_name PlaceTextureCommand
extends EditorCommand

var map_resource: MapResource
var positions: Array[Vector2i]
var terrain_id: int
var strength: float = 1.0
var center: Vector2i  ## Brush center for falloff calculation
var brush_ref: EditorBrush  ## Reference to brush for falloff lookup

var previous_weights := []


func _init(
	map_res,
	_positions,
	texture: TerrainType,
	_rotation,
	_center := Vector2i.ZERO,
	_brush: EditorBrush = null
):
	map_resource = map_res
	positions = _positions
	terrain_id = texture.id
	center = _center
	brush_ref = _brush


func execute():
	previous_weights.clear()

	for pos in positions:
		var px = pos.x
		var py = pos.y

		var backup := []

		# Store old values
		for s in range(map_resource.splatmaps.size()):
			var pixel = map_resource.splatmaps[s].get_pixel(px, py)
			backup.append(pixel)

		previous_weights.append(backup)

		# Compute per-cell strength using edge falloff
		var cell_strength = strength
		if brush_ref:
			var falloff = brush_ref.get_edge_falloff(pos, center)
			if falloff < 1.0:
				if _pixel_dominant_terrain(px, py) == terrain_id:
					falloff = 1.0
			cell_strength *= falloff
		if cell_strength <= 0.001:
			continue

		# Instead of additive blending, lerp all channels toward the
		# target state (target=1.0, everything else=0.0).
		# At full strength the painted texture completely replaces the base.
		for s in range(map_resource.splatmaps.size()):
			var img = map_resource.splatmaps[s]
			var col = img.get_pixel(px, py)

			# Determine the target value for each channel in this splatmap
			var target_r = 1.0 if (s * 4 + 0 == terrain_id) else 0.0
			var target_g = 1.0 if (s * 4 + 1 == terrain_id) else 0.0
			var target_b = 1.0 if (s * 4 + 2 == terrain_id) else 0.0
			var target_a = 1.0 if (s * 4 + 3 == terrain_id) else 0.0

			col.r = lerpf(col.r, target_r, cell_strength)
			col.g = lerpf(col.g, target_g, cell_strength)
			col.b = lerpf(col.b, target_b, cell_strength)
			col.a = lerpf(col.a, target_a, cell_strength)

			img.set_pixel(px, py, col)


func _pixel_dominant_terrain(px: int, py: int) -> int:
	"""Return the terrain index with the highest weight at this pixel."""
	var best_idx := -1
	var best_val := 0.0

	for s in range(map_resource.splatmaps.size()):
		var c = map_resource.splatmaps[s].get_pixel(px, py)
		var base = s * 4
		var channels := [c.r, c.g, c.b, c.a]
		for ch in range(4):
			if channels[ch] > best_val:
				best_val = channels[ch]
				best_idx = base + ch

	return best_idx


func undo():
	for i in range(positions.size()):
		var pos = positions[i]
		var backup = previous_weights[i]

		for s in range(map_resource.splatmaps.size()):
			map_resource.splatmaps[s].set_pixel(pos.x, pos.y, backup[s])
