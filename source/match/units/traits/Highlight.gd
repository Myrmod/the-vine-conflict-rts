@tool
extends Node3D

@export_range(0.001, 50.0) var radius = 1.0:
	set = _set_radius
@export_range(0.001, 50.0) var width = 5.0:
	set = _set_width

var _activated = false
var _forced = false

@onready var _unit = get_parent()
@onready var _circle = find_child("Circle3D")


func _ready():
	_update_circle_params()
	if Engine.is_editor_hint():
		return
	_set_visual_layer(_circle, 2)
	_unit.mouse_entered.connect(_activate)
	_unit.mouse_exited.connect(_deactivate)
	_circle.hide()


func force():
	_forced = true
	_update()


func unforce():
	_forced = false
	_update()


func refresh():
	_update()


func _update_circle_params():
	if _circle == null:
		return
	_circle.radius = radius
	_circle.width = width


func _update_circle_color():
	if _unit.is_in_group("controlled_units") or _unit.is_in_group("adversary_units"):
		if "player" in _unit and _unit.player != null:
			_circle.color = _unit.player.color
		else:
			_circle.color = MatchConstants.DEFAULT_CIRCLE_COLOR
	elif _unit.is_in_group("resource_units"):
		_circle.color = MatchConstants.RESOURCE_CIRCLE_COLOR
	else:
		_circle.color = MatchConstants.DEFAULT_CIRCLE_COLOR


func _set_radius(a_radius):
	radius = a_radius
	_update_circle_params()


func _set_width(a_width):
	width = a_width
	_update_circle_params()


func _activate():
	_activated = true
	_update()


func _deactivate():
	_activated = false
	_update()


func _update():
	_update_circle_color()
	_circle.visible = _forced or _activated


func _set_visual_layer(node: Node, layer: int) -> void:
	for child in node.get_children():
		if child is VisualInstance3D:
			child.layers = layer
		_set_visual_layer(child, layer)
