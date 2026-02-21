class_name TextureBrush

extends EditorBrush

## Brush for placing entities

var texture: TerrainType
var rotation: float = 0.0


func _init(
	map_res: MapResource = null,
	symmetry_sys: SymmetrySystem = null,
	cmd_stack: CommandStack = null,
	texture: TerrainType = null,
):
	super._init(map_res, symmetry_sys, cmd_stack)
	texture = texture


func apply(cell_pos: Vector2i):
	if not can_apply(cell_pos):
		return

	if texture.is_empty():
		push_warning("TextureBrush: No texture set")
		return

	var affected_positions = get_affected_positions(cell_pos)

	var cmd = PlaceTextureCommand.new(map_resource, affected_positions, texture, rotation)

	command_stack.push_command(cmd)

	brush_applied.emit(affected_positions)


func set_texture(texture: TerrainType):
	texture = texture


func set_rotation(rot: float):
	rotation = rot


func get_brush_name() -> String:
	if texture.is_empty():
		return "Texture (None Selected)"
	return "Texture: " + texture.name


func get_cursor_color() -> Color:
	return Color.CYAN
