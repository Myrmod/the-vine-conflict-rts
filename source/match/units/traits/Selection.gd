@tool
extends Node3D

@export_range(0.001, 50.0) var radius = 1.0:
	set = _set_radius
@export_range(0.001, 50.0) var width = 10.0:
	set = _set_width

var _selected = false

@onready var _unit = get_parent()
@onready var _circle = find_child("FadedCircle3D")


func _ready():
	_update_circle_params()
	if Engine.is_editor_hint():
		return
	_set_visual_layer(_circle, 2)
	# Air units fly at terrain_y + Air.Y — offset the circle back down so it
	# always appears at ground level rather than floating at flight altitude.
	if "get_nav_domain" in _unit and _unit.get_nav_domain() == NavigationConstants.Domain.AIR:
		_circle.position.y = -Air.Y
	MatchSignals.deselect_all_units.connect(deselect)
	_unit.input_event.connect(_on_input_event)
	_circle.hide()


func select():
	if _selected:
		return
	_selected = true
	if not _unit.is_in_group("selected_units"):
		_unit.add_to_group("selected_units")
	_update_circle_color()
	_circle.show()
	if "selected" in _unit:
		_unit.selected.emit()
	MatchSignals.unit_selected.emit(_unit)


func deselect():
	if not _selected:
		return
	_selected = false
	if _unit.is_in_group("selected_units"):
		_unit.remove_from_group("selected_units")
	_circle.hide()
	if "deselected" in _unit:
		_unit.deselected.emit()
	MatchSignals.unit_deselected.emit(_unit)


func _set_radius(a_radius):
	radius = a_radius
	_update_circle_params()


func _set_width(a_width):
	width = a_width
	_update_circle_params()


func _update_circle_color():
	if _unit.is_in_group("controlled_units") or _unit.is_in_group("adversary_units"):
		if "player" in _unit and _unit.player != null:
			_circle.color = _unit.player.color
		else:
			_circle.color = MatchConstants.DEFAULT_CIRCLE_COLOR
	elif _unit.is_in_group("resource_units") or _unit.is_in_group("forest_vines"):
		_circle.color = MatchConstants.RESOURCE_CIRCLE_COLOR
	else:
		_circle.color = MatchConstants.DEFAULT_CIRCLE_COLOR


func _update_circle_params():
	if _circle == null:
		return
	_circle.radius = radius
	_circle.width = width
	_circle.inner_edge_width = width


func _on_input_event(_camera, event, _click_position, _click_normal, _shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if MatchSignals.active_command_mode != Enums.UnitCommandMode.NORMAL:
			if MatchSignals.active_command_mode == Enums.UnitCommandMode.ATTACK_MOVE:
				MatchSignals.unit_targeted.emit(_unit)
			else:
				var camera = get_viewport().get_camera_3d()
				if camera != null:
					var match_node = _unit.get_parent()
					var map = match_node.map if match_node != null and "map" in match_node else null
					var pos = camera.get_terrain_ray_intersection(event.position, map)
					if pos != null:
						MatchSignals.terrain_targeted.emit(pos)
			return
		if _selected and Input.is_action_pressed("shift_selecting"):
			deselect()
			return
		select()


func _set_visual_layer(node: Node, layer: int) -> void:
	for child in node.get_children():
		if child is VisualInstance3D:
			child.layers = layer
		_set_visual_layer(child, layer)
