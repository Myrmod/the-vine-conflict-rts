extends EditorBrush
class_name UnitBrush

## Brush for placing units

var scene_path: String = ""
var player_id: int = 0
var rotation: float = 0.0


func _init(map_res: MapResource = null, symmetry_sys: SymmetrySystem = null, unit_path: String = "", player: int = 0):
	super._init(map_res, symmetry_sys)
	scene_path = unit_path
	player_id = player


func apply(cell_pos: Vector2i):
	if not can_apply(cell_pos):
		return
	
	if scene_path.is_empty():
		push_warning("UnitBrush: No unit scene path set")
		return
	
	var affected_positions = get_affected_positions(cell_pos)
	
	for pos in affected_positions:
		# First erase any units at this position
		_erase_at_position(pos)
		# Then place the unit
		map_resource.add_unit(scene_path, pos, player_id, rotation)
	
	brush_applied.emit(affected_positions)


func _erase_at_position(pos: Vector2i):
	"""Remove any existing units at position before placing"""
	map_resource.placed_units = map_resource.placed_units.filter(
		func(u): return u.pos != pos
	)


func set_unit(path: String):
	scene_path = path


func set_player(player: int):
	player_id = player


func set_rotation(rot: float):
	rotation = rot


func get_brush_name() -> String:
	if scene_path.is_empty():
		return "Unit (None Selected)"
	var unit_name = scene_path.get_file().get_basename()
	return "Unit: " + unit_name


func get_cursor_color() -> Color:
	return Color.YELLOW
