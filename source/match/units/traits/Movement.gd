extends NavigationAgent3D

signal movement_finished
signal passive_movement_started
signal passive_movement_finished

const INITIAL_DISPERSION_FACTOR: float = 0.1

const STUCK_PREVENTION_ENABLED: bool = true
const STUCK_PREVENTION_WINDOW_SIZE: int = 10  # number of frames for accumulating distance traveled
const STUCK_PREVENTION_THRESHOLD: float = 0.3  # fraction of expected distance traveled at full speed
const STUCK_PREVENTION_SIDE_MOVES: int = 15  # number of forced moves to the side if stuck

const ROTATION_LOW_PASS_FILTER_ENABLED: bool = true
const ROTATION_LOW_PASS_FILTER_WINDOW_SIZE: int = 10  # number of frames for accumulating directions
const ROTATION_LOW_PASS_FILTER_VELOCITY_THRESHOLD: float = 0.01  # velocities below will be dropped

const PASSIVE_MOVEMENT_TRACKING_ENABLED: bool = true

const AIR_HEIGHT_ADJUST_SPEED: float = 6.0  # lerp rate for flying units adjusting to terrain height

@export var domain: NavigationConstants.Domain = NavigationConstants.Domain.TERRAIN
@export var speed: float = 4.0

## Determines which terrain cell types this unit can walk on.
## AIR ignores terrain entirely; LAND avoids water; WATER avoids dry land.
@export var terrain_move_type: NavigationConstants.TerrainMoveType = (
	NavigationConstants.TerrainMoveType.LAND
)

var _interim_speed: float = 0.0

var _stuck_prevention_window: Array[float] = []
var _total_velocity_in_stuck_prevention_window: float = 0.0
var _number_of_forced_side_moves_left: int = 0

var _rotation_low_pass_filter_window: Array[Vector3] = []
var _total_direction_in_the_low_pass_filter_window: Vector3 = Vector3.ZERO
var _previously_set_global_transform_of_unit: Variant = null

var _passive_movement_detected: bool = false

## When true, the unit moves without rotating (reverse gear). Set by ReverseMoving action.
var reverse_moving: bool = false

@onready var _match: Match = find_parent("Match") as Match
@onready var _unit: Node3D = get_parent() as Node3D


func _physics_process(delta: float) -> void:
	_interim_speed = speed * delta

	# Water units move directly toward their target instead of following the
	# navmesh path.  The terrain navmesh covers land+water, so an Agent3D path
	# may route through land cells which _can_enter_position blocks, causing
	# wiggling.  Water areas are open, so pathfinding is unnecessary.
	if terrain_move_type == NavigationConstants.TerrainMoveType.WATER:
		_process_water_movement()
		return

	# The navmesh is flat (Y=0 for terrain, Y=Air.Y for air) but the unit may
	# sit at a different height (e.g. terrain height or air height over high ground).
	# NavigationAgent3D uses 3D distance for waypoint advancement, so the Y gap
	# prevents it from ever reaching the next waypoint.  Drop to navmesh height
	# for all navigation queries, then restore after set_velocity().
	var nav_y: float = Air.Y if domain == NavigationConstants.Domain.AIR else 0.0
	var real_y: float = _unit.global_transform.origin.y
	_unit.global_transform.origin.y = nav_y

	var fake_direction: Variant = _get_fake_direction_due_to_stuck_prevention()
	if fake_direction != null:
		set_velocity(fake_direction * _interim_speed)
		_unit.global_transform.origin.y = real_y
		return
	var next_path_position: Vector3 = get_next_path_position()
	var current_agent_position: Vector3 = _unit.global_transform.origin
	var direction: Vector3 = next_path_position - current_agent_position
	direction.y = 0.0
	var new_velocity: Vector3 = direction.normalized() * _interim_speed
	set_velocity(new_velocity)

	# Restore real height — will be refreshed in _on_velocity_computed
	_unit.global_transform.origin.y = real_y


func _ready() -> void:
	if not _match:
		return
	if _match.navigation == null:
		await _match.ready

	# Air-domain units always get the AIR terrain move type
	if domain == NavigationConstants.Domain.AIR:
		terrain_move_type = NavigationConstants.TerrainMoveType.AIR

	velocity_computed.connect(_on_velocity_computed)
	navigation_finished.connect(_on_navigation_finished)
	set_navigation_map(_match.navigation.get_navigation_map_rid_by_domain(domain))
	_align_unit_position_to_navigation()
	_apply_terrain_height_and_tilt(true)
	move(
		(
			_unit.global_position
			+ (
				Vector3(Match.rng.randf(), 0, Match.rng.randf()).normalized()
				* INITIAL_DISPERSION_FACTOR
			)
		)
	)


