# This is the HUMAN PLAYER INPUT HANDLER that bridges the UI with the unified command system.
# When a human player clicks a target or presses a button, UI signals (terrain_targeted, unit_targeted, etc.)
# fire from MatchSignals. This controller responds by determining:
# 1. Which units are selected and can perform the action
# 2. What action they should perform and on what target
# 3. Converting that to a Command object with correct data format
# 4. Queuing the command through CommandBus.push_command()
#
# Critical: Commands are queued for (current_tick + 1) to allow the command to execute
# in the next game tick. Both human and AI decisions go through this exact same pipeline,
# which ensures deterministic replays: same commands in same order = identical game outcome.
# See CommandBus.gd and Match._execute_command() for how commands become actual game changes.
extends Node

class_name UnitActionsController

const Structure = preload("res://source/match/units/Structure.gd")

@onready var _player = get_parent()

func _ready():
	MatchSignals.terrain_targeted.connect(_on_terrain_targeted)
	MatchSignals.unit_targeted.connect(_on_unit_targeted)
	MatchSignals.unit_spawned.connect(_on_unit_spawned)
	MatchSignals.navigate_unit_to_rally_point.connect(_on_navigate_unit_to_rally_point)


func _try_navigating_selected_units_towards_position(target_point):
	# Filter selected units to find which ones can move to the target terrain position.
	# Checks: unit belongs to human player, unit supports terrain movement, Moving action is applicable
	var terrain_units_to_move = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit):
			return (
				unit.is_in_group("controlled_units")
				and unit.movement_domain == NavigationConstants.Domain.TERRAIN
				and Actions.Moving.is_applicable(unit)
			)
	)
	var air_units_to_move = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit):
			return (
				unit.is_in_group("controlled_units")
				and unit.movement_domain == NavigationConstants.Domain.AIR
				and Actions.Moving.is_applicable(unit)
			)
	)
	# Calculate new positions for units to move to (handles unit grouping and collision avoidance)
	var new_unit_targets = MatchUtils.Movement.crowd_moved_to_new_pivot(
		terrain_units_to_move, target_point
	)
	new_unit_targets += MatchUtils.Movement.crowd_moved_to_new_pivot(
		air_units_to_move, target_point
	)

	# Queue a MOVE command through CommandBus. This will:
	# 1. Be recorded by ReplayRecorder for replay capability
	# 2. Execute in next tick when Match._process_commands_for_tick() runs
	# 3. Assign Actions.Moving to each selected unit
	# 4. Be deterministically replayed with identical behavior (same tick, same command data)
	CommandBus.push_command({
		"tick": Match.tick + 1,
		"type": Enums.CommandType.MOVE,
		"player_id": _player.id,
		"data": {
			"targets": new_unit_targets.map(
				func(t): return {"unit": t[0].id, "pos": t[1]}
			)
		}
	})


func _try_setting_rally_points(target_point: Vector3):
	# Set rally points through CommandBus so the action is recorded for replay determinism
	var controlled_structures = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit):
			return unit.is_in_group("controlled_units") and unit.find_child("RallyPoint") != null
	)
	for structure in controlled_structures:
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.SET_RALLY_POINT,
			"player_id": _player.id,
			"data": {
				"entity_id": structure.id,
				"position": target_point,
			}
		})


func _try_ordering_selected_workers_to_construct_structure(potential_structure):
	if not potential_structure is Structure or potential_structure.is_constructed():
		return
	var structure = potential_structure
	var selected_constructors = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit):
			return (
				unit.is_in_group("controlled_units")
				and Actions.Constructing.is_applicable(unit, structure)
			)
	)

	CommandBus.push_command({
		"tick": Match.tick + 1,
		"type": Enums.CommandType.CONSTRUCTING,
		"player_id": _player.id,
		"data": {
			"selected_constructors": selected_constructors.map(func(unit): return {
					"unit": unit.id,
					"pos": unit.global_position,
					"rot": unit.global_rotation,
				}
			),
			"structure": structure.id,
			"rotation": structure.global_rotation,
			"position": structure.global_transform.origin,
		}
	})


