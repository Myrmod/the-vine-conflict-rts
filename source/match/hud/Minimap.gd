extends PanelContainer

const Unit = preload("res://source/match/units/Unit.gd")
const Structure = preload("res://source/match/units/Structure.gd")
const Moving = preload("res://source/match/units/actions/Moving.gd")
const ResourceUnit = preload("res://source/match/units/non-player/ResourceUnit.gd")

const GROUND_LEVEL_PLANE = Plane(Vector3.UP, 0)
const MINIMAP_PIXELS_PER_WORLD_METER = 2

var _unit_to_corresponding_node_mapping = {}
var _orphaned_minimap_nodes = []
var _camera_movement_active = false

@onready var _match = find_parent("Match")
@onready var _camera_indicator = find_child("CameraIndicator")
@onready var _viewport_background = find_child("Background")
@onready var _texture_rect = find_child("MinimapTextureRect")
@onready var _fog_of_war_mask = find_child("FogOfWarMask")

@export var MaxSize = 100


func _ready():
	if not FeatureFlags.show_minimap:
		queue_free()
	_remove_dummy_nodes()
	await _match.ready  # make sure Match is ready as it may change map on setup
	_setup_fog_of_war_texture()

	var map_node = _match.find_child("Map")
	var viewport_size = map_node.size * MINIMAP_PIXELS_PER_WORLD_METER
	find_child("MinimapViewport").size = viewport_size

	# Replace the flat gray background with a terrain overview image
	_generate_terrain_background(map_node)

	await get_tree().process_frame

	# Fixed display size — the TextureRect's STRETCH_KEEP_ASPECT_CENTERED
	# fits the map inside this square; empty areas remain black.
	var display_size = MaxSize * 2
	custom_minimum_size = Vector2(display_size, display_size)
	_texture_rect.custom_minimum_size = Vector2(display_size, display_size)

	# Black background behind letterboxed areas
	var black_style = StyleBoxFlat.new()
	black_style.bg_color = Color.BLACK
	add_theme_stylebox_override("panel", black_style)

	_texture_rect.gui_input.connect(_on_gui_input)


func _setup_fog_of_war_texture():
	var combined_viewport: SubViewport = _match.find_child("CombinedViewport")
	if combined_viewport != null and _fog_of_war_mask != null:
		_fog_of_war_mask.material.set_shader_parameter(
			"reference_texture", combined_viewport.get_texture()
		)


func _physics_process(_delta):
	_sync_real_units_with_minimap_representations()
	_update_camera_indicator()


func _remove_dummy_nodes():
	for dummy_node in find_children("EditorOnlyDummy*"):
		dummy_node.queue_free()


func _sync_real_units_with_minimap_representations():
	var units_synced = {}
	var units_to_sync = (
		get_tree().get_nodes_in_group("units")
		+ get_tree().get_nodes_in_group("resource_units")
		+ get_tree().get_nodes_in_group("forest_vines")
	)
	for unit in units_to_sync:
		if unit is ResourceUnit or unit is ForestVine:
			if unit.in_player_vision:
				units_synced[unit] = 1
				if not _unit_is_mapped(unit):
					_map_unit(unit)
				_sync_unit(unit)
			else:
				# Not in vision: keep existing dot frozen, mark as synced so it isn't removed
				units_synced[unit] = 1
				if not _unit_is_mapped(unit):
					_map_unit(unit)
					_sync_unit(unit)
		elif unit is Structure:
			if unit.visible:
				units_synced[unit] = 1
				if not _unit_is_mapped(unit):
					_map_unit(unit)
				_sync_unit(unit)
			elif _unit_is_mapped(unit):
				# Structure in fog: keep dot frozen
				units_synced[unit] = 1
		else:
			if not unit.visible:
				continue
			units_synced[unit] = 1
			if not _unit_is_mapped(unit):
				_map_unit(unit)
			_sync_unit(unit)
	# Orphan minimap nodes for units destroyed outside vision
	var units_to_cleanup = []
	for mapped_unit in _unit_to_corresponding_node_mapping:
		if not mapped_unit in units_synced:
			if not is_instance_valid(mapped_unit):
				_orphaned_minimap_nodes.append(
					{
						"node": _unit_to_corresponding_node_mapping[mapped_unit],
						"position": _unit_to_corresponding_node_mapping[mapped_unit].position
					}
				)
			units_to_cleanup.append(mapped_unit)
	for unit in units_to_cleanup:
		if is_instance_valid(unit):
			_cleanup_mapping(unit)
		else:
			_unit_to_corresponding_node_mapping.erase(unit)
	_check_orphaned_minimap_nodes()


