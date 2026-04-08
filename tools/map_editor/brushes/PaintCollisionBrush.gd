class_name PaintCollisionBrush

extends EditorBrush

## Brush for painting collision tiles (blocked/walkable)

var paint_value: int = 1  # 1 = blocked, 0 = walkable


func _init(map_res: MapResource = null, symmetry_sys: SymmetrySystem = null, value: int = 1):
	super._init(map_res, symmetry_sys)
	paint_value = value


func apply(cell_pos: Vector2i):
	if not can_apply(cell_pos):
		return

	var affected_positions = get_affected_positions(cell_pos)

	for pos in affected_positions:
		map_resource.set_collision_at(pos, paint_value)

	brush_applied.emit(affected_positions)


func get_brush_name() -> String:
	if paint_value == 1:
		return "Paint Collision (Block)"
	else:
		return "Paint Collision (Clear)"


func get_cursor_color() -> Color:
	if paint_value == 1:
		return Color.RED
	else:
		return Color.GREEN
