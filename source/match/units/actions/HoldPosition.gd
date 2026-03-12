# HoldPosition action: Unit stays rooted, attacks enemies in range only (never chases).
# Unlike WaitingForTargets, this action:
# - Never assigns AutoAttacking (which chases) — always uses AttackingWhileInRange
# - Does NOT queue_free when idle — persists until explicitly cancelled
# - Unit stays in place, only attacking what enters its attack_range
extends "res://source/match/units/actions/Action.gd"

const AttackingWhileInRange = preload("res://source/match/units/actions/AttackingWhileInRange.gd")

const REFRESH_INTERVAL = 1.0 / 60.0 * 10.0

var _timer = null
var _sub_action = null

@onready var _unit = Utils.NodeEx.find_parent_with_group(self, "units")


func _ready():
	if _unit.attack_range == null or _unit.attack_range <= 0:
		return
	_timer = Timer.new()
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)
	_timer.start(REFRESH_INTERVAL)


func _get_enemies_in_range():
	return get_tree().get_nodes_in_group("units").filter(
		func(unit):
			return (
				unit.player != _unit.player
				and unit.player.team != _unit.player.team
				and _unit.attack_domains.any(
					func(d): return d in unit.get_effective_movement_types()
				)
				and (
					_unit.global_position_yless.distance_to(unit.global_position_yless)
					<= _unit.attack_range
				)
			)
	)


func _attack_unit(target):
	_timer.timeout.disconnect(_on_timer_timeout)
	_sub_action = AttackingWhileInRange.new(target)
	_sub_action.tree_exited.connect(_on_attack_finished)
	add_child(_sub_action)
	_unit.action_updated.emit()


func _on_timer_timeout():
	var enemies = _get_enemies_in_range()
	if not enemies.is_empty():
		_attack_unit(_pick_closest(enemies))


func _on_attack_finished():
	if not is_inside_tree():
		return
	_sub_action = null
	_unit.action_updated.emit()
	_timer.timeout.connect(_on_timer_timeout)


func _pick_closest(units):
	var closest = units[0]
	var best_dist = _unit.global_position_yless.distance_to(closest.global_position_yless)
	for u in units:
		var d = _unit.global_position_yless.distance_to(u.global_position_yless)
		if d < best_dist:
			best_dist = d
			closest = u
	return closest
