extends Node3D

var _static_obstacles = []

@onready var air = find_child("Air")
@onready var terrain = find_child("Terrain")

@onready var _match = find_parent("Match")


func _ready():
	if Engine.is_editor_hint():
		return
	await _match.ready
	_setup_static_obstacles()


func get_navigation_map_rid_by_domain(domain):
	if Engine.is_editor_hint():
		return null
	return {
		NavigationConstants.Domain.AIR: air.navigation_map_rid,
		NavigationConstants.Domain.TERRAIN: terrain.navigation_map_rid,
	}[domain]


func setup(map):
	if Engine.is_editor_hint():
		return
	assert(_static_obstacles.is_empty())
	air.bake(map)
	terrain.bake(map)
	_setup_static_obstacles()


func _setup_static_obstacles():
	if Engine.is_editor_hint():
		return
	if not _static_obstacles.is_empty():
		return
	for domain in [NavigationConstants.Domain.AIR, NavigationConstants.Domain.TERRAIN]:
		var obstacle = NavigationServer3D.obstacle_create()
		NavigationServer3D.obstacle_set_map(obstacle, get_navigation_map_rid_by_domain(domain))
		var obstacle_y = {
			NavigationConstants.Domain.AIR: Air.Y,
			NavigationConstants.Domain.TERRAIN: 0,
		}[domain]
		NavigationServer3D.obstacle_set_position(obstacle, Vector3(0, obstacle_y, 0))
		var obstacle_vertices = [
			Vector3(0, 0, 0),
			Vector3(0, 0, _match.map.size.y),
			Vector3(_match.map.size.x, 0, _match.map.size.y),
			Vector3(_match.map.size.x, 0, 0),
		]
		NavigationServer3D.obstacle_set_vertices(obstacle, obstacle_vertices)
		NavigationServer3D.obstacle_set_avoidance_enabled(obstacle, true)
		_static_obstacles.append(obstacle)