func _unit_is_mapped(unit):
	return unit in _unit_to_corresponding_node_mapping


func _map_unit(unit):
	var node_representing_unit = ColorRect.new()
	node_representing_unit.size = Vector2(3, 3)
	if not unit is Unit:
		node_representing_unit.rotation_degrees = 45
	_viewport_background.add_sibling(node_representing_unit)
	node_representing_unit.pivot_offset = node_representing_unit.size / 2.0
	_unit_to_corresponding_node_mapping[unit] = node_representing_unit


func _sync_unit(unit):
	var unit_pos_3d = unit.global_transform.origin
	var unit_pos_2d = Vector2(unit_pos_3d.x, unit_pos_3d.z) * MINIMAP_PIXELS_PER_WORLD_METER
	_unit_to_corresponding_node_mapping[unit].position = unit_pos_2d
	_unit_to_corresponding_node_mapping[unit].color = (
		unit.player.color if unit is Unit else unit.color
	)


func _cleanup_mapping(unit):
	_unit_to_corresponding_node_mapping[unit].queue_free()
	_unit_to_corresponding_node_mapping.erase(unit)


func _check_orphaned_minimap_nodes():
	var visibility_handler = find_parent("Match").find_child("UnitVisibilityHandler")
	if visibility_handler == null or visibility_handler._is_disabled():
		for entry in _orphaned_minimap_nodes:
			entry["node"].queue_free()
		_orphaned_minimap_nodes.clear()
		return
	var revealed_units = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit.is_in_group("revealed_units")
	)
	var to_remove = []
	for entry in _orphaned_minimap_nodes:
		var in_vision = false
		for revealed_unit in revealed_units:
			if revealed_unit.is_revealing() and revealed_unit.sight_range != null:
				var orphan_world_pos = entry["position"] / MINIMAP_PIXELS_PER_WORLD_METER
				var unit_pos = Vector2(
					revealed_unit.global_position.x, revealed_unit.global_position.z
				)
				if unit_pos.distance_to(orphan_world_pos) <= revealed_unit.sight_range + 2.0:
					in_vision = true
					break
		if in_vision:
			to_remove.append(entry)
	for entry in to_remove:
		entry["node"].queue_free()
		_orphaned_minimap_nodes.erase(entry)


func _update_camera_indicator():
	var viewport = get_viewport()
	var camera = viewport.get_camera_3d()
	var camera_corners = [
		Vector2.ZERO,
		Vector2(0, viewport.size.y),
		viewport.size,
		Vector2(viewport.size.x, 0),
		Vector2.ZERO
	]
	for index in range(camera_corners.size()):
		var corner_mapped_to_3d_position_on_ground_level = (
			GROUND_LEVEL_PLANE.intersects_ray(
				camera.project_ray_origin(camera_corners[index]),
				camera.project_ray_normal(camera_corners[index])
			)
			* MINIMAP_PIXELS_PER_WORLD_METER
		)
		_camera_indicator.set_point_position(
			index,
			Vector2(
				corner_mapped_to_3d_position_on_ground_level.x,
				corner_mapped_to_3d_position_on_ground_level.z
			)
		)


