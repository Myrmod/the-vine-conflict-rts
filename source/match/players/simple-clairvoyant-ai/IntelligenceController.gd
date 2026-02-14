# AI DECISION SYSTEM: Manages individual unit AI behavior for the Clairvoyant AI player type.
# Handles scouting drones and their movement targets. While AutoAttackingBattlegroup handles
# coordinated attack formations, IntelligenceController handles exploratory/scouting behaviors.
# TEAM AWARENESS: Only targets enemy teams (player.team != _player.team) preventing friendly fire.
#
# DETERMINISM: Drone re-targeting delays are measured in TICKS (not wall-clock time) so that
# the same commands are pushed at the same tick during replay. The global seeded RNG is used
# to choose the delay length (5–10 ticks = 0.5–1.0 s at TICK_RATE 10).
extends Node

# Delay range in ticks before a drone picks a new scouting target.
# At TICK_RATE 10, 5 ticks = 0.5 s, 10 ticks = 1.0 s.
const TARGET_SWITCHING_DELAY_MIN_TICKS = 5
const TARGET_SWITCHING_DELAY_MAX_TICKS = 10

const MovingToUnitAction = preload("res://source/match/units/actions/MovingToUnit.gd")

const Drone = preload("res://source/match/units/Drone.gd")

var _player = null
var _blacklisted_drone_target_paths = {}
# Maps drone → tick at which it should pick a new target.
# Entries are added when a drone's action ends; removed once the delay expires.
var _pending_drone_retargets = {}


func setup(player):
	# Initialize the intelligence system for a player. Called by AI player setup.
	_player = player
	MatchSignals.tick_advanced.connect(_on_tick_advanced)
	_attach_current_drones()
	_initialize_movement_of_current_drones()


func _attach_current_drones():
	# Register signal handlers for all existing drones belonging to this player
	for drone in _get_current_drones():
		_attach_drone(drone)


func _initialize_movement_of_current_drones():
	# Give each drone an initial target to scout
	for drone in _get_current_drones():
		_navigate_to_random_unit(drone)


func _get_current_drones():
	# Find all drone units belonging to this AI player
	return get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is Drone and unit.player == _player
	)


func _attach_drone(drone):
	# Listen for when drone finishes an action, so we can assign a new target
	drone.action_changed.connect(_on_drone_action_changed.bind(drone))
	# Clean up pending retargets if the drone dies
	drone.tree_exited.connect(_on_drone_freed.bind(drone))


func _navigate_to_random_unit(drone):
	# Select a random enemy unit (from enemy team) as scouting target.
	# TEAM FILTER: player.team != _player.team ensures we only scout enemies, not allies.
	var players_in_random_order = get_tree().get_nodes_in_group("players").filter(
		func(player): return player != _player and player.team != _player.team
	)
	if players_in_random_order.is_empty():
		return
	MatchUtils.rng_shuffle(players_in_random_order)
	var random_player_to_visit = players_in_random_order.front()
	if random_player_to_visit == null:
		return
	var random_player_units_in_random_order = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit.player == random_player_to_visit
	)
	var blacklisted_drone_target_path = _blacklisted_drone_target_paths.get(drone, NodePath())
	random_player_units_in_random_order = random_player_units_in_random_order.filter(
		func(unit): return unit.get_path() != blacklisted_drone_target_path
	)
	MatchUtils.rng_shuffle(random_player_units_in_random_order)
	if not random_player_units_in_random_order.is_empty():
		var target_unit = random_player_units_in_random_order.front()
		_blacklisted_drone_target_paths[drone] = target_unit.get_path()
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.MOVING_TO_UNIT,
			"player_id": _player.id,
			"data": {
				"targets": [{"unit": drone.id, "pos": drone.global_position, "rot": drone.global_rotation}],
				"target_unit": target_unit.id,
			}
		})
	else:
		var units_in_random_order = get_tree().get_nodes_in_group("units").filter(
			func(unit): return unit.player != _player and unit.player.team != _player.team
		)
		MatchUtils.rng_shuffle(units_in_random_order)
		units_in_random_order = units_in_random_order.filter(
			func(unit): return unit.get_path() != blacklisted_drone_target_path
		)
		if not units_in_random_order.is_empty():
			var target_unit = units_in_random_order.front()
			_blacklisted_drone_target_paths[drone] = target_unit.get_path()
			CommandBus.push_command({
				"tick": Match.tick + 1,
				"type": Enums.CommandType.MOVING_TO_UNIT,
				"player_id": _player.id,
				"data": {
					"targets": [{"unit": drone.id, "pos": drone.global_position, "rot": drone.global_rotation}],
					"target_unit": target_unit.id,
				}
			})


func _on_tick_advanced():
	# Each tick, check if any pending drone retargets are due.
	# This replaces the old create_timer(randf_range(...)) approach with deterministic tick counting.
	var drones_to_retarget = []
	for drone in _pending_drone_retargets:
		if Match.tick >= _pending_drone_retargets[drone]:
			drones_to_retarget.append(drone)
	# Sort by entity ID so RNG consumption order is deterministic across runs/replays.
	drones_to_retarget.sort_custom(func(a, b): return a.id < b.id)
	for drone in drones_to_retarget:
		_pending_drone_retargets.erase(drone)
		if is_instance_valid(drone) and not drone.is_queued_for_deletion():
			_navigate_to_random_unit(drone)


func _on_drone_action_changed(new_action, drone):
	if new_action == null:
		# Schedule retarget after a random tick delay (deterministic via seeded RNG).
		var delay_ticks = Match.rng.randi_range(TARGET_SWITCHING_DELAY_MIN_TICKS, TARGET_SWITCHING_DELAY_MAX_TICKS)
		_pending_drone_retargets[drone] = Match.tick + delay_ticks


func _on_drone_freed(drone):
	# Clean up any pending retarget for a freed drone
	_pending_drone_retargets.erase(drone)
	_blacklisted_drone_target_paths.erase(drone)
