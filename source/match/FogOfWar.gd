# FOG OF WAR SYSTEM: Renders what each player can see on the map.
# The \"revealed_units\" group (created by Match._setup_unit_groups()) drives visibility.
# Units in \"revealed_units\" are visible; others are in fog of war.
#
# HOW TEAM VISION WORKS:
# - Match._setup_unit_groups() adds units to \"revealed_units\" if:
#   1. Their controlling player is visible to the human player, OR
#   2. Their controlling player is on the same TEAM as a visible player
# - When a teammate's unit is added to \"revealed_units\", FogOfWar sees it and reveals it
# - This creates automatic team vision: all playable teammates share sight automatically
#
# RENDERING:
# - Revealed units: rendered with vision circles in the viewport
# - Unrevealed units: hidden by fog texture overlay
# - \"shroud\" areas: never seen before
# - \"fog\" areas: seen before but currently hidden
extends Node3D

const DynamicCircle2D = preload("res://source/generic-scenes-and-nodes/2d/DynamicCircle2D.tscn")

const DEFAULT_SIZE = Vector2i(100, 100)

@export_range(1, 10) var texture_units_per_world_unit = 2  # px/m
@export var fog_circle_color = Color(0.25, 0.25, 0.25)
@export var shroud_circle_color = Color(1.0, 1.0, 1.0)
## When true, the entire map starts as "explored" (semi-transparent fog)
## instead of fully black shroud. Units still need vision to fully reveal areas.
@export var start_explored: bool = true

var _unit_to_circles_mapping = {}

@onready var _revealer = find_child("Revealer")
@onready var _fog_viewport = find_child("FogViewport")
@onready var _fog_viewport_container = find_child("FogViewportContainer")
@onready var _combined_viewport = find_child("CombinedViewport")
@onready var _screen_overlay = find_child("ScreenOverlay")


func _ready():
	if _fog_viewport.size == DEFAULT_SIZE:
		resize(find_parent("Match").find_child("Map").size)
	# Assign viewport texture in code to avoid _setup_local_to_scene() timing error
	_screen_overlay.material_override.set_shader_parameter(
		"world_visibility_texture", _combined_viewport.get_texture()
	)
	_screen_overlay.material_override.set_shader_parameter(
		"texture_units_per_world_unit", texture_units_per_world_unit
	)
	if start_explored:
		find_child("Background").color = fog_circle_color
	_revealer.hide()
	find_child("EditorOnlyCircle").queue_free()


func _physics_process(_delta):
	# Sync vision circles for all currently revealed units
	# This updates the fog texture every frame based on what units can see
	var units_synced = {}
	var units_to_sync = get_tree().get_nodes_in_group("revealed_units")
	for unit in units_to_sync:
		if not unit.is_revealing():
			continue
		units_synced[unit] = 1
		if not _unit_is_mapped(unit):
			_map_unit_to_new_circles(unit)
		_sync_circles_to_unit(unit)
	for mapped_unit in _unit_to_circles_mapping:
		if not mapped_unit in units_synced:
			_cleanup_mapping(mapped_unit)


func reveal():
	_revealer.show()


func resize(map_size: Vector2):
	_fog_viewport.size = map_size * texture_units_per_world_unit
	_combined_viewport.size = map_size * texture_units_per_world_unit


func _unit_is_mapped(unit):
	return unit in _unit_to_circles_mapping


func _map_unit_to_new_circles(unit):
	var sight_range: float = _get_unit_sight_range(unit)
	var shroud_circle = DynamicCircle2D.instantiate()
	shroud_circle.color = fog_circle_color
	shroud_circle.radius = sight_range * texture_units_per_world_unit
	_fog_viewport.add_child(shroud_circle)
	var fow_circle = DynamicCircle2D.instantiate()
	fow_circle.color = shroud_circle_color
	fow_circle.radius = sight_range * texture_units_per_world_unit
	_fog_viewport_container.add_sibling(fow_circle)
	_unit_to_circles_mapping[unit] = [shroud_circle, fow_circle]


func _sync_circles_to_unit(unit):
	var unit_pos_3d = unit.global_transform.origin
	var unit_pos_2d = Vector2(unit_pos_3d.x, unit_pos_3d.z) * texture_units_per_world_unit
	var effective_sight: float = _get_unit_sight_range(unit)
	if "forest_zones_inside" in unit and unit.forest_zones_inside > 0:
		var forest_sight_multiplier: float = _get_unit_forest_sight_multiplier(unit)
		effective_sight *= forest_sight_multiplier
	var radius = effective_sight * texture_units_per_world_unit
	_unit_to_circles_mapping[unit][0].radius = radius
	_unit_to_circles_mapping[unit][1].radius = radius
	_unit_to_circles_mapping[unit][0].position = unit_pos_2d
	_unit_to_circles_mapping[unit][1].position = unit_pos_2d


func _get_unit_sight_range(unit) -> float:
	var raw_sight_range: Variant = unit.get("sight_range")
	if raw_sight_range == null:
		return 0.0
	return float(raw_sight_range)


func _get_unit_forest_sight_multiplier(unit) -> float:
	var raw_multiplier: Variant = unit.get("forest_sight_multiplier")
	if raw_multiplier == null:
		return 1.0
	return float(raw_multiplier)


func _cleanup_mapping(unit):
	_unit_to_circles_mapping[unit][0].queue_free()
	_unit_to_circles_mapping[unit][1].queue_free()
	_unit_to_circles_mapping.erase(unit)
