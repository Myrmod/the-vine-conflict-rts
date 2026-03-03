class_name SpawnBrush

extends EditorBrush

## Brush for placing player spawn points on the map


func apply(cell_pos: Vector2i):
	if not can_apply(cell_pos):
		return

	# Get all positions (including symmetry mirrors)
	var positions: Array[Vector2i] = get_affected_positions(cell_pos)

	for pos in positions:
		var cmd = PlaceSpawnCommand.new(map_resource, pos)
		command_stack.push_command(cmd)

	brush_applied.emit(positions)


func is_single_placement() -> bool:
	return true


func get_brush_name() -> String:
	var count = map_resource.spawn_points.size() if map_resource else 0
	return "Spawn Point (%d placed)" % count


func get_cursor_color() -> Color:
	return Color.YELLOW


func _build_footprint(center: Vector2i) -> Array[Vector2i]:
	return [center]
