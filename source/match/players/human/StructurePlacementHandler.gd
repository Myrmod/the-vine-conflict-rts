extends Node3D

enum BlueprintPositionValidity {
	VALID,
	COLLIDES_WITH_OBJECT,
	NOT_NAVIGABLE,
	NOT_ENOUGH_RESOURCES,
	OUT_OF_MAP,
}

const ROTATION_BY_KEY_STEP_GRID = 90.0
const ROTATION_BY_KEY_STEP_FREE = 45.0
const ROTATION_DEAD_ZONE_DISTANCE = 0.1

const MATERIALS_ROOT = "res://source/match/resources/materials/"
const BLUEPRINT_VALID_PATH = MATERIALS_ROOT + "blueprint_valid.material.tres"
const BLUEPRINT_INVALID_PATH = MATERIALS_ROOT + "blueprint_invalid.material.tres"

var _active_blueprint_node = null
var _pending_structure_radius = null
var _pending_structure_navmap_rid = null
var _pending_structure_prototype = null
var _blueprint_rotating = false
var _free_placement_mode = false

@onready var _player = get_parent()
@onready var _match = find_parent("Match")
@onready var _feedback_label = find_child("FeedbackLabel3D")


func _ready():
	_feedback_label.hide()
	MatchSignals.place_structure.connect(_on_structure_placement_request)


func _unhandled_input(event):
	if not _structure_placement_started():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_lmb_down_event(event)
	if event.is_action_pressed("rotate_structure"):
		var rotation_step = ROTATION_BY_KEY_STEP_FREE if _free_placement_mode else ROTATION_BY_KEY_STEP_GRID
		_try_rotating_blueprint_by(rotation_step)
	if event.is_action_pressed("toggle_free_placement"):
		_toggle_free_placement_mode()
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		_handle_lmb_up_event(event)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_rmb_event(event)
	if event is InputEventMouseMotion:
		_handle_mouse_motion_event(event)


func _handle_lmb_down_event(_event):
	get_viewport().set_input_as_handled()
	_start_blueprint_rotation()


func _handle_lmb_up_event(_event):
	get_viewport().set_input_as_handled()
	var blueprint_position_validity = _calculate_blueprint_position_validity()
	if blueprint_position_validity == BlueprintPositionValidity.VALID:
		_finish_structure_placement()
	elif blueprint_position_validity == BlueprintPositionValidity.NOT_ENOUGH_RESOURCES:
		MatchSignals.not_enough_resources_for_construction.emit(_player)
	_finish_blueprint_rotation()


func _handle_rmb_event(event):
	get_viewport().set_input_as_handled()
	if event.pressed:
		_finish_blueprint_rotation()
		_cancel_structure_placement()


func _handle_mouse_motion_event(_event):
	get_viewport().set_input_as_handled()
	if _blueprint_rotation_started():
		_rotate_blueprint_towards_mouse_pos()
	else:
		_set_blueprint_position_based_on_mouse_pos()
	var blueprint_position_validity = _calculate_blueprint_position_validity()
	_update_feedback_label(blueprint_position_validity)
	_update_blueprint_color(blueprint_position_validity == BlueprintPositionValidity.VALID)


func _structure_placement_started():
	return _active_blueprint_node != null


func _blueprint_rotation_started():
	return _blueprint_rotating == true


func _calculate_blueprint_position_validity():
	if _active_bluprint_out_of_map():
		return BlueprintPositionValidity.OUT_OF_MAP
	if not _player_has_enough_resources():
		return BlueprintPositionValidity.NOT_ENOUGH_RESOURCES
	var placement_validity = MatchUtils.Placement.validate_agent_placement_position(
		_active_blueprint_node.global_position,
		_pending_structure_radius,
		get_tree().get_nodes_in_group("units") + get_tree().get_nodes_in_group("resource_units"),
		_pending_structure_navmap_rid
	)
	if placement_validity == MatchUtils.Placement.COLLIDES_WITH_AGENT:
		return BlueprintPositionValidity.COLLIDES_WITH_OBJECT
	if placement_validity == MatchUtils.Placement.NOT_NAVIGABLE:
		return BlueprintPositionValidity.NOT_NAVIGABLE
	return BlueprintPositionValidity.VALID


