class_name HeightBrush

extends EditorBrush

## Brush for painting terrain height levels
## Supports 3 levels: WATER (-1), GROUND (0), HIGH_GROUND (1) as defined in the Enums / Constants
## Automatically sets collision for non-ground levels (water & high ground are blocked).
## Slopes override this collision later.

var height_level: Enums.HeightLevel = Enums.HeightLevel.GROUND
var auto_collision: bool = true  ## auto-block non-ground cells


func _init(
	map_res: MapResource = null,
	symmetry_sys: SymmetrySystem = null,
	cmd_stack: CommandStack = null,
	level: Enums.HeightLevel = Enums.HeightLevel.GROUND
):
	super._init(map_res, symmetry_sys, cmd_stack)
	height_level = level


func apply(cell_pos: Vector2i):
	if not can_apply(cell_pos):
		return

	var affected_positions = get_affected_positions(cell_pos)
	var world_height: float = Constants.LEVEL_HEIGHTS[height_level]

	var cmd = PaintHeightCommand.new(
		map_resource, affected_positions, world_height, height_level, auto_collision
	)
	command_stack.push_command(cmd)

	brush_applied.emit(affected_positions)


func set_level(level: Enums.HeightLevel):
	height_level = level


func get_brush_name() -> String:
	match height_level:
		Enums.HeightLevel.WATER:
			return "Height: Water"
		Enums.HeightLevel.GROUND:
			return "Height: Ground"
		Enums.HeightLevel.HIGH_GROUND:
			return "Height: High Ground"
	return "Height Brush"


func get_cursor_color() -> Color:
	match height_level:
		Enums.HeightLevel.WATER:
			return Color(0.2, 0.4, 0.9, 0.8)
		Enums.HeightLevel.GROUND:
			return Color(0.4, 0.8, 0.3, 0.8)
		Enums.HeightLevel.HIGH_GROUND:
			return Color(0.7, 0.5, 0.2, 0.8)
	return Color.WHITE
