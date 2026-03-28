extends StaticBody3D

## Minimum screen-pixel distance for a right-click to count as a drag
## rather than a plain click.
const _DRAG_THRESHOLD_PX := 8.0

@onready var _collision_shape = find_child("CollisionShape3D")

var _rclick_start_screen: Vector2 = Vector2.ZERO
var _rclick_start_world: Vector3 = Vector3.ZERO
var _rclick_dragging: bool = false


func _ready():
	input_event.connect(_on_input_event)


func update_shape_from_map_size(map_size: Vector2):
	var plane := PlaneMesh.new()
	plane.size = map_size
	plane.center_offset = Vector3(map_size.x / 2.0, 0.0, map_size.y / 2.0)
	_collision_shape.shape = plane.create_trimesh_shape()
	if not is_in_group("terrain_navigation_input"):
		add_to_group("terrain_navigation_input")


func _on_input_event(_camera, event, _click_position, _click_normal, _shape_idx):
	if not event is InputEventMouseButton:
		return

	var is_right_click = event.button_index == MOUSE_BUTTON_RIGHT
	var is_left_click = event.button_index == MOUSE_BUTTON_LEFT
	var command_mode_active = MatchSignals.active_command_mode != Enums.UnitCommandMode.NORMAL

	# ── Left-click in command mode: instant targeted (no drag) ──
	if is_left_click and command_mode_active and event.pressed:
		var target_point = _world_pos_from_mouse(event.position)
		if target_point != null:
			MatchSignals.terrain_targeted.emit(target_point)
		return

	# ── Right-click press: begin potential drag ──
	if is_right_click and event.pressed:
		_rclick_start_screen = event.position
		var target_point = _world_pos_from_mouse(event.position)
		if target_point != null:
			_rclick_start_world = target_point
			_rclick_dragging = true
		return

	# ── Right-click release: finish click or drag ──
	if is_right_click and not event.pressed:
		if not _rclick_dragging:
			MatchSignals.unit_targeted_this_click = false
			return
		_rclick_dragging = false
		var suppressed := MatchSignals.unit_targeted_this_click
		MatchSignals.unit_targeted_this_click = false
		var drag_dist: float = event.position.distance_to(_rclick_start_screen)
		if drag_dist < _DRAG_THRESHOLD_PX:
			# Tiny movement → treat as a normal click.
			if not suppressed:
				MatchSignals.terrain_targeted.emit(_rclick_start_world)
		else:
			var end_world = _world_pos_from_mouse(event.position)
			if end_world != null:
				MatchSignals.terrain_drag_finished.emit(_rclick_start_world, end_world)
		return


func _unhandled_input(event: InputEvent) -> void:
	if not _rclick_dragging:
		return
	if event is InputEventMouseMotion:
		var screen_pos: Vector2 = event.position
		if screen_pos.distance_to(_rclick_start_screen) < _DRAG_THRESHOLD_PX:
			return
		var current_world = _world_pos_from_mouse(screen_pos)
		if current_world != null:
			MatchSignals.terrain_drag_updated.emit(_rclick_start_world, current_world)
	# Cancel drag if right button released outside the collision body
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and not event.pressed
	):
		if _rclick_dragging:
			_rclick_dragging = false
			var suppressed := MatchSignals.unit_targeted_this_click
			MatchSignals.unit_targeted_this_click = false
			var end_world = _world_pos_from_mouse(event.position)
			if end_world != null:
				var drag_dist: float = event.position.distance_to(_rclick_start_screen)
				if drag_dist < _DRAG_THRESHOLD_PX:
					if not suppressed:
						MatchSignals.terrain_targeted.emit(_rclick_start_world)
				else:
					MatchSignals.terrain_drag_finished.emit(_rclick_start_world, end_world)


func _world_pos_from_mouse(screen_pos: Vector2) -> Variant:
	var camera = get_viewport().get_camera_3d()
	var match_node = get_parent()
	var map = match_node.map if match_node != null else null
	return camera.get_terrain_ray_intersection(screen_pos, map)
