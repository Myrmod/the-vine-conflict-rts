class_name PlaceEntityCommand

extends EditorCommand

## Command for placing entities (structures, units, resources) with undo support

var map_resource: MapResource
var positions: Array[Vector2i]
var scene_path: String
var player_id: int
var rotation: float
var entity_scale: float
var material_path: String
var free_position: Variant = null  # Vector2 when free-placed, null otherwise

# For undo: store what was at these positions before
var removed_entities: Array[Dictionary] = []


func _init(
	map_res: MapResource,
	affected_positions: Array[Vector2i],
	path: String,
	player: int,
	rot: float = 0.0,
	scl: float = 1.0,
	mat_path: String = ""
):
	map_resource = map_res
	positions = affected_positions.duplicate()
	scene_path = path
	player_id = player
	rotation = rot
	entity_scale = scl
	material_path = mat_path

	# Store what will be removed for undo
	_store_removed_entities()

	if free_position != null:
		description = "Place entity (free)"
	else:
		description = "Place entity (%d positions)" % [positions.size()]


func _store_removed_entities():
	"""Store entities that will be removed for undo"""
	if free_position != null:
		# Free placement: store entities at the exact same float position
		var removed_at_pos = []
		for entity in map_resource.placed_entities:
			if entity.pos is Vector2 and entity.pos.is_equal_approx(free_position):
				removed_at_pos.append({"type": "entity", "data": entity.duplicate()})
		removed_entities.append({"pos": free_position, "entities": removed_at_pos})
		return

	for pos in positions:
		var removed_at_pos = []

		# Check for existing entities
		for entity in map_resource.placed_entities:
			if entity.pos == pos:
				removed_at_pos.append({"type": "entity", "data": entity.duplicate()})

		removed_entities.append({"pos": pos, "entities": removed_at_pos})


func execute():
	if free_position != null:
		# Free placement: remove entities at the exact float position, then add
		var fp = free_position
		map_resource.placed_entities = map_resource.placed_entities.filter(
			func(u): return not (u.pos is Vector2 and u.pos.is_equal_approx(fp))
		)
		map_resource.add_entity_free(
			scene_path, free_position, player_id, rotation, entity_scale, material_path
		)
		return

	for pos in positions:
		# Remove existing entities at position
		map_resource.placed_entities = map_resource.placed_entities.filter(
			func(u): return u.pos != pos
		)

		# Place new entity
		map_resource.add_entity(scene_path, pos, player_id, rotation, entity_scale, material_path)


func undo():
	if free_position != null:
		# Free placement: remove the free-placed entity
		var fp = free_position
		map_resource.placed_entities = map_resource.placed_entities.filter(
			func(u): return not (u.pos is Vector2 and u.pos.is_equal_approx(fp))
		)
	else:
		# Remove placed entities
		for pos in positions:
			map_resource.placed_entities = map_resource.placed_entities.filter(
				func(u): return u.pos != pos
			)

	# Restore removed entities
	for item in removed_entities:
		for entity in item.entities:
			map_resource.placed_entities.append(entity.data)
