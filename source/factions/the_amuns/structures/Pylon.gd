extends "res://source/factions/the_amuns/AmunResourceDropOffStructure.gd"

const SYPHON_DRONE_SCENE = preload("res://source/factions/the_amuns/units/SyphonDrone.tscn")
const _AUTO_HARVEST_SEARCH_DISTANCE: float = 100000.0

var _spawned_completion_drone: bool = false


func _ready() -> void:
	super()
	if not constructed.is_connected(_on_syphon_constructed):
		constructed.connect(_on_syphon_constructed)


func _on_syphon_constructed() -> void:
	if _spawned_completion_drone:
		return
	_spawned_completion_drone = true
	_spawn_drone_and_start_harvesting()


func _spawn_drone_and_start_harvesting() -> void:
	if player == null:
		return
	var drone_node: Node = SYPHON_DRONE_SCENE.instantiate()
	if not (drone_node is Unit):
		drone_node.queue_free()
		return
	var drone: Unit = drone_node
	var match_node = find_parent("Match")
	var spawn_position: Vector3 = global_position + Vector3(radius + 0.8, 0.0, 0.0)
	if match_node != null and "navigation" in match_node:
		var nav_map_rid: RID = match_node.navigation.get_navigation_map_rid_by_domain(
			drone.get_nav_domain()
		)
		spawn_position = (
			UnitPlacementUtils
			. find_valid_position_radially_yet_skip_starting_radius(
				global_position,
				radius,
				drone.radius,
				0.1,
				Vector3(0, 0, 1),
				false,
				nav_map_rid,
				get_tree(),
			)
		)
	(
		MatchSignals
		. setup_and_spawn_unit
		. emit(
			drone,
			Transform3D(Basis(), spawn_position),
			player,
			false,
		)
	)
	_queue_auto_harvest_command(drone)


func _queue_auto_harvest_command(drone: Unit) -> void:
	if drone == null or not is_instance_valid(drone):
		return
	var target_resource = ResourceUtils.find_resource_unit_closest_to_unit_yet_no_further_than(
		drone, _AUTO_HARVEST_SEARCH_DISTANCE
	)
	if target_resource == null or not is_instance_valid(target_resource):
		return
	(
		CommandBus
		. push_command(
			{
				"tick": Match.tick + 1,
				"type": Enums.CommandType.COLLECTING_RESOURCES_SEQUENTIALLY,
				"player_id": player.id,
				"data":
				{
					"targets":
					[
						{
							"unit": drone.id,
							"pos": drone.global_position,
							"rot": drone.global_rotation,
						}
					],
					"target_unit": target_resource.id,
				}
			}
		)
	)
