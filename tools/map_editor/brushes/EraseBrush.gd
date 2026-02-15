extends EditorBrush
class_name EraseBrush

## Brush for erasing entities (structures, units, resources) at a position


func apply(cell_pos: Vector2i):
	if not can_apply(cell_pos):
		return
	
	var affected_positions = get_affected_positions(cell_pos)
	
	for pos in affected_positions:
		_erase_at_position(pos)
	
	brush_applied.emit(affected_positions)


func _erase_at_position(pos: Vector2i):
	"""Remove any entities at the given position"""
	# Remove structures
	map_resource.placed_structures = map_resource.placed_structures.filter(
		func(s): return s.pos != pos
	)
	
	# Remove units
	map_resource.placed_units = map_resource.placed_units.filter(
		func(u): return u.pos != pos
	)
	
	# Remove resources
	map_resource.resource_nodes = map_resource.resource_nodes.filter(
		func(r): return r.pos != pos
	)
	
	# Remove cosmetics
	map_resource.cosmetic_tiles = map_resource.cosmetic_tiles.filter(
		func(c): return c.pos != pos
	)


func get_brush_name() -> String:
	return "Erase"


func get_cursor_color() -> Color:
	return Color.ORANGE_RED
