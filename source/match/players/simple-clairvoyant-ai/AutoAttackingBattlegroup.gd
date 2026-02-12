# Manages coordinated AI combat behavior for a group of units attacking a common enemy.
# This is part of the clairvoyant AI strategy where multiple units work together as a battlegroup.
# NOTE: While human players send commands through CommandBus, this directly assigns actions to units,
# which bypasses the replay recording system. For perfect replay determinism, this should be
# refactored to queue commands through CommandBus instead (like human players do).
extends Node

enum State {FORMING, ATTACKING}

const PLAYER_TO_ATTACK_SWITCHING_DELAY_S = 0.5

var _expected_number_of_units = null
var _players_to_attack = null
var _player_to_attack = null

var _state = State.FORMING
var _attached_units = []


func _init(expected_number_of_units, players_to_attack):
	# Store the expected unit count (battlegroup waits until all units attached before attacking)
	# and the list of enemy players this battlegroup should attack
	_expected_number_of_units = expected_number_of_units
	_players_to_attack = players_to_attack
	# Start targeting the first enemy player; when cleared, move to next
	_player_to_attack = _players_to_attack.front() if not _players_to_attack.is_empty() else null


func size():
	return _attached_units.size()


func attach_unit(unit):
	# Battlegroup units are attached during formation phase. When all expected units attached,
	# transition to ATTACKING state and find targets.
	assert(_state == State.FORMING, "unexpected state")
	_attached_units.append(unit)
	unit.tree_exited.connect(_on_unit_died.bind(unit))
	if size() == _expected_number_of_units:
		_start_attacking()


func _start_attacking():
	_state = State.ATTACKING
	_attack_next_adversary_unit()


func _attack_next_adversary_unit():
	# Find all units belonging to the target player
	var adversary_units = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit.player == _player_to_attack
	)
	# If target player has no units left, move to attacking next enemy player
	if adversary_units.is_empty():
		_attack_next_player()
		return
	
	# Sort adversary units by distance to find closest target (simplest strategy)
	var battlegroup_position = _attached_units[0].global_position
	var adversary_units_sorted_by_distance = adversary_units.map(
		func(adversary_unit):
			return {
				"distance":
				(adversary_unit.global_position * Vector3(1, 0, 1)).distance_to(
					battlegroup_position
				),
				"unit": adversary_unit
			}
	)
	adversary_units_sorted_by_distance.sort_custom(
		func(tuple_a, tuple_b): return tuple_a["distance"] < tuple_b["distance"]
	)
	
	# Attempt to attack the closest valid target
	for tuple in adversary_units_sorted_by_distance:
		var target_unit = tuple["unit"]
		# Check if at least one battlegroup unit can attack this target
		if _attached_units.any(
			func(attached_unit):
				return Actions.AutoAttacking.is_applicable(attached_unit, target_unit)
		):
			# Found a valid target! Assign attack or move-to-attack actions to all units in battlegroup
			target_unit.tree_exited.connect(_on_target_unit_died)
			for attached_unit in _attached_units:
				if Actions.AutoAttacking.is_applicable(attached_unit, target_unit):
					# Unit is in range and can attack
					attached_unit.action = Actions.AutoAttacking.new(target_unit)
				else:
					# Unit is out of range, move closer to target
					attached_unit.action = Actions.MovingToUnit.new(target_unit)
			return
	# No valid targets found on this player, try next enemy
	_attack_next_player()


func _attack_next_player():
	# Move to next enemy player in rotation. If all players defeated, battlegroup mission complete.
	if _players_to_attack.is_empty():
		queue_free()
		return
	var player_to_attack_index = _players_to_attack.find(_player_to_attack)
	var next_player_to_attack_index = (player_to_attack_index + 1) % _players_to_attack.size()
	_player_to_attack = _players_to_attack[next_player_to_attack_index]
	# Small delay before attacking next player (gives some bot "reaction time")
	get_tree().create_timer(PLAYER_TO_ATTACK_SWITCHING_DELAY_S).timeout.connect(
		_attack_next_adversary_unit
	)


func _on_unit_died(unit):
	# Remove the dead unit and check if battlegroup is still viable
	if not is_inside_tree():
		return
	_attached_units.erase(unit)
	if _state == State.ATTACKING and _attached_units.is_empty():
		# All units dead, mission over
		queue_free()


func _on_target_unit_died():
	# Current target died, find next target
	if not is_inside_tree():
		return
	_attack_next_adversary_unit()
