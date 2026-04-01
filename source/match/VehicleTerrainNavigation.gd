extends Node3D

const DOMAIN = NavigationConstants.Domain.TERRAIN_VEHICLE

var navigation_map_rid: RID

var _earliest_frame_to_perform_next_rebake = null
var _is_baking = false
var _map_geometry = NavigationMeshSourceGeometryData3D.new()
var _navigation_region: NavigationRegion3D


func _ready():
	navigation_map_rid = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(navigation_map_rid, Terrain.CELL_SIZE)
	NavigationServer3D.map_set_cell_height(navigation_map_rid, Terrain.CELL_HEIGHT)
	NavigationServer3D.map_set_active(navigation_map_rid, true)
	NavigationServer3D.map_force_update(navigation_map_rid)

	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_BOTH
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SourceGeometryMode.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nav_mesh.geometry_source_group_name = &"vehicle_terrain_navigation_input"
	nav_mesh.geometry_collision_mask = 4278190082
	nav_mesh.cell_size = Terrain.CELL_SIZE
	nav_mesh.cell_height = Terrain.CELL_HEIGHT
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = Terrain.MAX_AGENT_RADIUS
	nav_mesh.agent_max_climb = 0.0
	nav_mesh.edge_max_error = 1.0

	_navigation_region = NavigationRegion3D.new()
	_navigation_region.navigation_mesh = nav_mesh
	add_child(_navigation_region)
	NavigationServer3D.region_set_map(_navigation_region.get_region_rid(), navigation_map_rid)

	MatchSignals.schedule_navigation_rebake.connect(_on_schedule_navigation_rebake)


func _process(_delta):
	if (
		not _is_baking
		and _earliest_frame_to_perform_next_rebake != null
		and get_tree().get_frame() >= _earliest_frame_to_perform_next_rebake
	):
		_is_baking = true
		_earliest_frame_to_perform_next_rebake = null
		_rebake()


func bake(map, base_terrain_geometry: NavigationMeshSourceGeometryData3D):
	_navigation_region.navigation_mesh.filter_baking_aabb = AABB(
		Vector3.ZERO, Vector3(map.size.x, 5.0, map.size.y)
	)
	# Parse vehicle-specific obstacles (forest vines + dual-registered terrain obstacles)
	NavigationServer3D.parse_source_geometry_data(
		_navigation_region.navigation_mesh, _map_geometry, get_tree().root
	)
	# Merge the base terrain ground geometry (ground plane, cliffs, water edges)
	_map_geometry.merge(base_terrain_geometry)
	for node in get_tree().get_nodes_in_group("vehicle_terrain_navigation_input"):
		node.remove_from_group("vehicle_terrain_navigation_input")
	NavigationServer3D.bake_from_source_geometry_data(
		_navigation_region.navigation_mesh, _map_geometry
	)
	_sync_navmesh_changes()


func _rebake():
	var full_geometry = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(
		_navigation_region.navigation_mesh, full_geometry, get_tree().root
	)
	full_geometry.merge(_map_geometry)
	NavigationServer3D.bake_from_source_geometry_data_async(
		_navigation_region.navigation_mesh, full_geometry, _on_bake_finished
	)


func _sync_navmesh_changes():
	_navigation_region.navigation_mesh = _navigation_region.navigation_mesh


func rebake_sync() -> void:
	var full_geometry = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(
		_navigation_region.navigation_mesh, full_geometry, get_tree().root
	)
	full_geometry.merge(_map_geometry)
	NavigationServer3D.bake_from_source_geometry_data(
		_navigation_region.navigation_mesh, full_geometry
	)
	_sync_navmesh_changes()


func _on_schedule_navigation_rebake(domain):
	if domain != DOMAIN or not is_inside_tree() or not FeatureFlags.allow_navigation_rebaking:
		return
	if _earliest_frame_to_perform_next_rebake == null:
		_earliest_frame_to_perform_next_rebake = get_tree().get_frame() + 1


func _on_bake_finished():
	_sync_navmesh_changes()
	_is_baking = false
