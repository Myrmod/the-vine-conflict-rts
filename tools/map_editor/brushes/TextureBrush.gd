class_name TextureBrush

extends EditorBrush

## Brush for placing entities

enum AlphaMode { SOLID, SOFT, AIRBRUSH }

var texture: TerrainType
var rotation: float = 0.0
var alpha_mode: AlphaMode = AlphaMode.SOFT


func _init(
	map_res: MapResource = null,
	symmetry_sys: SymmetrySystem = null,
	cmd_stack: CommandStack = null,
	_texture: TerrainType = null,
):
	super._init(map_res, symmetry_sys, cmd_stack)
	texture = _texture


func apply(cell_pos: Vector2i):
	if not can_apply(cell_pos):
		return

	if not texture:
		push_warning("TextureBrush: No texture set")
		return

	var affected_positions = get_affected_positions(cell_pos)

	var cmd = PlaceTextureCommand.new(
		map_resource, affected_positions, texture, rotation, cell_pos, self
	)

	command_stack.push_command(cmd)

	# Notify editor AFTER command executes
	brush_applied.emit(affected_positions)


func set_texture(_texture: TerrainType):
	texture = _texture


func set_rotation(rot: float):
	rotation = rot


func set_alpha_mode(mode: AlphaMode) -> void:
	alpha_mode = mode


func get_edge_falloff(cell_pos: Vector2i, center: Vector2i) -> float:
	var effective_radius: float = maxf(brush_size + 0.5, 0.5)
	var offset: Vector2 = Vector2(float(cell_pos.x - center.x), float(cell_pos.y - center.y))
	var distance: float = 0.0

	if brush_shape == BrushShape.CIRCLE:
		distance = offset.length()
	else:
		distance = maxf(absf(offset.x), absf(offset.y))

	var normalized_distance: float = clampf(distance / effective_radius, 0.0, 1.0)

	match alpha_mode:
		AlphaMode.SOLID:
			return 1.0 if normalized_distance <= 1.0 else 0.0
		AlphaMode.SOFT:
			var soft_t: float = (
				normalized_distance * normalized_distance * (3.0 - 2.0 * normalized_distance)
			)
			return 1.0 - soft_t
		AlphaMode.AIRBRUSH:
			return exp(-4.0 * normalized_distance * normalized_distance)

	return 1.0


func get_brush_name() -> String:
	if not texture:
		return "Texture (None Selected)"
	return "Texture: %s [%s]" % [texture.name, _get_alpha_mode_name()]


func get_cursor_color() -> Color:
	return Color.CYAN


func _get_alpha_mode_name() -> String:
	match alpha_mode:
		AlphaMode.SOLID:
			return "Solid"
		AlphaMode.SOFT:
			return "Soft"
		AlphaMode.AIRBRUSH:
			return "Airbrush"
	return "Unknown"
