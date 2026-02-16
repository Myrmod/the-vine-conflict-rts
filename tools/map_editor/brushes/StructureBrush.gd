class_name StructureBrush

extends EditorBrush

## Brush for placing structures

var scene_path: String = ""
var player_id: int = 0
var rotation: float = 0.0


func _init(
	map_res: MapResource = null,
	symmetry_sys: SymmetrySystem = null,
	structure_path: String = "",
	player: int = 0
):
	super._init(map_res, symmetry_sys)
	scene_path = structure_path
	player_id = player


func apply(cell_pos: Vector2i):
	if not can_apply(cell_pos):
		return

	if scene_path.is_empty():
		push_warning("StructureBrush: No structure scene path set")
		return

	var affected_positions = get_affected_positions(cell_pos)

	for pos in affected_positions:
		# First erase anything at this position
		_erase_at_position(pos)
		# Then place the structure
		map_resource.add_structure(scene_path, pos, player_id, rotation)

	brush_applied.emit(affected_positions)


func _erase_at_position(pos: Vector2i):
	"""Remove any existing structures/units at position before placing"""
	map_resource.placed_structures = map_resource.placed_structures.filter(
		func(s): return s.pos != pos
	)
	map_resource.placed_units = map_resource.placed_units.filter(func(u): return u.pos != pos)


func set_structure(path: String):
	scene_path = path


func set_player(player: int):
	player_id = player


func set_rotation(rot: float):
	rotation = rot


func get_brush_name() -> String:
	if scene_path.is_empty():
		return "Structure (None Selected)"
	var structure_name = scene_path.get_file().get_basename()
	return "Structure: " + structure_name


func get_cursor_color() -> Color:
	return Color.CYAN
