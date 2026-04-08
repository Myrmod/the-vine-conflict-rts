class_name EditorBrush

extends RefCounted

## Base class for all editor brushes
## Brushes handle painting/placing operations on the map

signal brush_applied(positions: Array[Vector2i])

enum BrushShape { CIRCLE, SQUARE }

var map_resource: MapResource
var symmetry_system: SymmetrySystem
var command_stack: CommandStack

## Brush footprint settings
var brush_size: float = 0.0  # radius in cells (0 = single cell, 1 = 3×3, etc.)
var brush_shape: BrushShape = BrushShape.CIRCLE


func _init(
	map_res: MapResource = null, symmetry_sys: SymmetrySystem = null, cmd_stack: CommandStack = null
):
	map_resource = map_res
	symmetry_system = symmetry_sys
	command_stack = cmd_stack


func apply(_cell_pos: Vector2i):
	"""Apply brush at the given cell position. Override in subclasses."""
	push_error("EditorBrush.apply() must be overridden")


func can_apply(cell_pos: Vector2i) -> bool:
	"""Check if brush can be applied at position. Override for custom logic."""
	return map_resource != null and _is_in_bounds(cell_pos)


func _is_in_bounds(pos: Vector2i) -> bool:
	if map_resource == null:
		return false
	return pos.x >= 0 and pos.x < map_resource.size.x and pos.y >= 0 and pos.y < map_resource.size.y


func get_affected_positions(cell_pos: Vector2i) -> Array[Vector2i]:
	"""Get all positions that will be affected by this brush (includes size, shape & symmetry)"""
	# 1. Build footprint around center based on shape & size
	var footprint: Array[Vector2i] = _build_footprint(cell_pos)

	# 2. Apply symmetry to every cell in the footprint
	var all_positions: Array[Vector2i] = []
	for pos in footprint:
		if symmetry_system:
			var sym_positions = symmetry_system.get_symmetric_positions(pos)
			for sp in sym_positions:
				if _is_in_bounds(sp) and not all_positions.has(sp):
					all_positions.append(sp)
		else:
			if _is_in_bounds(pos) and not all_positions.has(pos):
				all_positions.append(pos)

	return all_positions


func _build_footprint(center: Vector2i) -> Array[Vector2i]:
	"""Build array of cell positions for the current brush shape and size."""
	var positions: Array[Vector2i] = []

	if brush_size <= 0.0:
		positions.append(center)
		return positions

	var effective_radius: float = brush_size + 0.5
	var radius_cells: int = ceili(effective_radius)
	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var p = Vector2i(center.x + dx, center.y + dy)

			if brush_shape == BrushShape.CIRCLE:
				var offset: Vector2 = Vector2(float(dx), float(dy))
				if offset.length() > effective_radius:
					continue
			else:
				var max_offset: float = maxf(absf(float(dx)), absf(float(dy)))
				if max_offset > effective_radius:
					continue

			# Square: all cells in the rectangle are included
			positions.append(p)

	return positions


func _build_footprint_f(center_f: Vector2) -> Array[Vector2i]:
	"""Like _build_footprint but with a sub-cell float center (in cell-space units).
	Cells are included when their center (cell + 0.5) is within effective_radius of center_f."""
	var positions: Array[Vector2i] = []
	var effective_radius: float = brush_size + 0.5
	var radius_cells: int = ceili(effective_radius) + 1
	var cx: int = int(floor(center_f.x))
	var cy: int = int(floor(center_f.y))
	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var p := Vector2i(cx + dx, cy + dy)
			var cell_center_f := Vector2(float(p.x) + 0.5, float(p.y) + 0.5)
			var offset := cell_center_f - center_f
			if brush_shape == BrushShape.CIRCLE:
				if offset.length() > effective_radius:
					continue
			else:
				if maxf(absf(offset.x), absf(offset.y)) > effective_radius:
					continue
			positions.append(p)
	return positions


func get_affected_positions_f(center_f: Vector2) -> Array[Vector2i]:
	"""Float-center version of get_affected_positions. center_f is in cell-space units."""
	var footprint: Array[Vector2i] = _build_footprint_f(center_f)
	var all_positions: Array[Vector2i] = []
	for pos in footprint:
		if symmetry_system:
			var sym_positions: Array[Vector2i] = symmetry_system.get_symmetric_positions(pos)
			for sp in sym_positions:
				if _is_in_bounds(sp) and not all_positions.has(sp):
					all_positions.append(sp)
		else:
			if _is_in_bounds(pos) and not all_positions.has(pos):
				all_positions.append(pos)
	return all_positions


func get_edge_falloff(_cell_pos: Vector2i, _center: Vector2i) -> float:
	"""Returns 1.0 for all cells — no edge falloff."""
	return 1.0


func get_edge_falloff_f(cell_pos: Vector2i, center_f: Vector2) -> float:
	"""Float-center falloff. Base delegates to integer version."""
	return get_edge_falloff(cell_pos, Vector2i(int(floor(center_f.x)), int(floor(center_f.y))))


func is_single_placement() -> bool:
	"""Return true if this brush places a discrete item per click (no drag-painting)."""
	return false


func get_brush_name() -> String:
	"""Get display name for this brush"""
	return "Base Brush"


func get_cursor_color() -> Color:
	"""Get color for brush cursor preview"""
	return Color.WHITE
