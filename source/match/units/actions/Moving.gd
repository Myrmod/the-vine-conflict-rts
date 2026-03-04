# Moving action: Unit moves to a target position (terrain or air).
# Simple action that delegates to the unit's Movement trait/component.
# When movement reaches the destination, automatically cleans itself up.
# This action is assigned by Match._execute_command() when processing COMMAND.MOVE commands.
extends "res://source/match/units/actions/Action.gd"

var _target_position = null

@onready var _unit = Utils.NodeEx.find_parent_with_group(self, "units")
@onready var _movement_trait = _unit.find_child("Movement")


# Moving is applicable if the unit has a Movement component (most units do, except stationary buildings)
static func is_applicable(unit):
	return unit.find_child("Movement") != null


func _init(target_position):
	# Store the destination position. Movement logic is delegated to the Movement trait.
	_target_position = target_position


func _ready():
	# Tell the Movement trait to navigate to the target.
	# The trait handles pathfinding, obstacle avoidance, etc.
	_movement_trait.move(_target_position)
	_movement_trait.movement_finished.connect(_on_movement_finished)


func _exit_tree():
	# If action is removed from tree (e.g., unit dies), stop movement immediately
	if is_inside_tree():
		_movement_trait.stop()


func _on_movement_finished():
	# Destination reached, action is complete
	queue_free()
