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


func _try_navigating_selected_units_towards_position(target_point, queued: bool = false):
	# Filter selected units to find which ones can move to the target terrain position.
	# Checks: unit belongs to human player, unit supports terrain movement, Moving action is applicable
	var terrain_units_to_move = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit):
			return (
				unit.is_in_group("controlled_units")
				and unit.get_nav_domain() == NavigationConstants.Domain.TERRAIN
				and Actions.Moving.is_applicable(unit)
			)
	)
	var air_units_to_move = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit):
			return (
				unit.is_in_group("controlled_units")
				and unit.get_nav_domain() == NavigationConstants.Domain.AIR
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
	CommandBus.push_command(
		{
			"tick": Match.tick + 1,
			"type": Enums.CommandType.MOVE,
			"player_id": _player.id,
			"data":
			{
				"targets": new_unit_targets.map(func(t): return {"unit": t[0].id, "pos": t[1]}),
				"queued": queued,
			}
		}
	)


func _try_setting_rally_points(target_point: Vector3):
	# Set rally points through CommandBus so the action is recorded for replay determinism
	var controlled_structures = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit):
			return unit.is_in_group("controlled_units") and unit.find_child("RallyPoint") != null
	)
	for structure in controlled_structures:
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.SET_RALLY_POINT,
					"player_id": _player.id,
					"data":
					{
						"entity_id": structure.id,
						"position": target_point,
					}
				}
			)
		)


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

	CommandBus.push_command(
		{
			"tick": Match.tick + 1,
			"type": Enums.CommandType.CONSTRUCTING,
			"player_id": _player.id,
			"data":
			{
				"selected_constructors":
				selected_constructors.map(
					func(unit): return {
						"unit": unit.id,
						"pos": unit.global_position,
						"rot": unit.global_rotation,
					}
				),
				"structure": structure.id,
				"rotation": structure.global_rotation,
				"position": structure.global_transform.origin,
			}
		}
	)


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
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.COLLECTING_RESOURCES_SEQUENTIALLY,
					"player_id": _player.id,
					"data":
					{
						"targets":
						[
							{
								"unit": unit.id,
								"pos": unit.global_position,
								"rot": unit.global_rotation
							}
						],
						"target_unit": target_unit.id,
					}
				}
			)
		)

		return true
	if Actions.AutoAttacking.is_applicable(unit, target_unit):
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.AUTO_ATTACKING,
					"player_id": _player.id,
					"data":
					{
						"targets":
						[
							{
								"unit": unit.id,
								"pos": unit.global_position,
								"rot": unit.global_rotation
							}
						],
						"target_unit": target_unit.id,
					}
				}
			)
		)
		return true
	if Actions.Constructing.is_applicable(unit, target_unit):
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.CONSTRUCTING,
					"player_id": _player.id,
					"data":
					{
						"selected_constructors":
						[
							{
								"unit": unit.id,
								"pos": unit.global_position,
								"rot": unit.global_rotation
							}
						],
						"structure": target_unit.id,
						"rotation": target_unit.global_rotation,
						"position": target_unit.global_transform.origin,
					}
				}
			)
		)
		return true
	if (
		(target_unit.is_in_group("adversary_units") or target_unit.is_in_group("controlled_units"))
		and Actions.Following.is_applicable(unit)
	):
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.FOLLOWING,
					"player_id": _player.id,
					"data":
					{
						"targets":
						[
							{
								"unit": unit.id,
								"pos": unit.global_position,
								"rot": unit.global_rotation
							}
						],
						"target_unit": target_unit.id,
					}
				}
			)
		)
		return true
	if Actions.MovingToUnit.is_applicable(unit):
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.MOVING_TO_UNIT,
					"player_id": _player.id,
					"data":
					{
						"targets":
						[
							{
								"unit": unit.id,
								"pos": unit.global_position,
								"rot": unit.global_rotation
							}
						],
						"target_unit": target_unit.id,
					}
				}
			)
		)
		return true
	if _try_setting_rally_point_to_unit(unit, target_unit):
		return true
	return false  # gdlint: ignore = max-returns


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
	(
		CommandBus
		. push_command(
			{
				"tick": Match.tick + 1,
				"type": Enums.CommandType.SET_RALLY_POINT_TO_UNIT,
				"player_id": _player.id,
				"data":
				{
					"entity_id": unit.id,
					"target_unit": target_unit.id,
				}
			}
		)
	)
	return true