func move(movement_target: Vector3) -> void:
	target_position = movement_target


func stop() -> void:
	target_position = Vector3.INF


func _process_water_movement() -> void:
	"""Direct movement for water units — bypasses navmesh path following.
	Water units head straight for their target.  The avoidance system
	(set_velocity → velocity_computed) still prevents unit overlap, and
	_can_enter_position prevents entering non-water cells."""
	var terrain_y: float = _unit.global_transform.origin.y
	_unit.global_transform.origin.y = 0.0

	if target_position == Vector3.INF:
		set_velocity(Vector3.ZERO)
		_unit.global_transform.origin.y = terrain_y
		return

	var diff: Vector3 = target_position - _unit.global_transform.origin
	diff.y = 0.0

	if diff.length() < target_desired_distance:
		set_velocity(Vector3.ZERO)
		_unit.global_transform.origin.y = terrain_y
		target_position = Vector3.INF
		movement_finished.emit()
		return

	var new_velocity: Vector3 = diff.normalized() * _interim_speed
	set_velocity(new_velocity)
	_unit.global_transform.origin.y = terrain_y


func _align_unit_position_to_navigation() -> void:
	await get_tree().process_frame  # wait for navigation to be operational
	_unit.global_transform.origin = (
		NavigationServer3D.map_get_closest_point(
			get_navigation_map(), get_parent().global_transform.origin
		)
		- Vector3(0, path_height_offset, 0)
	)


func _is_moving_actively() -> bool:
	return get_next_path_position() != _unit.global_position


func _get_fake_direction_due_to_stuck_prevention() -> Variant:
	if (
		not STUCK_PREVENTION_ENABLED
		or not _is_moving_actively()
		or _number_of_forced_side_moves_left == 0
	):
		return null
	_number_of_forced_side_moves_left -= 1
	var next_path_position: Vector3 = get_next_path_position()
	var diff: Vector3 = next_path_position - _unit.global_position
	diff.y = 0.0
	var direction_to_target: Vector3 = diff.normalized()
	var current_navigation_path: PackedVector3Array = get_current_navigation_path()
	var current_navigation_path_index: int = get_current_navigation_path_index()
	if current_navigation_path.size() <= 1 or current_navigation_path_index == 0:
		return direction_to_target.rotated(Vector3.UP, PI / 2.0)
	# rotate +90*/-90* and choose the one that goes further from path
	var option_a: Vector3 = direction_to_target.rotated(Vector3.UP, PI / 2.0)
	var option_b: Vector3 = direction_to_target.rotated(Vector3.UP, -PI / 2.0)
	var previous_path_position: Vector3 = current_navigation_path[current_navigation_path_index - 1]
	if (
		(_unit.global_position + option_a).distance_to(previous_path_position)
		> (_unit.global_position + option_b).distance_to(previous_path_position)
	):
		return option_a
	return option_b


func _update_stuck_prevention(safe_velocity: Vector3) -> void:
	if not _is_moving_actively():
		return
	_stuck_prevention_window.append(safe_velocity.length())
	_total_velocity_in_stuck_prevention_window += safe_velocity.length()
	if _stuck_prevention_window.size() > STUCK_PREVENTION_WINDOW_SIZE:
		_total_velocity_in_stuck_prevention_window -= _stuck_prevention_window.pop_front()
	var stuck_prevention_threshold: float = (
		_interim_speed * STUCK_PREVENTION_WINDOW_SIZE * STUCK_PREVENTION_THRESHOLD
	)
	if (
		_stuck_prevention_window.size() == STUCK_PREVENTION_WINDOW_SIZE
		and _total_velocity_in_stuck_prevention_window < stuck_prevention_threshold
	):
		_number_of_forced_side_moves_left = STUCK_PREVENTION_SIDE_MOVES


func _get_filtered_rotation_direction(safe_velocity: Vector3) -> Vector3:
	var direction: Vector3 = safe_velocity.normalized()
	if (
		_previously_set_global_transform_of_unit != null
		and not _previously_set_global_transform_of_unit.is_equal_approx(_unit.global_transform)
	):
		# reset filter if a global_transform of unit was altered from the outside
		_rotation_low_pass_filter_window = []
		_total_direction_in_the_low_pass_filter_window = Vector3.ZERO
	if safe_velocity.length() >= ROTATION_LOW_PASS_FILTER_VELOCITY_THRESHOLD:
		_rotation_low_pass_filter_window.append(direction)
		_total_direction_in_the_low_pass_filter_window += direction
	if _rotation_low_pass_filter_window.size() > ROTATION_LOW_PASS_FILTER_WINDOW_SIZE:
		_total_direction_in_the_low_pass_filter_window -= (
			_rotation_low_pass_filter_window.pop_front()
		)
	if _rotation_low_pass_filter_window.size() == ROTATION_LOW_PASS_FILTER_WINDOW_SIZE:
		return (
			_total_direction_in_the_low_pass_filter_window
			/ float(ROTATION_LOW_PASS_FILTER_WINDOW_SIZE)
		)
	return direction


