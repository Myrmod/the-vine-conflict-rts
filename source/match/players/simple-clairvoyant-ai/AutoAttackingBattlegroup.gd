# Manages coordinated AI combat behavior for a group of units attacking a common enemy.
# This is part of the clairvoyant AI strategy where multiple units work together as a battlegroup.
#
# DETERMINISM: Player-switching delay uses tick counting (not wall-clock timers) so the same
# commands are pushed at the same tick during replay. 5 ticks = 0.5 s at TICK_RATE 10.
extends Node

enum State {FORMING, ATTACKING}

# Delay in ticks before switching to the next enemy player (5 ticks = 0.5 s at TICK_RATE 10).
const PLAYER_TO_ATTACK_SWITCHING_DELAY_TICKS = 5

var _expected_number_of_units = null
var _players_to_attack = null
var _player_to_attack = null

var _state = State.FORMING
var _attached_units = []
var _player = null
# Tick at which we should execute the pending player-switch. -1 means no pending switch.
var _pending_switch_tick = -1


func _init(expected_number_of_units, players_to_attack, player):
	# Store the expected unit count (battlegroup waits until all units attached before attacking)
	# and the list of enemy players this battlegroup should attack
	_expected_number_of_units = expected_number_of_units
	_players_to_attack = players_to_attack
	_player = player
	# Start targeting the first enemy player; when cleared, move to next
	_player_to_attack = _players_to_attack.front() if not _players_to_attack.is_empty() else null


func _ready():
	# Subscribe to deterministic tick events for delayed player-switching
	MatchSignals.tick_advanced.connect(_on_tick_advanced)


func _on_tick_advanced():
	# Check if a pending player-switch delay has elapsed
	if _pending_switch_tick >= 0 and Match.tick >= _pending_switch_tick:
		_pending_switch_tick = -1
		_attack_next_adversary_unit()


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
			# Found a valid target! Push a single deterministic command for the whole battlegroup
			target_unit.tree_exited.connect(_on_target_unit_died)
			var targets = []
			for attached_unit in _attached_units:
				targets.append({
					"unit": attached_unit.id,
					"pos": attached_unit.global_position,
					"rot": attached_unit.global_rotation,
				})
			CommandBus.push_command({
				"tick": Match.tick + 1,
				"type": Enums.CommandType.AUTO_ATTACKING,
				"player_id": _player.id,
				"data": {
					"targets": targets,
					"target_unit": target_unit.id,
				}
			})
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
	# Deterministic tick-based delay before attacking next player (replaces wall-clock timer).
	# _on_tick_advanced() will fire _attack_next_adversary_unit when the tick arrives.
	_pending_switch_tick = Match.tick + PLAYER_TO_ATTACK_SWITCHING_DELAY_TICKS


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
