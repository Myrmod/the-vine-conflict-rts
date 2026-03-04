extends NavigationObstacle3D

@export var domain = NavigationConstants.Domain.TERRAIN
@export var path_height_offset = 0.0

## Determines which terrain cell types this unit can occupy.
@export var terrain_move_type: NavigationConstants.TerrainMoveType = (
	NavigationConstants.TerrainMoveType.LAND
)

@onready var _match = find_parent("Match")
@onready var _unit = get_parent()


func _ready():
	await get_tree().process_frame  # wait for navigation to be operational
	if _match:
		set_navigation_map(_match.navigation.get_navigation_map_rid_by_domain(domain))
		_align_unit_position_to_navigation()
		_affect_navigation_if_needed()


func _exit_tree():
	if affect_navigation_mesh:
		remove_from_group(NavigationConstants.DOMAIN_TO_GROUP_MAPPING[domain])
		MatchSignals.schedule_navigation_rebake.emit(domain)


func _align_unit_position_to_navigation():
	_unit.global_transform.origin = (
		NavigationServer3D.map_get_closest_point(
			get_navigation_map(), get_parent().global_transform.origin
		)
		- Vector3(0, path_height_offset, 0)
	)


func _affect_navigation_if_needed():
	if affect_navigation_mesh:
		add_to_group(NavigationConstants.DOMAIN_TO_GROUP_MAPPING[domain])
		MatchSignals.schedule_navigation_rebake.emit(domain)
