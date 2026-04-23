extends ResourceDropOffStructure

const HARVESTER_SCENE = preload("res://source/factions/the_legion/units/Harvester.tscn")
const _AUTO_HARVEST_SEARCH_DISTANCE: float = 100000.0

var _spawned_completion_harvester: bool = false


func _ready() -> void:
	super()
	if not constructed.is_connected(_on_refinery_constructed):
		constructed.connect(_on_refinery_constructed)


func _on_refinery_constructed() -> void:
	if _spawned_completion_harvester:
		return
	_spawned_completion_harvester = true
	_spawn_harvester_and_start_harvesting()


func _spawn_harvester_and_start_harvesting() -> void:
	if player == null:
		return
	var harvester_node: Node = HARVESTER_SCENE.instantiate()
	if not (harvester_node is Unit):
		harvester_node.queue_free()
		return
	var harvester: Unit = harvester_node
	var match_node = find_parent("Match")
	var spawn_position: Vector3 = global_position + Vector3(radius + 0.8, 0.0, 0.0)
	if match_node != null and "navigation" in match_node:
		var nav_map_rid: RID = match_node.navigation.get_navigation_map_rid_by_domain(
			harvester.get_nav_domain()
		)
		spawn_position = (
			UnitPlacementUtils
			. find_valid_position_radially_yet_skip_starting_radius(
				global_position,
				radius,
				harvester.radius,
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
			harvester,
			Transform3D(Basis(), spawn_position),
			player,
			false,
		)
	)
	_queue_auto_harvest_command(harvester)


func _queue_auto_harvest_command(harvester: Unit) -> void:
	if harvester == null or not is_instance_valid(harvester):
		return
	var target_resource = ResourceUtils.find_resource_unit_closest_to_unit_yet_no_further_than(
		harvester, _AUTO_HARVEST_SEARCH_DISTANCE
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
							"unit": harvester.id,
							"pos": harvester.global_position,
							"rot": harvester.global_rotation,
						}
					],
					"target_unit": target_resource.id,
				}
			}
		)
	)
