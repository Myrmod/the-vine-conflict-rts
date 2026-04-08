extends "res://source/match/units/actions/Action.gd"

const REFRESH_TICKS = 1

var _target_unit = null
var _distance_to_reach = null
var _refresh_counter: int = 0
var _last_known_target_unit_position = null

@onready var _unit = Utils.NodeEx.find_parent_with_group(self, "units")
@onready var _movement_trait = _unit.find_child("Movement")


func _init(target_unit, distance_to_reach):
	_target_unit = target_unit
	_distance_to_reach = distance_to_reach


func _ready():
	MatchSignals.tick_advanced.connect(_on_tick_advanced)
	_movement_trait.movement_finished.connect(_on_movement_finished)
	_refresh()


func _exit_tree():
	_movement_trait.stop()


func _on_tick_advanced():
	if not is_inside_tree():
		return
	_refresh_counter += 1
	if _refresh_counter >= REFRESH_TICKS:
		_refresh_counter = 0
		_refresh()


func _refresh():
	if _teardown_if_distance_reached():
		return
	_align_movement_if_needed()


func _teardown_if_distance_reached():
	if (
		_unit.global_position_yless.distance_to(_target_unit.global_position_yless)
		<= _distance_to_reach
	):
		queue_free()
		return true
	return false


func _align_movement_if_needed():
	if (
		_last_known_target_unit_position == null
		or not _last_known_target_unit_position.is_equal_approx(_target_unit.global_position)
	):
		_movement_trait.move(_target_unit.global_position)
		_last_known_target_unit_position = _target_unit.global_position


func _on_movement_finished():
	_movement_trait.move(_target_unit.global_position)
