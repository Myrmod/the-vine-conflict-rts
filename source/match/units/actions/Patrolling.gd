# Patrolling action: Unit moves back and forth between two points repeatedly.
# Scans for enemies during movement (like attack-move). When an enemy is found,
# the unit engages and chases up to 5 tiles from the nearest patrol waypoint.
# If the enemy moves beyond 5 tiles, the unit disengages and resumes patrol.
# Loops indefinitely until cancelled.
extends "res://source/match/units/actions/Action.gd"

const AutoAttacking = preload("res://source/match/units/actions/AutoAttacking.gd")

const SCAN_INTERVAL = 1.0 / 60.0 * 10.0
const MAX_CHASE_DISTANCE = 5.0
const CHASE_CHECK_INTERVAL = 1.0 / 60.0 * 10.0

var _point_a: Vector3
var _point_b: Vector3
var _moving_to_b: bool = true
var _sub_action = null
var _state: int = 0  # 0 = patrolling, 1 = engaging

@onready var _unit = Utils.NodeEx.find_parent_with_group(self, "units")
@onready var _movement_trait = _unit.find_child("Movement")


func _init(point_a: Vector3, point_b: Vector3):
	_point_a = point_a
	_point_b = point_b


func _ready():
	_start_patrol_leg()
	if _unit.attack_range != null and _unit.attack_range > 0:
		var timer = Timer.new()
		timer.name = "ScanTimer"
		timer.timeout.connect(_on_scan_timeout)
		add_child(timer)
		timer.start(SCAN_INTERVAL)


func _exit_tree():
	if is_inside_tree() and _state == 0:
		_movement_trait.stop()


func _current_target() -> Vector3:
	return _point_b if _moving_to_b else _point_a


func _nearest_patrol_point(pos: Vector3) -> float:
	var da = pos.distance_to(_point_a * Vector3(1, 0, 1))
	var db = pos.distance_to(_point_b * Vector3(1, 0, 1))
	return min(da, db)


func _start_patrol_leg():
	_state = 0
	_movement_trait.move(_current_target())
	_movement_trait.movement_finished.connect(_on_leg_finished)


func _on_leg_finished():
	if not is_inside_tree():
		return
	if _movement_trait.movement_finished.is_connected(_on_leg_finished):
		_movement_trait.movement_finished.disconnect(_on_leg_finished)
	_moving_to_b = not _moving_to_b
	_start_patrol_leg()


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
	if _movement_trait.movement_finished.is_connected(_on_leg_finished):
		_movement_trait.movement_finished.disconnect(_on_leg_finished)
	var scan_timer = get_node_or_null("ScanTimer")
	if scan_timer:
		scan_timer.timeout.disconnect(_on_scan_timeout)
		scan_timer.stop()

	_sub_action = AutoAttacking.new(target)
	_sub_action.tree_exited.connect(_on_engagement_finished)
	add_child(_sub_action)

	# Start chase-distance check
	var chase_timer = Timer.new()
	chase_timer.name = "ChaseTimer"
	chase_timer.timeout.connect(_on_chase_check.bind(target))
	add_child(chase_timer)
	chase_timer.start(CHASE_CHECK_INTERVAL)
	_unit.action_updated.emit()


func _on_chase_check(target):
	if _state != 1:
		return
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	var dist = _nearest_patrol_point(target.global_position_yless)
	if dist > MAX_CHASE_DISTANCE:
		_disengage()


func _disengage():
	if _sub_action != null and is_instance_valid(_sub_action):
		if _sub_action.tree_exited.is_connected(_on_engagement_finished):
			_sub_action.tree_exited.disconnect(_on_engagement_finished)
		_sub_action.queue_free()
		_sub_action = null
	var chase_timer = get_node_or_null("ChaseTimer")
	if chase_timer:
		chase_timer.queue_free()
	_resume_patrol()


func _on_engagement_finished():
	if not is_inside_tree():
		return
	_sub_action = null
	var chase_timer = get_node_or_null("ChaseTimer")
	if chase_timer:
		chase_timer.queue_free()
	_unit.action_updated.emit()
	_resume_patrol()


func _resume_patrol():
	_start_patrol_leg()
	var scan_timer = get_node_or_null("ScanTimer")
	if scan_timer:
		scan_timer.timeout.connect(_on_scan_timeout)
		scan_timer.start(SCAN_INTERVAL)


func _pick_closest(units):
	var closest = units[0]
	var best_dist = _unit.global_position_yless.distance_to(closest.global_position_yless)
	for u in units:
		var d = _unit.global_position_yless.distance_to(u.global_position_yless)
		if d < best_dist:
			best_dist = d
			closest = u
	return closest