func _rotate_in_direction(direction: Vector3) -> void:
	if ROTATION_LOW_PASS_FILTER_ENABLED:
		direction = _get_filtered_rotation_direction(direction)
	var rotation_target: Vector3 = _unit.global_transform.origin + direction
	if (
		not is_zero_approx(direction.length())
		and not rotation_target.is_equal_approx(_unit.global_transform.origin)
	):
		_unit.global_transform = _unit.global_transform.looking_at(rotation_target)


func _update_passive_movement_tracking(safe_velocity: Vector3) -> void:
	if not PASSIVE_MOVEMENT_TRACKING_ENABLED:
		return
	if _is_moving_actively() or safe_velocity.is_zero_approx():
		if _passive_movement_detected:
			_passive_movement_detected = false
			passive_movement_finished.emit()
		return
	if not _passive_movement_detected:
		_passive_movement_detected = true
		passive_movement_started.emit()


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_update_stuck_prevention(safe_velocity)

	if not reverse_moving:
		_rotate_in_direction(safe_velocity * Vector3(1, 0, 1))

	var new_pos: Vector3 = _unit.global_transform.origin.move_toward(
		_unit.global_transform.origin + safe_velocity, _interim_speed
	)

	# Terrain passability check — block movement into impassable terrain
	if not _can_enter_position(new_pos):
		# Stop the unit; don't apply movement
		_previously_set_global_transform_of_unit = _unit.global_transform
		_update_passive_movement_tracking(Vector3.ZERO)
		return

	_unit.global_transform.origin = new_pos
	_apply_terrain_height_and_tilt()
	_previously_set_global_transform_of_unit = _unit.global_transform
	_update_passive_movement_tracking(safe_velocity)


func _on_navigation_finished() -> void:
	# Water units handle arrival in _process_water_movement, so ignore
	# the NavigationAgent3D signal which may fire spuriously when the
	# navmesh has no valid path for a water-only unit.
	if terrain_move_type == NavigationConstants.TerrainMoveType.WATER:
		return
	target_position = Vector3.INF
	movement_finished.emit()


func _apply_terrain_height_and_tilt(snap: bool = false) -> void:
	var pos: Vector3 = Vector3.ONE
	var terrain_y: float = 0.0

	# Air units adjust height to stay above terrain
	if terrain_move_type == NavigationConstants.TerrainMoveType.AIR:
		if not _match or not _match.map:
			return
		pos = _unit.global_transform.origin
		terrain_y = _match.map.get_height_at_world(pos)
		var target_y: float = terrain_y + Air.Y
		if snap:
			_unit.global_transform.origin.y = target_y
		else:
			var dt: float = get_physics_process_delta_time()
			_unit.global_transform.origin.y = lerpf(
				_unit.global_transform.origin.y,
				target_y,
				clampf(AIR_HEIGHT_ADJUST_SPEED * dt, 0.0, 1.0)
			)
		return

	if not _match or not _match.map:
		return

	var map: Variant = _match.map
	pos = _unit.global_transform.origin
	terrain_y = map.get_height_at_world(pos)

	# Set Y to terrain height
	_unit.global_transform.origin.y = terrain_y

	# Apply slope tilt
	var surface_normal: Vector3 = map.get_slope_normal_at_world(pos)
	if not surface_normal.is_equal_approx(Vector3.UP):
		# Build a basis that aligns the unit's local UP to the surface normal
		# while preserving the current forward direction as closely as possible.
		var forward: Vector3 = -_unit.global_transform.basis.z
		# Project forward onto the slope plane so the unit doesn't pitch into the ground
		forward = (forward - surface_normal * forward.dot(surface_normal)).normalized()
		if forward.is_zero_approx():
			forward = Vector3.FORWARD
		var right: Vector3 = surface_normal.cross(forward).normalized()
		forward = right.cross(surface_normal).normalized()
		_unit.global_transform.basis = Basis(right, surface_normal, -forward)
	else:
		# Flat ground — remove any residual tilt but keep yaw rotation
		var yaw: float = _unit.global_transform.basis.get_euler().y
		_unit.global_transform.basis = Basis(Vector3.UP, yaw)


func _can_enter_position(world_pos: Vector3) -> bool:
	if terrain_move_type == NavigationConstants.TerrainMoveType.AIR:
		return true
	if not _match or not _match.map:
		return true
	return _match.map.can_unit_traverse(world_pos, terrain_move_type, _unit.global_transform.origin)
