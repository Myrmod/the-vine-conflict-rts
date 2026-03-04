class_name PlaceEntityCommand

extends EditorCommand

## Command for placing entities (structures, units, resources) with undo support

var map_resource: MapResource
var positions: Array[Vector2i]
var scene_path: String
var player_id: int
var rotation: float

# For undo: store what was at these positions before
var removed_entities: Array[Dictionary] = []


func _init(
	map_res: MapResource,
	affected_positions: Array[Vector2i],
	path: String,
	player: int,
	rot: float = 0.0
):
	map_resource = map_res
	positions = affected_positions.duplicate()
	scene_path = path
	player_id = player
	rotation = rot

	# Store what will be removed for undo
	_store_removed_entities()

	description = "Place entity (%d positions)" % [positions.size()]


func _store_removed_entities():
	"""Store entities that will be removed for undo"""
	for pos in positions:
		var removed_at_pos = []

		# Check for existing entities
		for entity in map_resource.placed_entities:
			if entity.pos == pos:
				removed_at_pos.append({"type": "entity", "data": entity.duplicate()})

		removed_entities.append({"pos": pos, "entities": removed_at_pos})


func execute():
	for pos in positions:
		# Remove existing entities at position
		map_resource.placed_entities = map_resource.placed_entities.filter(
			func(u): return u.pos != pos
		)

		# Place new entity
		map_resource.add_entity(scene_path, pos, player_id, rotation)


func undo():
	# Remove placed entities
	for pos in positions:
		map_resource.placed_entities = map_resource.placed_entities.filter(
			func(u): return u.pos != pos
		)

	# Restore removed entities
	for item in removed_entities:
		for entity in item.entities:
			map_resource.placed_entities.append(entity.data)
