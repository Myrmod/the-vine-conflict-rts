extends Node3D

enum BlueprintPositionValidity {
	VALID,
	COLLIDES_WITH_OBJECT,
	NOT_NAVIGABLE,
	NOT_ENOUGH_RESOURCES,
	OUT_OF_MAP,
	OUTSIDE_BUILD_RADIUS,
	WRONG_TERRAIN,
	NOT_ON_CREEP,
	NO_AVAILABLE_SEEDLING,
	NOT_ON_RESOURCE_SPAWNER,
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
var _pending_structure_placement_domains = []
var _pending_skip_nav_check = false
var _blueprint_rotating = false
var _free_placement_mode = false
var _off_field_deploy = false
var _is_trickle = false
var _off_field_producer_id: int = -1
var _pending_requires_creep: bool = false
var _pending_requires_seedling: bool = false
var _pending_requires_resource_spawner: bool = false
var _pending_resource_spawner_height_offset: float = 0.0

const _RESOURCE_SPAWNER_SNAP_RADIUS: float = 2.0

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
		var rotation_step = (
			ROTATION_BY_KEY_STEP_FREE if _free_placement_mode else ROTATION_BY_KEY_STEP_GRID
		)
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
	if not _off_field_deploy and not _is_trickle and not _player_has_enough_resources():
		return BlueprintPositionValidity.NOT_ENOUGH_RESOURCES
	if (
		FeatureFlags.use_grid_based_placement
		and not (
			BuildRadius
			. is_position_in_any_build_radius(
				get_tree(),
				_active_blueprint_node.global_position,
				_player,
				_get_placement_domain(),
			)
		)
	):
		return BlueprintPositionValidity.OUTSIDE_BUILD_RADIUS
	if not _placement_domains_match_terrain():
		return BlueprintPositionValidity.WRONG_TERRAIN
	if (
		_pending_requires_creep
		and not RadixStructure.is_creep_at_position(_active_blueprint_node.global_position)
	):
		return BlueprintPositionValidity.NOT_ON_CREEP
	if _pending_requires_seedling and not _player_has_available_seedling():
		return BlueprintPositionValidity.NO_AVAILABLE_SEEDLING
	if _pending_requires_resource_spawner:
		if _get_resource_spawner_at_blueprint() == null:
			return BlueprintPositionValidity.NOT_ON_RESOURCE_SPAWNER
		return BlueprintPositionValidity.VALID
	var placement_validity = MatchUtils.Placement.validate_agent_placement_position(
		_active_blueprint_node.global_position,
		_pending_structure_radius,
		(
			get_tree().get_nodes_in_group("units")
			+ get_tree().get_nodes_in_group("resource_units")
			+ get_tree().get_nodes_in_group("forest_vines")
		),
		_pending_structure_navmap_rid,
		_pending_skip_nav_check
	)
	if placement_validity == MatchUtils.Placement.COLLIDES_WITH_AGENT:
		return BlueprintPositionValidity.COLLIDES_WITH_OBJECT
	if placement_validity == MatchUtils.Placement.NOT_NAVIGABLE:
		return BlueprintPositionValidity.NOT_NAVIGABLE
	return BlueprintPositionValidity.VALID


func _player_has_enough_resources():
	var construction_cost = (
		UnitConstants
		. get_default_properties(
			UnitConstants.get_scene_id(_pending_structure_prototype.resource_path)
		)["costs"]
	)
	return _player.has_resources(construction_cost)


func _active_bluprint_out_of_map():
	return not Geometry2D.is_point_in_polygon(
		Vector2(
			_active_blueprint_node.global_transform.origin.x,
			_active_blueprint_node.global_transform.origin.z
		),
		_match.map.get_topdown_polygon_2d()
	)


func _placement_domains_match_terrain() -> bool:
	if _pending_structure_placement_domains.is_empty():
		return true
	var map = _match.map if _match != null else null
	if map == null or map.cell_type_grid.is_empty():
		return true
	var cell_type = map.get_cell_type_at_world(_active_blueprint_node.global_position)
	if cell_type == MapResource.CELL_WATER:
		return Enums.PlacementTypes.WATER in _pending_structure_placement_domains
	elif cell_type == MapResource.CELL_SLOPE or cell_type == MapResource.CELL_WATER_SLOPE:
		return Enums.PlacementTypes.SLOPE in _pending_structure_placement_domains
	else:
		return Enums.PlacementTypes.LAND in _pending_structure_placement_domains


## Returns the PlacementTypes domain based on the actual terrain at the blueprint position.
## Used to check the correct build radius (land uses normal, water uses expanded).
func _get_placement_domain() -> Enums.PlacementTypes:
	var map = _match.map if _match != null else null
	if map != null and not map.cell_type_grid.is_empty():
		var cell_type = map.get_cell_type_at_world(_active_blueprint_node.global_position)
		if cell_type == MapResource.CELL_WATER:
			return Enums.PlacementTypes.WATER
	return Enums.PlacementTypes.LAND


func _is_water_building() -> bool:
	return Enums.PlacementTypes.WATER in _pending_structure_placement_domains


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
		BlueprintPositionValidity.OUTSIDE_BUILD_RADIUS:
			_feedback_label.text = tr("BLUEPRINT_OUTSIDE_BUILD_RADIUS")
		BlueprintPositionValidity.WRONG_TERRAIN:
			_feedback_label.text = tr("BLUEPRINT_WRONG_TERRAIN")
		BlueprintPositionValidity.NOT_ON_CREEP:
			_feedback_label.text = tr("BLUEPRINT_NOT_ON_CREEP")
		BlueprintPositionValidity.NO_AVAILABLE_SEEDLING:
			_feedback_label.text = "A Seedling is required"
		BlueprintPositionValidity.NOT_ON_RESOURCE_SPAWNER:
			_feedback_label.text = "Must be placed above a Resource Spawner"


func _start_structure_placement(structure_prototype):
	if _structure_placement_started():
		return
	_pending_structure_prototype = structure_prototype
	var temporary_structure_instance = _pending_structure_prototype.instantiate()
	_pending_structure_radius = _get_structure_radius(temporary_structure_instance)
	_pending_structure_placement_domains = (
		Array(temporary_structure_instance.get("placement_domains"))
		if temporary_structure_instance.get("placement_domains") != null
		else []
	)
	_pending_requires_creep = (temporary_structure_instance.get("requires_creep") == true)
	_pending_requires_seedling = (
		temporary_structure_instance.get("requires_seedling_to_start") == true
	)
	_pending_requires_resource_spawner = (
		temporary_structure_instance.get("requires_resource_spawner") == true
	)
	_pending_resource_spawner_height_offset = float(
		(
			temporary_structure_instance.get("resource_spawner_height_offset")
			if temporary_structure_instance.get("resource_spawner_height_offset") != null
			else 0.0
		)
	)
	_pending_structure_navmap_rid = (
		find_parent("Match")
		. navigation
		. get_navigation_map_rid_by_domain(_get_structure_nav_domain(temporary_structure_instance))
	)
	var geometry = temporary_structure_instance.find_child("Geometry")
	if geometry != null:
		geometry.get_parent().remove_child(geometry)
		_active_blueprint_node = geometry
	else:
		_active_blueprint_node = Node3D.new()
	var structure_radius = _get_structure_radius(temporary_structure_instance)
	var structure_placement_domains = (
		Array(temporary_structure_instance.get("placement_domains"))
		if temporary_structure_instance.get("placement_domains") != null
		else []
	)
	var structure_nav_domain = _get_structure_nav_domain(temporary_structure_instance)
	var movement_obstacle = temporary_structure_instance.find_child("MovementObstacle")
	var skip_nav = movement_obstacle != null and movement_obstacle.affect_navigation_mesh
	temporary_structure_instance.free()
	var blueprint_origin = Vector3(-999, 0, -999)
	var camera_direction_yless = (
		(get_viewport().get_camera_3d().project_ray_normal(Vector2(0, 0)) * Vector3(1, 0, 1))
		. normalized()
	)
	var rotate_towards = blueprint_origin + camera_direction_yless.rotated(Vector3.UP, PI * 0.75)
	_active_blueprint_node.global_transform = Transform3D(Basis(), blueprint_origin).looking_at(
		rotate_towards, Vector3.UP
	)
	# Snap initial rotation to 90 degrees if grid mode is enabled
	if FeatureFlags.use_grid_based_placement:
		_snap_rotation_to_90_degrees()
	add_child(_active_blueprint_node)
	_pending_structure_radius = structure_radius
	_pending_structure_placement_domains = structure_placement_domains
	_pending_skip_nav_check = skip_nav
	_pending_structure_navmap_rid = (
		find_parent("Match").navigation.get_navigation_map_rid_by_domain(structure_nav_domain)
	)
	MatchSignals.current_placement_domains = _pending_structure_placement_domains
	MatchSignals.structure_placement_started.emit()
	# Position blueprint at current mouse immediately so it's visible
	# without requiring a mouse move first.
	_set_blueprint_position_based_on_mouse_pos()


func _get_structure_radius(structure_node: Node) -> float:
	if structure_node == null:
		return 0.0
	var radius_value = structure_node.get("radius")
	if radius_value != null:
		return float(radius_value)
	var movement_obstacle = structure_node.find_child("MovementObstacle")
	if movement_obstacle != null and movement_obstacle.get("radius") != null:
		return float(movement_obstacle.get("radius"))
	return 0.0


func _get_structure_nav_domain(structure_node: Node) -> NavigationConstants.Domain:
	if structure_node != null and structure_node.has_method("get_nav_domain"):
		return structure_node.get_nav_domain()
	var movement_obstacle = (
		structure_node.find_child("MovementObstacle") if structure_node != null else null
	)
	if movement_obstacle != null and movement_obstacle.get("domain") != null:
		return movement_obstacle.get("domain")
	return NavigationConstants.Domain.TERRAIN


func _set_blueprint_position_based_on_mouse_pos():
	var mouse_pos_2d = get_viewport().get_mouse_position()
	var camera = get_viewport().get_camera_3d()
	var map = _match.map if _match != null else null
	var mouse_pos_3d = camera.get_terrain_ray_intersection(mouse_pos_2d, map)
	if mouse_pos_3d == null:
		return
	# Apply grid snapping unless free placement mode is enabled or grid placement is disabled
	var target_position = mouse_pos_3d
	if FeatureFlags.use_grid_based_placement and not _free_placement_mode:
		target_position = _snap_to_grid(mouse_pos_3d)
		# Re-query terrain height at the snapped XZ so buildings on high ground
		# sit at the correct elevation instead of using the pre-snap height.
		if map != null:
			target_position.y = map.get_height_at_world(target_position)
	# Water buildings sit at Y=0 (above the water surface at Y=-0.5) to
	# avoid z-fighting that hides the blueprint and construction outlines.
	if _is_water_building() and map != null:
		target_position.y = 0.0
	if _pending_requires_resource_spawner:
		var spawner := _find_nearest_resource_spawner(
			target_position, _RESOURCE_SPAWNER_SNAP_RADIUS
		)
		if spawner != null:
			target_position = spawner.global_position
			target_position.y += _pending_resource_spawner_height_offset
	_active_blueprint_node.global_transform.origin = target_position
	_feedback_label.global_transform.origin = target_position


func _get_resource_spawner_at_blueprint() -> ResourceSpawner:
	if not _structure_placement_started():
		return null
	return _find_nearest_resource_spawner(
		_active_blueprint_node.global_position, _RESOURCE_SPAWNER_SNAP_RADIUS
	)


func _find_nearest_resource_spawner(world_pos: Vector3, radius: float) -> ResourceSpawner:
	var best: ResourceSpawner = null
	var best_dist_sq: float = INF
	var world_pos_yless: Vector3 = world_pos * Vector3(1, 0, 1)
	var radius_sq: float = radius * radius
	for node: Node in get_tree().get_nodes_in_group("resource_spawners"):
		if (
			UnitConstants.get_scene_id(node.scene_file_path)
			!= Enums.SceneId.NEUTRAL_RESOURCE_SPAWNER
		):
			continue
		if not (node is ResourceSpawner):
			continue
		var dist_sq: float = node.global_position_yless.distance_squared_to(world_pos_yless)
		if dist_sq > radius_sq:
			continue
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = node
	return best


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
		_off_field_deploy = false
		_is_trickle = false
		_off_field_producer_id = -1
		_pending_requires_seedling = false
		_pending_requires_resource_spawner = false
		_pending_resource_spawner_height_offset = 0.0
		MatchSignals.structure_placement_ended.emit()


func _player_has_available_seedling() -> bool:
	for child in _player.get_children():
		if UnitConstants.get_scene_id(child.scene_file_path) != Enums.SceneId.RADIX_SEEDLING:
			continue
		if child.action != null and child.action is Actions.Constructing:
			continue
		return true
	return false


func _finish_structure_placement():
	var can_place = _off_field_deploy or _is_trickle or _player_has_enough_resources()
	if can_place:
		var structure_scene_id: int = UnitConstants.get_scene_id(
			_pending_structure_prototype.resource_path
		)
		if structure_scene_id == Enums.SceneId.INVALID:
			_cancel_structure_placement()
			return
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.STRUCTURE_PLACED,
					"player_id": _player.id,
					"data":
					{
						"structure_prototype": structure_scene_id,
						"transform": _active_blueprint_node.global_transform,
						"self_constructing": true,
						"off_field_deploy": _off_field_deploy,
						"trickle": _is_trickle,
						"producer_id": _off_field_producer_id,
					}
				}
			)
		)
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
	var camera = get_viewport().get_camera_3d()
	var map = _match.map if _match != null else null
	var mouse_pos_3d = camera.get_terrain_ray_intersection(mouse_pos_2d, map)
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


func _snap_to_grid(_position: Vector3) -> Vector3:
	var grid_size = FeatureFlags.grid_cell_size
	return Vector3(
		floor(_position.x / grid_size) * grid_size + grid_size * 0.5,
		_position.y,
		floor(_position.z / grid_size) * grid_size + grid_size * 0.5
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
	_off_field_deploy = MatchSignals.pending_off_field_deploy
	_is_trickle = MatchSignals.pending_trickle
	_off_field_producer_id = MatchSignals.pending_off_field_producer_id
	MatchSignals.pending_off_field_deploy = false
	MatchSignals.pending_trickle = false
	MatchSignals.pending_off_field_producer_id = -1
	_start_structure_placement(structure_prototype)
