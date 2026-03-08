## Visual countdown bar shown above a structure while it is being sold.
## Works like HealthBar but counts down from full to empty over the
## sell duration. Appears automatically when selling starts and hides
## when selling ends or is cancelled.
extends Node3D

@export var size = Vector2(200, 12):
	set(value):
		size = value
		if _actual_bar != null:
			_actual_bar.texture.width = size.x
			_actual_bar.texture.height = size.y

@onready var _unit = get_parent()
@onready var _actual_bar: Sprite3D = find_child("ActualBar")


func _ready():
	hide()


func _process(_delta: float) -> void:
	if _unit == null:
		return
	if _unit.is_selling:
		var fraction := float(_unit._sell_ticks_remaining) / float(_unit.SELL_DURATION_TICKS)
		# Clamp to avoid 1px gap
		if is_equal_approx(fraction, 1.0):
			fraction = 1.1
		_actual_bar.texture.gradient.set_offset(1, fraction)
		if not visible:
			show()
	else:
		if visible:
			hide()
