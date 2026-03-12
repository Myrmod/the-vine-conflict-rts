# AttackMoving action: Unit moves toward a destination while scanning for enemies.
# When an enemy is found in sight range, the unit stops and engages (first enemy encountered).
# After the enemy dies, the unit resumes moving toward the original destination.
# When the destination is reached, the action completes (unit returns to default idle).
#
# Non-combat units (no attack_range): not handled here — they just use Moving.
extends "res://source/match/units/actions/Action.gd"

const AutoAttacking = preload("res://source/match/units/actions/AutoAttacking.gd")

const SCAN_INTERVAL = 1.0 / 60.0 * 10.0

var _target_position: Vector3
var _sub_action = null
var _state: int = 0  # 0 = moving, 1 = engaging

@onready var _unit = Utils.NodeEx.find_parent_with_group(self, "units")
@onready var _movement_trait = _unit.find_child("Movement")


func _init(target_position: Vector3):
	_target_position = target_position


func _ready():
	if _unit.attack_range != null and _unit.attack_range > 0:
		_start_moving_with_scan()
	else:
		_start_moving_no_scan()


func _start_moving_no_scan():
	_state = 0
	_movement_trait.move(_target_position)
	_movement_trait.movement_finished.connect(_on_movement_finished)


func _start_moving_with_scan():
	_state = 0
	_movement_trait.move(_target_position)
	_movement_trait.movement_finished.connect(_on_movement_finished)
	var timer = Timer.new()
	timer.name = "ScanTimer"
	timer.timeout.connect(_on_scan_timeout)
	add_child(timer)
	timer.start(SCAN_INTERVAL)


func _exit_tree():
	if is_inside_tree() and _state == 0:
		_movement_trait.stop()


func _get_enemies_in_sight():
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
					<= _unit.sight_range
				)
			)
	)


func _on_scan_timeout():
	if _state != 0:
		return
	var enemies = _get_enemies_in_sight()
	if not enemies.is_empty():
		_engage_enemy(_pick_closest(enemies))


func _engage_enemy(target):
	_state = 1
	_movement_trait.stop()
	if _movement_trait.movement_finished.is_connected(_on_movement_finished):
		_movement_trait.movement_finished.disconnect(_on_movement_finished)
	var scan_timer = get_node_or_null("ScanTimer")
	if scan_timer:
		scan_timer.timeout.disconnect(_on_scan_timeout)
		scan_timer.stop()
	_sub_action = AutoAttacking.new(target)
	_sub_action.tree_exited.connect(_on_engagement_finished)
	add_child(_sub_action)
	_unit.action_updated.emit()


func _on_engagement_finished():
	if not is_inside_tree():
		return
	_sub_action = null
	_unit.action_updated.emit()
	_state = 0
	_movement_trait.move(_target_position)
	_movement_trait.movement_finished.connect(_on_movement_finished)
	var scan_timer = get_node_or_null("ScanTimer")
	if scan_timer:
		scan_timer.timeout.connect(_on_scan_timeout)
		scan_timer.start(SCAN_INTERVAL)


func _on_movement_finished():
	queue_free()


func _pick_closest(units):
	var closest = units[0]
	var best_dist = _unit.global_position_yless.distance_to(closest.global_position_yless)
	for u in units:
		var d = _unit.global_position_yless.distance_to(u.global_position_yless)
		if d < best_dist:
			best_dist = d
			closest = u
	return closest
