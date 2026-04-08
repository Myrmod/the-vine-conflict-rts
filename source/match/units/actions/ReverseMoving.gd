# ReverseMoving action: Unit moves to a target position while facing away from it.
# The unit travels backwards (reverse gear) without turning around.
# Only applicable if the unit has can_reverse_move set to true.
extends "res://source/match/units/actions/Action.gd"

var _target_position = null

@onready var _unit = Utils.NodeEx.find_parent_with_group(self, "units")
@onready var _movement_trait = _unit.find_child("Movement")


static func is_applicable(unit):
	return (
		unit.find_child("Movement") != null and "can_reverse_move" in unit and unit.can_reverse_move
	)


func _init(target_position):
	_target_position = target_position


func _ready():
	_movement_trait.reverse_moving = true
	_movement_trait.move(_target_position)
	_movement_trait.movement_finished.connect(_on_movement_finished)


func _exit_tree():
	_movement_trait.reverse_moving = false
	if is_inside_tree():
		_movement_trait.stop()


func _on_movement_finished():
	queue_free()