func _player_has_enough_resources():
	var construction_cost = UnitConstants.DEFAULT_PROPERTIES[
		_pending_structure_prototype.resource_path
	]["costs"]
	return _player.has_resources(construction_cost)


func _active_bluprint_out_of_map():
	return not Geometry2D.is_point_in_polygon(
		Vector2(
			_active_blueprint_node.global_transform.origin.x,
			_active_blueprint_node.global_transform.origin.z
		),
		_match.map.get_topdown_polygon_2d()
	)


func _update_feedback_label(blueprint_position_validity):
	_feedback_label.visible = (blueprint_position_validity != BlueprintPositionValidity.VALID)
	match blueprint_position_validity:
		BlueprintPositionValidity.COLLIDES_WITH_OBJECT:
			_feedback_label.text = tr("BLUEPRINT_COLLIDES_WITH_OBJECT")
		BlueprintPositionValidity.NOT_NAVIGABLE:
			_feedback_label.text = tr("BLUEPRINT_NOT_NAVIGABLE")
		BlueprintPositionValidity.NOT_ENOUGH_RESOURCES:
			_feedback_label.text = tr("BLUEPRINT_NOT_ENOUGH_RESOURCES")
		BlueprintPositionValidity.OUT_OF_MAP:
			_feedback_label.text = tr("BLUEPRINT_OUT_OF_MAP")


func _start_structure_placement(structure_prototype):
	if _structure_placement_started():
		return
	_pending_structure_prototype = structure_prototype
	_active_blueprint_node = (
		load(UnitConstants.STRUCTURE_BLUEPRINTS[structure_prototype.resource_path])
		.instantiate()
	)
	var blueprint_origin = Vector3(-999, 0, -999)
	var camera_direction_yless = (
		(get_viewport().get_camera_3d().project_ray_normal(Vector2(0, 0)) * Vector3(1, 0, 1))
		.normalized()
	)
	var rotate_towards = blueprint_origin + camera_direction_yless.rotated(Vector3.UP, PI * 0.75)
	_active_blueprint_node.global_transform = Transform3D(Basis(), blueprint_origin).looking_at(
		rotate_towards, Vector3.UP
	)
	# Snap initial rotation to 90 degrees if grid mode is enabled
	if FeatureFlags.use_grid_based_placement:
		_snap_rotation_to_90_degrees()
	add_child(_active_blueprint_node)
	var temporary_structure_instance = _pending_structure_prototype.instantiate()
	_pending_structure_radius = temporary_structure_instance.radius
	_pending_structure_navmap_rid = (
		find_parent("Match")
		.navigation
		.get_navigation_map_rid_by_domain(temporary_structure_instance.movement_domain)
	)
	temporary_structure_instance.free()


func _set_blueprint_position_based_on_mouse_pos():
	var mouse_pos_2d = get_viewport().get_mouse_position()
	var mouse_pos_3d = get_viewport().get_camera_3d().get_ray_intersection(mouse_pos_2d)
	if mouse_pos_3d == null:
		return
	# Apply grid snapping unless free placement mode is enabled or grid placement is disabled
	var target_position = mouse_pos_3d
	if FeatureFlags.use_grid_based_placement and not _free_placement_mode:
		target_position = _snap_to_grid(mouse_pos_3d)
	_active_blueprint_node.global_transform.origin = target_position
	_feedback_label.global_transform.origin = target_position


func _update_blueprint_color(blueprint_position_is_valid):
	var material_to_set = (
		preload(BLUEPRINT_VALID_PATH)
		if blueprint_position_is_valid
		else preload(BLUEPRINT_INVALID_PATH)
	)
	for child in _active_blueprint_node.find_children("*"):
		if "material_override" in child:
			child.material_override = material_to_set


