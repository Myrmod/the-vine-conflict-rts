class_name SlopeBrush

extends EditorBrush

## Brush for painting slopes between height levels.
## Slopes interpolate the height from neighbouring cells and
## remove collision so units can walk across the transition.
## Set `is_water_slope` to tag the cell as CELL_WATER_SLOPE instead.

var is_water_slope: bool = false


func _init(
	map_res: MapResource = null,
	symmetry_sys: SymmetrySystem = null,
	cmd_stack: CommandStack = null,
	water_slope: bool = false,
):
	super._init(map_res, symmetry_sys, cmd_stack)
	is_water_slope = water_slope


func apply(cell_pos: Vector2i) -> void:
	if not can_apply(cell_pos):
		return

	var affected_positions: Array[Vector2i] = get_affected_positions(cell_pos)

	var cmd: PaintSlopeCommand = PaintSlopeCommand.new(
		map_resource, affected_positions, is_water_slope
	)
	command_stack.push_command(cmd)

	brush_applied.emit(affected_positions)


func get_brush_name() -> String:
	if is_water_slope:
		return "Water Slope Brush"
	return "Slope Brush"


func get_cursor_color() -> Color:
	if is_water_slope:
		return Color(0.2, 0.8, 0.8, 0.8)
	return Color(0.9, 0.7, 0.2, 0.8)
