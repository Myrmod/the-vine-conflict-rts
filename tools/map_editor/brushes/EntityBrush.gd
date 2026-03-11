class_name EntityBrush

extends EditorBrush

## Brush for placing entities
## Blocks placement on terrain types not listed in the entity's
## placement_domains (structures) or movement_domains (units).

var scene_path: String = ""
var player_id: int = 0
var rotation: float = 0.0
var entity_scale: float = 1.0
var material_path: String = ""

# Cached placement domains from the loaded scene
var _placement_domains: Array = []


func _init(
	map_res: MapResource = null,
	symmetry_sys: SymmetrySystem = null,
	cmd_stack: CommandStack = null,
	entity_path: String = "",
	player: int = 0
):
	super._init(map_res, symmetry_sys, cmd_stack)
	scene_path = entity_path
	player_id = player
	_refresh_placement_domains()


func apply(cell_pos: Vector2i):
	if not can_apply(cell_pos):
		return

	if scene_path.is_empty():
		push_warning("EntityBrush: No entity scene path set")
		return

	# Validate terrain type at target cell
	if map_resource:
		var cell_type = map_resource.get_cell_type_at(cell_pos)
		if (
			cell_type == MapResource.CELL_SLOPE
			and Enums.PlacementTypes.SLOPE not in _placement_domains
		):
			push_warning("Cannot place entity on a slope (entity does not allow slope placement)")
			return
		if (
			cell_type == MapResource.CELL_WATER
			and Enums.PlacementTypes.WATER not in _placement_domains
		):
			push_warning("Cannot place entity on water (entity does not allow water placement)")
			return

	var affected_positions = get_affected_positions(cell_pos)

	var cmd = PlaceEntityCommand.new(
		map_resource,
		affected_positions,
		scene_path,
		player_id,
		rotation,
		entity_scale,
		material_path
	)

	command_stack.push_command(cmd)

	brush_applied.emit(affected_positions)


func set_entity(path: String):
	scene_path = path
	_refresh_placement_domains()


func set_player(player: int):
	player_id = player


func set_rotation(rot: float):
	rotation = rot


func set_entity_scale(s: float):
	entity_scale = s


func set_material_path(path: String):
	material_path = path


func _refresh_placement_domains():
	"""Check the entity scene for placement_domains (structures) or movement_domains (units)."""
	_placement_domains = []

	if scene_path.is_empty():
		return

	var packed = load(scene_path)
	if not packed:
		return

	var inst = packed.instantiate()
	if inst.get("placement_domains") != null:
		_placement_domains = Array(inst.placement_domains)
	elif inst.get("movement_domains") != null:
		# Map MovementTypes to PlacementTypes for consistent checking
		for mt in inst.movement_domains:
			match mt:
				Enums.MovementTypes.LAND:
					if Enums.PlacementTypes.LAND not in _placement_domains:
						_placement_domains.append(Enums.PlacementTypes.LAND)
				Enums.MovementTypes.WATER:
					if Enums.PlacementTypes.WATER not in _placement_domains:
						_placement_domains.append(Enums.PlacementTypes.WATER)
				Enums.MovementTypes.AIR:
					# Air units can be placed anywhere
					_placement_domains.append(Enums.PlacementTypes.LAND)
					_placement_domains.append(Enums.PlacementTypes.WATER)
					_placement_domains.append(Enums.PlacementTypes.SLOPE)
	inst.queue_free()


func is_single_placement() -> bool:
	return true


func get_brush_name() -> String:
	if scene_path.is_empty():
		return "Entity (None Selected)"
	var entity_name = scene_path.get_file().get_basename()
	var rot_deg := int(rad_to_deg(rotation)) % 360
	if is_equal_approx(entity_scale, 1.0):
		return "Entity: %s  rot: %d°" % [entity_name, rot_deg]
	return "Entity: %s  rot: %d°  scale: %.1f" % [entity_name, rot_deg, entity_scale]


func get_cursor_color() -> Color:
	return Color.CYAN


func _build_footprint(center: Vector2i) -> Array[Vector2i]:
	return [center]
