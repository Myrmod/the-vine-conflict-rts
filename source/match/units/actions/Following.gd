extends "res://source/match/units/actions/Action.gd"

const MovingToUnit = preload("res://source/match/units/actions/MovingToUnit.gd")

const REFRESH_TICKS = 1

var _target_unit = null
var _refresh_counter: int = 0
var _last_known_target_unit_position = null
var _sub_action = null

@onready var _unit = Utils.NodeEx.find_parent_with_group(self, "units")


static func is_applicable(source_unit):
	return MovingToUnit.is_applicable(source_unit)


func _init(target_unit):
	_target_unit = target_unit


func _ready():
	_target_unit.tree_exited.connect(queue_free)
	MatchSignals.tick_advanced.connect(_on_tick_advanced)
	_refresh()


func _to_string():
	return "{0}({1})".format([super(), str(_sub_action) if _sub_action != null else ""])


func _on_tick_advanced():
	if not is_inside_tree():
		return
	_refresh_counter += 1
	if _refresh_counter >= REFRESH_TICKS:
		_refresh_counter = 0
		_refresh()


func _refresh():
	if (
		_last_known_target_unit_position == null
		or not _target_unit.global_position.is_equal_approx(_last_known_target_unit_position)
	):
		if _sub_action != null:
			_sub_action.tree_exited.disconnect(_on_sub_action_finished)
			remove_child(_sub_action)
		_sub_action = MovingToUnit.new(_target_unit)
		_sub_action.tree_exited.connect(_on_sub_action_finished)
		add_child(_sub_action)
		_last_known_target_unit_position = _target_unit.global_position
		_unit.action_updated.emit()


func _on_sub_action_finished():
	_sub_action = null
	_unit.action_updated.emit()