func _navigate_selected_units_towards_unit(target_unit):
	var at_least_one_unit_navigated = false
	for unit in get_tree().get_nodes_in_group("selected_units"):
		if not unit.is_in_group("controlled_units"):
			continue
		if _navigate_unit_towards_unit(unit, target_unit):
			at_least_one_unit_navigated = true
	return at_least_one_unit_navigated


func _navigate_unit_towards_unit(unit, target_unit):
	if Actions.CollectingResourcesSequentially.is_applicable(unit, target_unit):
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.COLLECTING_RESOURCES_SEQUENTIALLY,
			"player_id": _player.id,
			"data": {
				"targets": [{"unit": unit.id, "pos": unit.global_position, "rot": unit.global_rotation}],
				"target_unit": target_unit.id,
			}
		})

		return true
	if Actions.AutoAttacking.is_applicable(unit, target_unit):
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.AUTO_ATTACKING,
			"player_id": _player.id,
			"data": {
				"targets": [{"unit": unit.id, "pos": unit.global_position, "rot": unit.global_rotation}],
				"target_unit": target_unit.id,
			}
		})
		return true
	if Actions.Constructing.is_applicable(unit, target_unit):
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.CONSTRUCTING,
			"player_id": _player.id,
			"data": {
				"selected_constructors": [{"unit": unit.id, "pos": unit.global_position, "rot": unit.global_rotation}],
				"structure": target_unit.id,
				"rotation": target_unit.global_rotation,
				"position": target_unit.global_transform.origin,
			}
		})
		return true
	if (
		(target_unit.is_in_group("adversary_units") or target_unit.is_in_group("controlled_units"))
		and Actions.Following.is_applicable(unit)
	):
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.FOLLOWING,
			"player_id": _player.id,
			"data": {
				"targets": [{"unit": unit.id, "pos": unit.global_position, "rot": unit.global_rotation}],
				"target_unit": target_unit.id,
			}
		})
		return true
	if Actions.MovingToUnit.is_applicable(unit):
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.MOVING_TO_UNIT,
			"player_id": _player.id,
			"data": {
				"targets": [{"unit": unit.id, "pos": unit.global_position, "rot": unit.global_rotation}],
				"target_unit": target_unit.id,
			}
		})
		return true
	if _try_setting_rally_point_to_unit(unit, target_unit):
		return true
	return false # gdlint: ignore = max-returns


func _try_setting_rally_point_to_unit(unit, target_unit):
	if not unit is Structure:
		return false
	if not target_unit is ResourceUnit and unit.player != target_unit.player:
		# it's not allowed to set rally point to enemy at the moment as with current implementation
		# the position of enemy unit hidden in the fog of war could be hinted
		return false
	var rally_point = unit.find_child("RallyPoint")
	if rally_point == null:
		return false
	# Set rally point to unit through CommandBus for replay determinism
	CommandBus.push_command({
		"tick": Match.tick + 1,
		"type": Enums.CommandType.SET_RALLY_POINT_TO_UNIT,
		"player_id": _player.id,
		"data": {
			"entity_id": unit.id,
			"target_unit": target_unit.id,
		}
	})
	return true


func _on_terrain_targeted(position):
	_try_navigating_selected_units_towards_position(position)
	_try_setting_rally_points(position)


func _on_unit_targeted(unit):
	if _navigate_selected_units_towards_unit(unit):
		var targetability = unit.find_child("Targetability")
		if targetability != null:
			targetability.animate()


func _on_unit_spawned(unit):
	_try_ordering_selected_workers_to_construct_structure(unit)


func _on_navigate_unit_to_rally_point(unit, rally_point):
	if rally_point.target_unit != null:
		_navigate_unit_towards_unit(unit, rally_point.target_unit)
	elif rally_point.global_position != rally_point.get_parent().global_position:
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.MOVE,
			"player_id": _player.id,
			"data": {
				"targets": [{"unit": unit.id, "pos": rally_point.global_position, "rot": unit.global_rotation}]
			}
		})
