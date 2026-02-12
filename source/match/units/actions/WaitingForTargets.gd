# WaitingForTargets action: Idle action state where a unit waits for enemies to come in range.
# Periodically scans for valid attack targets and transitions to attacking when found.
# This is the \"holding ground\" behavior - unit stands still, scans, and reacts to threats.
# TEAM CHECK: Filters out same-team units from consideration, implementing team protection.
extends "res://source/match/units/actions/Action.gd"

const AttackingWhileInRange = preload("res://source/match/units/actions/AttackingWhileInRange.gd")
const AutoAttacking = preload("res://source/match/units/actions/AutoAttacking.gd")

const REFRESH_INTERVAL = 1.0 / 60.0 * 10.0

var _timer = null
var _sub_action = null

@onready var _unit = Utils.NodeEx.find_parent_with_group(self, "units")


func _ready():
	# Start periodic scanning for enemies in sight range
	_timer = Timer.new()
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)
	_timer.start(REFRESH_INTERVAL)


func is_idle():
	return _sub_action == null


func _get_units_to_attack():
	# Scan for valid attack targets: enemy units in sight range that can be attacked.
	# TEAM FILTER: unit.player.team != _unit.player.team ensures we only see enemy teams.
	return get_tree().get_nodes_in_group("units").filter(
		func(unit):
			return (
				unit.player != _unit.player  # Different player
				and unit.player.team != _unit.player.team  # Different TEAM (core protection)
				and unit.movement_domain in _unit.attack_domains  # Attackable domain
				and (
					_unit.global_position_yless.distance_to(unit.global_position_yless)
					<= _unit.sight_range  # In vision range
				)
			)
	)


func _attack_unit(unit):
	# Found a target! Stop scanning and start attacking.
	_timer.timeout.disconnect(_on_timer_timeout)
	_sub_action = (
		AutoAttacking.new(unit) if _unit.movement_speed > 0.0 else AttackingWhileInRange.new(unit)
	)
	_sub_action.tree_exited.connect(_on_attack_finished)
	add_child(_sub_action)
	_unit.action_updated.emit()


func _on_timer_timeout():
	var units_to_attack = _get_units_to_attack()
	if not units_to_attack.is_empty():
		_attack_unit(_pick_closest_unit(units_to_attack, _unit))


func _on_attack_finished():
	if not is_inside_tree():
		return
	_sub_action = null
	_unit.action_updated.emit()
	_timer.timeout.connect(_on_timer_timeout)


static func _pick_closest_unit(units, unit):
	assert(not units.is_empty())
	var distance_to_closest_unit = unit.global_position_yless.distance_to(
		units[0].global_position_yless
	)
	var closest_unit = units[0]
	for unit_to_check in units:
		var distance = unit.global_position_yless.distance_to(unit_to_check.global_position_yless)
		if distance < distance_to_closest_unit:
			distance_to_closest_unit = distance
			closest_unit = unit_to_check
	return closest_unit
