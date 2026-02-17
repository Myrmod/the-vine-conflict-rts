class_name EntityBrush

extends EditorBrush

## Brush for placing entities

var scene_path: String = ""
var player_id: int = 0
var rotation: float = 0.0


func _init(
	map_res: MapResource = null,
	symmetry_sys: SymmetrySystem = null,
	entity_path: String = "",
	player: int = 0
):
	super._init(map_res, symmetry_sys)
	scene_path = entity_path
	player_id = player


func apply(cell_pos: Vector2i):
	print(
		"Applying EntityBrush at ",
		cell_pos,
		" with scene: ",
		scene_path,
		" player: ",
		player_id,
		" rotation: ",
		rotation
	)
	if not can_apply(cell_pos):
		push_warning("EntityBrush: Cannot apply at ", cell_pos, " - out of bounds")
		return

	if scene_path.is_empty():
		push_warning("EntityBrush: No entity scene path set")
		return

	var affected_positions = get_affected_positions(cell_pos)

	for pos in affected_positions:
		# First erase anything at this position
		_erase_at_position(pos)
		# Then place the entity
		map_resource.add_entity(scene_path, pos, player_id, rotation)

	brush_applied.emit(affected_positions)


func _erase_at_position(pos: Vector2i):
	"""Remove any existing entities/units at position before placing"""
	map_resource.placed_entities = map_resource.placed_entities.filter(func(e): return e.pos != pos)
	map_resource.placed_units = map_resource.placed_units.filter(func(u): return u.pos != pos)


func set_entity(path: String):
	scene_path = path


func set_player(player: int):
	player_id = player


func set_rotation(rot: float):
	rotation = rot


func get_brush_name() -> String:
	if scene_path.is_empty():
		return "Entity (None Selected)"
	var entity_name = scene_path.get_file().get_basename()
	return "Entity: " + entity_name


func get_cursor_color() -> Color:
	return Color.CYAN
