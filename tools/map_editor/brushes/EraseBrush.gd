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
	"""Remove any entities and spawn points at the given position"""
	# Remove entities
	map_resource.placed_entities = map_resource.placed_entities.filter(func(s): return s.pos != pos)

	# Remove spawn point at this position
	map_resource.remove_spawn_point(pos)


func get_brush_name() -> String:
	return "Erase"


func get_cursor_color() -> Color:
	return Color.ORANGE_RED