func _on_terrain_targeted(position):
	var mode = MatchSignals.active_command_mode
	if mode != Enums.UnitCommandMode.NORMAL:
		_handle_command_mode_click(position, mode)
		MatchSignals.active_command_mode = Enums.UnitCommandMode.NORMAL
		MatchSignals.command_mode_changed.emit(Enums.UnitCommandMode.NORMAL)
		return
	var is_queued = Input.is_key_pressed(KEY_SHIFT)
	_try_navigating_selected_units_towards_position(position, is_queued)
	_try_setting_rally_points(position)


func _handle_command_mode_click(position: Vector3, mode: int):
	var is_queued = Input.is_key_pressed(KEY_SHIFT)
	var movable_units = _get_movable_selected_units()
	if movable_units.is_empty():
		return
	match mode:
		Enums.UnitCommandMode.ATTACK_MOVE:
			_push_positional_command(
				Enums.CommandType.ATTACK_MOVE, movable_units, position, is_queued
			)
		Enums.UnitCommandMode.MOVE:
			_push_positional_command(
				Enums.CommandType.MOVE_NO_ATTACK, movable_units, position, is_queued
			)
		Enums.UnitCommandMode.PATROL:
			_push_patrol_command(movable_units, position, is_queued)


func _get_movable_selected_units() -> Array:
	return get_tree().get_nodes_in_group("selected_units").filter(
		func(unit):
			return unit.is_in_group("controlled_units") and Actions.Moving.is_applicable(unit)
	)


func _push_positional_command(cmd_type: int, units: Array, target_point: Vector3, queued: bool):
	var terrain_units = units.filter(
		func(u): return u.get_nav_domain() == NavigationConstants.Domain.TERRAIN
	)
	var air_units = units.filter(
		func(u): return u.get_nav_domain() == NavigationConstants.Domain.AIR
	)
	var targets = MatchUtils.Movement.crowd_moved_to_new_pivot(terrain_units, target_point)
	targets += MatchUtils.Movement.crowd_moved_to_new_pivot(air_units, target_point)
	CommandBus.push_command(
		{
			"tick": Match.tick + 1,
			"type": cmd_type,
			"player_id": _player.id,
			"data":
			{
				"targets": targets.map(func(t): return {"unit": t[0].id, "pos": t[1]}),
				"queued": queued,
			}
		}
	)


func _push_patrol_command(units: Array, target_point: Vector3, queued: bool):
	var terrain_units = units.filter(
		func(u): return u.get_nav_domain() == NavigationConstants.Domain.TERRAIN
	)
	var air_units = units.filter(
		func(u): return u.get_nav_domain() == NavigationConstants.Domain.AIR
	)
	var targets = MatchUtils.Movement.crowd_moved_to_new_pivot(terrain_units, target_point)
	targets += MatchUtils.Movement.crowd_moved_to_new_pivot(air_units, target_point)
	# Patrol origin: use the crowd pivot of the selected units as point_a
	var all_units = terrain_units + air_units
	var origin = (
		MatchUtils.Movement.calculate_aabb_crowd_pivot_yless(all_units)
		if not all_units.is_empty()
		else target_point
	)
	CommandBus.push_command(
		{
			"tick": Match.tick + 1,
			"type": Enums.CommandType.PATROL,
			"player_id": _player.id,
			"data":
			{
				"targets": targets.map(func(t): return {"unit": t[0].id, "pos": t[1]}),
				"patrol_origin": origin,
				"queued": queued,
			}
		}
	)


func push_stop_command():
	var selected = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit): return unit.is_in_group("controlled_units")
	)
	if selected.is_empty():
		return
	CommandBus.push_command(
		{
			"tick": Match.tick + 1,
			"type": Enums.CommandType.STOP,
			"player_id": _player.id,
			"data":
			{
				"targets": selected.map(func(u): return {"unit": u.id}),
			}
		}
	)


func push_hold_position_command():
	var selected = get_tree().get_nodes_in_group("selected_units").filter(
		func(unit): return unit.is_in_group("controlled_units")
	)
	if selected.is_empty():
		return
	var is_queued = Input.is_key_pressed(KEY_SHIFT)
	CommandBus.push_command(
		{
			"tick": Match.tick + 1,
			"type": Enums.CommandType.HOLD_POSITION,
			"player_id": _player.id,
			"data":
			{
				"targets": selected.map(func(u): return {"unit": u.id}),
				"queued": is_queued,
			}
		}
	)


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
		CommandBus.push_command(
			{
				"tick": Match.tick + 1,
				"type": Enums.CommandType.MOVE,
				"player_id": _player.id,
				"data":
				{
					"targets":
					[
						{
							"unit": unit.id,
							"pos": rally_point.global_position,
							"rot": unit.global_rotation
						}
					]
				}
			}
		)
