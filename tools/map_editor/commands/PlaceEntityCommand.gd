class_name PlaceEntityCommand

extends EditorCommand

## Command for placing entities (structures, units, resources) with undo support

var map_resource: MapResource
var entity_type: String  # "structure", "unit", "resource"
var positions: Array[Vector2i]
var scene_path: String
var player_id: int
var rotation: float

# For undo: store what was at these positions before
var removed_entities: Array[Dictionary] = []


func _init(
	map_res: MapResource,
	type: String,
	affected_positions: Array[Vector2i],
	path: String,
	player: int,
	rot: float = 0.0
):
	map_resource = map_res
	entity_type = type
	positions = affected_positions.duplicate()
	scene_path = path
	player_id = player
	rotation = rot

	# Store what will be removed for undo
	_store_removed_entities()

	description = "Place %s (%d positions)" % [type, positions.size()]


func _store_removed_entities():
	"""Store entities that will be removed for undo"""
	for pos in positions:
		var removed_at_pos = []

		# Check for existing structures
		for structure in map_resource.placed_structures:
			if structure.pos == pos:
				removed_at_pos.append({"type": "structure", "data": structure.duplicate()})

		# Check for existing units
		for unit in map_resource.placed_units:
			if unit.pos == pos:
				removed_at_pos.append({"type": "unit", "data": unit.duplicate()})

		# Check for existing resources
		for resource in map_resource.resource_nodes:
			if resource.pos == pos:
				removed_at_pos.append({"type": "resource", "data": resource.duplicate()})

		removed_entities.append({"pos": pos, "entities": removed_at_pos})


func execute():
	for pos in positions:
		# Remove existing entities at position
		map_resource.placed_structures = map_resource.placed_structures.filter(
			func(s): return s.pos != pos
		)
		map_resource.placed_units = map_resource.placed_units.filter(func(u): return u.pos != pos)
		if entity_type != "resource":
			map_resource.resource_nodes = map_resource.resource_nodes.filter(
				func(r): return r.pos != pos
			)

		# Place new entity
		match entity_type:
			"structure":
				map_resource.add_structure(scene_path, pos, player_id, rotation)
			"unit":
				map_resource.add_unit(scene_path, pos, player_id, rotation)
			"resource":
				map_resource.add_resource_node(scene_path, pos)


func undo():
	# Remove placed entities
	for pos in positions:
		map_resource.placed_structures = map_resource.placed_structures.filter(
			func(s): return s.pos != pos
		)
		map_resource.placed_units = map_resource.placed_units.filter(func(u): return u.pos != pos)
		map_resource.resource_nodes = map_resource.resource_nodes.filter(
			func(r): return r.pos != pos
		)

	# Restore removed entities
	for item in removed_entities:
		for entity in item.entities:
			match entity.type:
				"structure":
					map_resource.placed_structures.append(entity.data)
				"unit":
					map_resource.placed_units.append(entity.data)
				"resource":
					map_resource.resource_nodes.append(entity.data)
