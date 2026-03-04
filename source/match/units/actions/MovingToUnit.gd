# MovingToUnit action: Unit follows and maintains distance from a target unit.
# Extends Moving action. Continuously updates movement target as the target unit moves.
# Completes when unit is adjacent to target (units_adhere check). Used for both:
# - AutoAttacking (move into range) 
# - Constructing (move to structure)
extends "res://source/match/units/actions/Moving.gd"

var _target_unit = null


func _init(target_unit):
	# Store target unit. Position will be calculated in _ready()
	_target_unit = target_unit


func _process(_delta):
	# Every frame, check if we've reached the target unit.
	# If we're adjacent (units_adhere), end the action immediately.
	if MatchUtils.Movement.units_adhere(_unit, _target_unit):
		queue_free()


func _ready():
	# Listen for target unit death - if target dies, this action dies with it
	_target_unit.tree_exited.connect(queue_free)
	# Calculate position next to target (not on top of it) based on target radius
	_target_position = (
		_target_unit.global_position_yless
		+ (
			(_unit.global_position_yless - _target_unit.global_position_yless).normalized()
			* _target_unit.radius
		)
	)
	super()


func _on_movement_finished():
	# Movement to one position complete. Check if we've reached the target unit.
	if MatchUtils.Movement.units_adhere(_unit, _target_unit):
		queue_free()
	else:
		# Target has moved. Recalculate position and resume movement.
		_target_position = _target_unit.global_position
		_movement_trait.move(_target_position)
