extends "res://source/factions/the_amuns/AmunStructure.gd"

const _SPAWNER_LINK_RADIUS: float = 0.75

@export var requires_resource_spawner: bool = true
@export var resource_spawner_height_offset: float = 1.8
@export var resource_vine_capacity_bonus: int = 250

var _linked_spawner: ResourceSpawner = null


func _ready() -> void:
	# This structure sits above a spawner and should not claim ground occupancy cells.
	_footprint = Vector2i(0, 0)
	super()
	_link_to_resource_spawner()
	_apply_bonus_to_existing_vines()


func _exit_tree() -> void:
	_remove_spawner_bonus()
	super()


func _link_to_resource_spawner() -> void:
	_linked_spawner = _find_spawner_below()
	if _linked_spawner == null:
		return
	_linked_spawner.resource_capacity_bonus += resource_vine_capacity_bonus


func _remove_spawner_bonus() -> void:
	if _linked_spawner == null or not is_instance_valid(_linked_spawner):
		return
	_linked_spawner.resource_capacity_bonus = maxi(
		0, _linked_spawner.resource_capacity_bonus - resource_vine_capacity_bonus
	)


func _find_spawner_below() -> ResourceSpawner:
	var best: ResourceSpawner = null
	var best_dist_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("resource_spawners"):
		if UnitConstants.get_scene_id(node.scene_file_path) != Enums.SceneId.NEUTRAL_RESOURCE_SPAWNER:
			continue
		if not (node is ResourceSpawner):
			continue
		var dist_sq: float = node.global_position_yless.distance_squared_to(global_position_yless)
		if dist_sq > (_SPAWNER_LINK_RADIUS * _SPAWNER_LINK_RADIUS):
			continue
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = node
	return best


func _apply_bonus_to_existing_vines() -> void:
	if _linked_spawner == null:
		return
	for node: Node in get_tree().get_nodes_in_group("resource_units"):
		if UnitConstants.get_scene_id(node.scene_file_path) != Enums.SceneId.NEUTRAL_RESOURCE_VINE:
			continue
		var vine: ResourceVine = node as ResourceVine
		if vine == null:
			continue
		var dist_sq: float = vine.global_position_yless.distance_squared_to(
			_linked_spawner.global_position_yless
		)
		if dist_sq > (ResourceSpawner.SPAWN_RADIUS * ResourceSpawner.SPAWN_RADIUS):
			continue
		var boosted_max: int = (vine.tile_count * vine.resources_per_tile) + resource_vine_capacity_bonus
		if boosted_max <= vine.resource_max:
			continue
		var delta: int = boosted_max - vine.resource_max
		vine.resource_max = boosted_max
		vine.resource += delta