func _cancel_structure_placement():
	if _structure_placement_started():
		_feedback_label.hide()
		_active_blueprint_node.queue_free()
		_active_blueprint_node = null
		# Reset to grid mode for next placement
		_free_placement_mode = false


func _finish_structure_placement():
	if _player_has_enough_resources():
		# Resources are NOT deducted here — Match._execute_command() handles that
		# when STRUCTURE_PLACED executes. This ensures replay determinism: the same
		# resource deduction happens at the exact same tick during playback.
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.STRUCTURE_PLACED,
			"player_id": _player.id,
			"data": {
				"structure_prototype": _pending_structure_prototype.resource_path,
				"transform": _active_blueprint_node.global_transform,
				"self_constructing": true,
			}
		})
	_cancel_structure_placement()


func _start_blueprint_rotation():
	_blueprint_rotating = true


func _try_rotating_blueprint_by(degrees):
	if not _structure_placement_started():
		return
	_active_blueprint_node.global_transform.basis = (
		_active_blueprint_node.global_transform.basis.rotated(Vector3.UP, deg_to_rad(degrees))
	)
	# Snap to 90-degree increments when in grid mode
	if FeatureFlags.use_grid_based_placement and not _free_placement_mode:
		_snap_rotation_to_90_degrees()


func _rotate_blueprint_towards_mouse_pos():
	var mouse_pos_2d = get_viewport().get_mouse_position()
	var mouse_pos_3d = get_viewport().get_camera_3d().get_ray_intersection(mouse_pos_2d)
	if mouse_pos_3d == null:
		return
	var mouse_pos_yless = mouse_pos_3d * Vector3(1, 0, 1)
	var blueprint_pos_3d = _active_blueprint_node.global_transform.origin
	var blueprint_pos_yless = blueprint_pos_3d * Vector3(-999, 0, -999)
	if mouse_pos_yless.distance_to(blueprint_pos_yless) < ROTATION_DEAD_ZONE_DISTANCE:
		return
	var rotation_target = Vector3(mouse_pos_yless.x, blueprint_pos_3d.y, mouse_pos_yless.z)
	if rotation_target.is_equal_approx(_active_blueprint_node.global_transform.origin):
		return
	_active_blueprint_node.global_transform = _active_blueprint_node.global_transform.looking_at(
		rotation_target, Vector3.UP
	)
	# Snap to 90-degree increments when in grid mode
	if FeatureFlags.use_grid_based_placement and not _free_placement_mode:
		_snap_rotation_to_90_degrees()


func _finish_blueprint_rotation():
	_blueprint_rotating = false


func _toggle_free_placement_mode():
	_free_placement_mode = not _free_placement_mode
	# Update blueprint position to snap/unsnap from grid
	if _structure_placement_started():
		_set_blueprint_position_based_on_mouse_pos()


func _snap_to_grid(position: Vector3) -> Vector3:
	var grid_size = FeatureFlags.grid_cell_size
	return Vector3(
		round(position.x / grid_size) * grid_size,
		position.y,
		round(position.z / grid_size) * grid_size
	)


func _snap_rotation_to_90_degrees():
	# Defensive check - although callers should ensure blueprint exists, 
	# this prevents potential issues if called incorrectly
	if not _structure_placement_started():
		return
	# Get current Y rotation in degrees
	var current_rotation = _active_blueprint_node.rotation.y
	var current_degrees = rad_to_deg(current_rotation)
	# Round to nearest 90 degrees
	var snapped_degrees = round(current_degrees / 90.0) * 90.0
	# Apply snapped rotation
	_active_blueprint_node.rotation.y = deg_to_rad(snapped_degrees)


func _on_structure_placement_request(structure_prototype):
	_start_structure_placement(structure_prototype)
