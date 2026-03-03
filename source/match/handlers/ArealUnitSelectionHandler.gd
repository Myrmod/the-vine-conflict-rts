extends Node3D

const Structure = preload("res://source/match/units/Structure.gd")

@export var rectangular_selection_3d: NodePath

var _rectangular_selection_3d = null
var _highlighted_units = Utils.Set.new()


func _ready():
	_rectangular_selection_3d = get_node_or_null(rectangular_selection_3d)
	if _rectangular_selection_3d == null:
		return
	_rectangular_selection_3d.started.connect(_on_selection_started)
	_rectangular_selection_3d.interrupted.connect(_on_selection_interrupted)
	_rectangular_selection_3d.finished.connect(_on_selection_finished)


func _force_highlight(units_to_highlight):
	for unit in units_to_highlight.iterate():
		var highlight = unit.find_child("Highlight")
		if highlight != null:
			highlight.force()


func _unforce_highlight(units_not_to_highlight_anymore):
	for unit in units_not_to_highlight_anymore.iterate():
		if unit == null:
			continue
		var highlight = unit.find_child("Highlight")
		if highlight != null:
			highlight.unforce()


func _get_controlled_units_from_navigation_domain_within_topdown_polygon_2d(
	navigation_domain, topdown_polygon_2d
):
	if topdown_polygon_2d == null:
		return Utils.Set.new()
	var units_within_polygon = Utils.Set.new()
	var camera = get_viewport().get_camera_3d()
	for unit in get_tree().get_nodes_in_group("controlled_units"):
		if not unit.visible or not _matches_nav_domain(unit, navigation_domain):
			continue
		# Project the unit's 3D position to screen space, then check if the
		# screen point falls inside the selection rectangle.  This makes the
		# selection independent of the unit's Y position (height layer).
		var screen_pos: Vector2 = camera.unproject_position(unit.global_transform.origin)
		# Convert the topdown polygon back to screen-space for the check.
		# The polygon was built from the screen rect projected onto y=0.  We
		# convert it to screen points so the comparison is height-agnostic.
		var screen_polygon: PackedVector2Array = PackedVector2Array()
		for pt: Vector2 in topdown_polygon_2d:
			var world_pt := Vector3(pt.x, 0.0, pt.y)
			screen_polygon.append(camera.unproject_position(world_pt))
		if Geometry2D.is_point_in_polygon(screen_pos, screen_polygon):
			units_within_polygon.add(unit)
	return units_within_polygon


func _rebase_topdown_polygon_2d_to_different_plane(topdown_polygon_2d, plane):
	var rebased_topdown_polygon_2d = []
	var camera = get_viewport().get_camera_3d()
	for polygon_point_2d in topdown_polygon_2d:
		var screen_point_2d = camera.unproject_position(
			Vector3(polygon_point_2d.x, Terrain.PLANE.d, polygon_point_2d.y)
		)
		var rebased_point_3d = camera.get_ray_intersection_with_plane(screen_point_2d, plane)
		rebased_topdown_polygon_2d.append(Vector2(rebased_point_3d.x, rebased_point_3d.z))
	return rebased_topdown_polygon_2d


func _on_selection_started():
	_rectangular_selection_3d.changed.connect(_on_selection_changed)


func _on_selection_changed(topdown_polygon_2d):
	var units_to_highlight = _get_controlled_units_from_navigation_domain_within_topdown_polygon_2d(
		NavigationConstants.Domain.TERRAIN, topdown_polygon_2d
	)
	units_to_highlight.merge(
		_get_controlled_units_from_navigation_domain_within_topdown_polygon_2d(
			NavigationConstants.Domain.AIR,
			_rebase_topdown_polygon_2d_to_different_plane(topdown_polygon_2d, Air.PLANE)
		)
	)
	var units_not_to_highlight_anymore = Utils.Set.subtracted(
		_highlighted_units, units_to_highlight
	)
	_force_highlight(units_to_highlight)
	_unforce_highlight(units_not_to_highlight_anymore)
	_highlighted_units = units_to_highlight


func _on_selection_interrupted():
	_rectangular_selection_3d.changed.disconnect(_on_selection_changed)
	_unforce_highlight(_highlighted_units)
	_highlighted_units = Utils.Set.new()


func _on_selection_finished(topdown_polygon_2d):
	_rectangular_selection_3d.changed.disconnect(_on_selection_changed)
	_unforce_highlight(_highlighted_units)
	_highlighted_units = Utils.Set.new()
	var units_to_select = _get_controlled_units_from_navigation_domain_within_topdown_polygon_2d(
		NavigationConstants.Domain.TERRAIN, topdown_polygon_2d
	)
	units_to_select.merge(
		_get_controlled_units_from_navigation_domain_within_topdown_polygon_2d(
			NavigationConstants.Domain.AIR,
			_rebase_topdown_polygon_2d_to_different_plane(topdown_polygon_2d, Air.PLANE)
		)
	)
	# Prefer non-structure units: if any mobile unit is in the selection,
	# exclude structures so they don't clutter the selection
	var non_structures = Utils.Set.new()
	for unit in units_to_select.iterate():
		if not (unit is Structure):
			non_structures.add(unit)
	if not non_structures.empty():
		units_to_select = non_structures
	MatchUtils.select_units(units_to_select)


func _matches_nav_domain(unit, navigation_domain: NavigationConstants.Domain) -> bool:
	"""Check if a unit belongs to the given navigation domain."""
	return unit.get_nav_domain() == navigation_domain