func _texture_rect_position_to_world_position(position_2d_within_texture_rect):
	assert(
		_texture_rect.stretch_mode == _texture_rect.STRETCH_KEEP_ASPECT_CENTERED,
		"world 3d position retrieval algorithm assumes 'STRETCH_KEEP_ASPECT_CENTERED'"
	)
	var texture_rect_size = _texture_rect.size
	var texture_size = _texture_rect.texture.get_size()
	var proportions = texture_rect_size / texture_size
	var scaling_factor = proportions.x if proportions.x < proportions.y else proportions.y
	var scaled_texture_size = texture_size * scaling_factor
	var scaled_texture_position_within_texture_rect = (
		(texture_rect_size - scaled_texture_size) / 2.0
	)
	var rect_containing_scaled_texture = Rect2(
		scaled_texture_position_within_texture_rect, scaled_texture_size
	)
	if rect_containing_scaled_texture.has_point(position_2d_within_texture_rect):
		var position_2d_within_minimap = (
			(position_2d_within_texture_rect - rect_containing_scaled_texture.position)
			/ scaling_factor
		)
		return position_2d_within_minimap / MINIMAP_PIXELS_PER_WORLD_METER
	return null


func _try_teleporting_camera_based_on_local_texture_rect_position(position_2d_within_texture_rect):
	var world_position_2d = _texture_rect_position_to_world_position(
		position_2d_within_texture_rect
	)
	if world_position_2d == null:
		return
	var world_position_3d = Vector3(world_position_2d.x, 0, world_position_2d.y)
	get_viewport().get_camera_3d().set_position_safely(world_position_3d)


func _issue_movement_action(position_2d_within_texture_rect):
	var world_position_2d = _texture_rect_position_to_world_position(
		position_2d_within_texture_rect
	)
	if world_position_2d == null:
		return
	var abstract_world_position_3d = Vector3(world_position_2d.x, 0, world_position_2d.y)

	#Leaving this temporarily because maybe the OG writer knew something I don't?
	#var camera = get_viewport().get_camera_3d()
	#var target_point_on_colliding_surface = camera.get_ray_intersection(
	#	camera.unproject_position(abstract_world_position_3d)
	#)
	#MatchSignals.terrain_targeted.emit(target_point_on_colliding_surface)

	#Assuming they were preparing for a 3D terrain, I'm just doing this instead
	var space_state = get_viewport().get_world_3d().direct_space_state
	var ray_from = Vector3(world_position_2d.x, 1000.0, world_position_2d.y)
	var ray_to = Vector3(world_position_2d.x, -1000.0, world_position_2d.y)
	var query = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collision_mask = 1  #Landscape Collision channel
	var result = space_state.intersect_ray(query)

	if result:
		MatchSignals.terrain_targeted.emit(result.position)
	else:
		MatchSignals.terrain_targeted.emit(abstract_world_position_3d)


func _on_gui_input(event):
	if event is InputEventMouseButton:
		if event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
			_try_teleporting_camera_based_on_local_texture_rect_position(event.position)
			_camera_movement_active = true
		if not event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
			_camera_movement_active = false
		if event.is_pressed() and event.button_index == MOUSE_BUTTON_RIGHT:
			_issue_movement_action(event.position)
	elif event is InputEventMouseMotion and _camera_movement_active:
		_try_teleporting_camera_based_on_local_texture_rect_position(event.position)


func _generate_terrain_background(map_node: Node3D) -> void:
	"""Replace the flat ColorRect background with a terrain overview."""
	var img := MinimapTerrainRenderer.generate_image_from_map(map_node)
	if img == null:
		return

	# Scale the 1px-per-cell image up to the minimap viewport resolution
	var viewport_size_i: Vector2i = find_child("MinimapViewport").size
	img.resize(viewport_size_i.x, viewport_size_i.y, Image.INTERPOLATE_NEAREST)

	var tex := ImageTexture.create_from_image(img)

	# Replace the Background ColorRect with a TextureRect
	if _viewport_background:
		var tex_rect := TextureRect.new()
		tex_rect.name = "Background"
		tex_rect.texture = tex
		tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var parent = _viewport_background.get_parent()
		var idx = _viewport_background.get_index()
		_viewport_background.queue_free()

		parent.add_child(tex_rect)
		parent.move_child(tex_rect, idx)
		_viewport_background = tex_rect
