extends Node
## Deterministic tick-based movement with rotation speed.
##
## Fully deterministic: paths are computed via NavigationServer3D.map_get_path()
## inside the tick handler only, so every peer produces identical results.
##
## SC2-style movement: units turn toward their target direction at a
## fixed angular rate and move forward along their facing.  Separation
## between overlapping units is handled centrally by Match after all
## Movement handlers have ticked.
##
## Public API consumed by action scripts:
##   move(pos)            – set navigation target
##   stop()               – cancel movement
##   reverse_moving       – flag for reverse-gear actions
##   movement_finished    – emitted when destination reached
##   passive_movement_*   – emitted when externally pushed/blocked

signal movement_finished
signal passive_movement_started
signal passive_movement_finished

const INITIAL_DISPERSION: float = 0.1
const AIR_HEIGHT_LERP: float = 6.0
const _STUCK_WINDOW: int = 6
const _STUCK_THRESHOLD: float = 0.25
const _STUCK_SIDE_MOVES: int = 15
## How far ahead (in multiples of combined radii) to steer around others.
const _AVOIDANCE_RADIUS_FACTOR: float = 3.5
## Blend weight for avoidance vs. navigation direction.
const _AVOIDANCE_WEIGHT: float = 1.0
## Minimum speed ratio while turning (prevents group stall).
const _MIN_ALIGNMENT_SPEED: float = 0.35
## When within this many radii of the final target for
## _NEAR_TARGET_PATIENCE ticks, accept arrival.  Prevents jitter when a
## rally point (or any destination) is occupied by another unit.
const _ARRIVAL_ACCEPT_FACTOR: float = 3.0
const _NEAR_TARGET_PATIENCE: int = 5

@export var domain: NavigationConstants.Domain = NavigationConstants.Domain.TERRAIN
@export var speed: float = 4.0
## Radians per second the unit can rotate.
@export var turn_speed: float = TAU
@export var terrain_move_type: NavigationConstants.TerrainMoveType = (
	NavigationConstants.TerrainMoveType.LAND
)
## Properties formerly inherited from NavigationAgent3D.
@export var radius: float = 0.25
@export var target_desired_distance: float = 0.5
@export var path_desired_distance: float = 0.5
@export var path_height_offset: float = 0.0

## Stub for debug panel (NavigationAgent3D used to provide this).
var debug_enabled: bool = false

## Set by ReverseMoving action – unit moves backward.
var reverse_moving: bool = false
## Suppresses movement_finished during separation resync.
var _suppress_nav_finished: bool = false

var _initialized: bool = false
var _passive_movement_detected: bool = false

## The current movement target.  Vector3.INF means "no target / stopped".
var target_position: Vector3 = Vector3.INF

# ── deterministic path cache ────────────────────────────────────────
var _nav_map_rid: RID
var _cached_path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0

# ── authoritative yaw (radians, deterministic) ──────────────────────
var _yaw: float = 0.0

# ── interpolation state ─────────────────────────────────────────────
var _prev_transform: Transform3D
var _tick_transform: Transform3D
var _tick_elapsed: float = 0.0

var _stuck_dists: Array[float] = []
var _stuck_total: float = 0.0
var _side_moves_left: int = 0
var _near_target_ticks: int = 0
var _near_target_prev_dist: float = -1.0

@onready var _match: Match = find_parent("Match") as Match
@onready var _unit: Node3D = get_parent() as Node3D


func _ready() -> void:
	if not _match:
		return
	if _match.navigation == null:
		await _match.ready

	if domain == NavigationConstants.Domain.AIR:
		terrain_move_type = NavigationConstants.TerrainMoveType.AIR

	_nav_map_rid = _match.navigation.get_navigation_map_rid_by_domain(domain)
	_align_unit_position_to_navigation()
	_apply_terrain_height_and_tilt(true)

	# Initial dispersion so stacked units spread.
	move(
		(
			_unit.global_position
			+ (Vector3(Match.rng.randf(), 0, Match.rng.randf()).normalized() * INITIAL_DISPERSION)
		)
	)

	# Record initial yaw from whatever direction the unit faces.
	_yaw = _unit.global_transform.basis.get_euler().y

	MatchSignals.tick_advanced.connect(_on_tick_advanced)
	_prev_transform = _unit.global_transform
	_tick_transform = _unit.global_transform
	# Run _process AFTER the tick Timer (priority 0).
	process_priority = 100
	_initialized = true


# ── visual interpolation ────────────────────────────────────────────


func _process(delta: float) -> void:
	if not _initialized:
		return
	_tick_elapsed = minf(_tick_elapsed + delta, MatchConstants.TICK_DELTA)
	_interpolate_visual()


func _interpolate_visual() -> void:
	var alpha: float = clampf(_tick_elapsed / MatchConstants.TICK_DELTA, 0.0, 1.0)
	_unit.global_transform.origin = (_prev_transform.origin.lerp(_tick_transform.origin, alpha))
	var q_prev := _prev_transform.basis.get_rotation_quaternion()
	var q_tick := _tick_transform.basis.get_rotation_quaternion()
	_unit.global_transform.basis = Basis(q_prev.slerp(q_tick, alpha))


# ── public API ──────────────────────────────────────────────────────


func move(movement_target: Vector3) -> void:
	target_position = movement_target
	_cached_path = PackedVector3Array()
	_path_index = 0
	_near_target_ticks = 0
	_near_target_prev_dist = -1.0


func stop() -> void:
	target_position = Vector3.INF
	_cached_path = PackedVector3Array()
	_path_index = 0
	_near_target_ticks = 0
	_near_target_prev_dist = -1.0


func is_moving() -> bool:
	return target_position != Vector3.INF


# ── tick-based movement ─────────────────────────────────────────────


func _on_tick_advanced() -> void:
	if not _initialized:
		return
	# Snap to authoritative state before computing.
	_unit.global_transform = _tick_transform
	var step: float = speed * MatchConstants.TICK_DELTA

	if terrain_move_type == NavigationConstants.TerrainMoveType.WATER:
		_tick_water(step)
		_finish_tick()
		return

	# NavigationAgent queries require navmesh-plane Y.
	var nav_y: float = Air.Y if domain == NavigationConstants.Domain.AIR else 0.0
	var real_y: float = _unit.global_transform.origin.y
	_unit.global_transform.origin.y = nav_y

	# Stuck side-step override.
	var fake: Variant = _get_stuck_direction()
	if fake != null:
		_unit.global_transform.origin.y = real_y
		_step(fake, step)
		_finish_tick()
		return

	# If there is no active target, nothing to do.
	if target_position == Vector3.INF:
		_unit.global_transform.origin.y = real_y
		_near_target_ticks = 0
		_finish_tick()
		return

	# Deterministic arrival check: if the authoritative position
	# is within target_desired_distance, consider the target reached.
	var to_target: Vector3 = target_position - _unit.global_transform.origin
	to_target.y = 0.0
	if to_target.length() <= target_desired_distance:
		_unit.global_transform.origin.y = real_y
		_near_target_ticks = 0
		_near_target_prev_dist = -1.0
		target_position = Vector3.INF
		_finish_tick()
		if not _suppress_nav_finished:
			movement_finished.emit()
		return

	# Accept "close enough" when near the target for several ticks.
	# This catches the case where avoidance keeps steering the unit
	# around a blocker at the destination (e.g. another unit on the
	# rally point) — the unit is still *moving* so stuck detection
	# never fires, but it never arrives either.
	# Only kicks in when progress has stalled (distance not decreasing).
	var to_final: Vector3 = target_position - _unit.global_transform.origin
	to_final.y = 0.0
	var dist_to_final: float = to_final.length()
	var accept_dist: float = _unit.radius * _ARRIVAL_ACCEPT_FACTOR if _unit.radius else 1.5
	if dist_to_final < accept_dist:
		# Only count patience ticks when we're NOT making progress
		# toward the target (i.e. stuck circling/jittering).
		if _near_target_prev_dist >= 0.0 and dist_to_final >= _near_target_prev_dist - 0.01:
			_near_target_ticks += 1
		else:
			_near_target_ticks = 0
		_near_target_prev_dist = dist_to_final
		if _near_target_ticks >= _NEAR_TARGET_PATIENCE:
			_unit.global_transform.origin.y = real_y
			_near_target_ticks = 0
			_near_target_prev_dist = -1.0
			_side_moves_left = 0
			_stuck_dists.clear()
			_stuck_total = 0.0
			target_position = Vector3.INF
			movement_finished.emit()
			_finish_tick()
			return
	else:
		_near_target_ticks = 0
		_near_target_prev_dist = -1.0

	# Compute the deterministic path from current (navmesh-plane) position.
	_recompute_path()

	var next_pos: Vector3 = _get_next_waypoint()
	var cur_pos: Vector3 = _unit.global_transform.origin
	var diff: Vector3 = next_pos - cur_pos
	diff.y = 0.0
	var remaining: float = diff.length()

	# If we're close enough to the waypoint, clamp the step so
	# we don't overshoot and jiggle back and forth.
	var clamped_step: float = minf(step, remaining)

	var desired_dir: Vector3 = diff.normalized()

	_unit.global_transform.origin.y = real_y
	# Steer around nearby units instead of walking through them.
	var steer_dir: Vector3 = _compute_avoidance_dir(desired_dir)
	_step(steer_dir, clamped_step, desired_dir)
	_finish_tick()


func _tick_water(step: float) -> void:
	var terrain_y: float = _unit.global_transform.origin.y
	_unit.global_transform.origin.y = 0.0

	if target_position == Vector3.INF:
		_unit.global_transform.origin.y = terrain_y
		return

	var diff: Vector3 = target_position - _unit.global_transform.origin
	diff.y = 0.0

	if diff.length() < target_desired_distance:
		_unit.global_transform.origin.y = terrain_y
		target_position = Vector3.INF
		movement_finished.emit()
		return

	var desired_dir: Vector3 = diff.normalized()
	_unit.global_transform.origin.y = terrain_y
	_step(desired_dir, step)


## Core per-tick movement step: turn toward steer_dir, then
## advance along the unit's facing direction.
## nav_dir is the original navigation direction (pre-avoidance)
## used for speed alignment so avoidance doesn't cause slowdown.
func _step(steer_dir: Vector3, step: float, nav_dir: Vector3 = Vector3.ZERO) -> void:
	if steer_dir.is_zero_approx():
		_update_passive_movement(Vector3.ZERO)
		return
	if nav_dir.is_zero_approx():
		nav_dir = steer_dir

	# ── rotation ────────────────────────────────────────────────
	# facing = (-sin(yaw), 0, -cos(yaw)), so solve for yaw:
	#   -sin(yaw) = dir.x  →  sin(yaw) = -dir.x
	#   -cos(yaw) = dir.z  →  cos(yaw) = -dir.z
	var target_yaw: float = atan2(-steer_dir.x, -steer_dir.z)
	if reverse_moving:
		target_yaw = target_yaw + PI

	var max_turn: float = turn_speed * MatchConstants.TICK_DELTA
	var diff_yaw: float = _wrap_angle(target_yaw - _yaw)
	_yaw += clampf(diff_yaw, -max_turn, max_turn)
	_yaw = _wrap_angle(_yaw)

	# ── forward vector from facing ──────────────────────────────
	# Godot models face -Z; Basis(UP, yaw) with yaw=0 → -Z forward.
	# sin/cos give +Z at yaw=0, so negate to match the model.
	var facing := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var move_dir: Vector3 = -facing if reverse_moving else facing

	# Blend between desired direction and facing so units start
	# moving toward the target immediately instead of rotating in
	# place first.  Use steer_dir (avoidance-adjusted) for the
	# blend target so we don't walk into walls that avoidance is
	# trying to steer us around.
	var raw_alignment: float = maxf(move_dir.dot(steer_dir), 0.0)
	var blended_dir: Vector3 = (
		(move_dir * raw_alignment + steer_dir * (1.0 - raw_alignment)).normalized()
	)
	if blended_dir.is_zero_approx():
		blended_dir = steer_dir
	# Always move at full step speed.  The rotation system already
	# rate-limits turning; slowing movement on top causes jitter
	# when avoidance continuously shifts the steer direction.
	var move_vel: Vector3 = blended_dir * step

	# ── position update ─────────────────────────────────────────
	var old_pos: Vector3 = _unit.global_transform.origin
	var new_pos: Vector3 = old_pos + move_vel

	# Resolve collisions with other units: if the new position
	# overlaps another unit, slide along the blocker's edge.
	new_pos = _resolve_unit_collisions(new_pos)

	if not _can_enter_position(new_pos):
		_apply_yaw()
		_update_stuck_prevention(Vector3.ZERO)
		_update_passive_movement(Vector3.ZERO)
		return

	# Track actual displacement for stuck detection (after
	# collision resolution has potentially reduced movement).
	var actual_disp := new_pos - old_pos
	actual_disp.y = 0.0
	_update_stuck_prevention(actual_disp)

	_unit.global_transform.origin = new_pos
	_apply_yaw()
	_apply_terrain_height_and_tilt()
	_update_passive_movement(move_vel)


func _apply_yaw() -> void:
	var surface_normal := Vector3.UP
	if _match and _match.map and terrain_move_type != NavigationConstants.TerrainMoveType.AIR:
		surface_normal = _match.map.get_slope_normal_at_world(_unit.global_transform.origin)
	if surface_normal.is_equal_approx(Vector3.UP):
		_unit.global_transform.basis = Basis(Vector3.UP, _yaw)
	else:
		var fwd := Vector3(sin(_yaw), 0.0, cos(_yaw))
		fwd = (fwd - surface_normal * fwd.dot(surface_normal)).normalized()
		if fwd.is_zero_approx():
			fwd = Vector3.FORWARD
		var right := surface_normal.cross(fwd).normalized()
		fwd = right.cross(surface_normal).normalized()
		_unit.global_transform.basis = Basis(right, surface_normal, -fwd)


# ── tick bookkeeping ────────────────────────────────────────────────


func _finish_tick() -> void:
	_prev_transform = _tick_transform
	_tick_transform = _unit.global_transform
	_tick_elapsed = maxf(_tick_elapsed - MatchConstants.TICK_DELTA, 0.0)
	_interpolate_visual()


## Called by Match._apply_unit_separation() after pushing.
func resync_tick_transform() -> void:
	_suppress_nav_finished = true
	_apply_terrain_height_and_tilt()
	_tick_transform = _unit.global_transform
	_interpolate_visual()
	_suppress_nav_finished = false


# ── navigation helpers ──────────────────────────────────────────────


func _align_unit_position_to_navigation() -> void:
	await get_tree().process_frame
	_unit.global_transform.origin = (
		(
			NavigationServer3D
			. map_get_closest_point(
				_nav_map_rid,
				get_parent().global_transform.origin,
			)
		)
		- Vector3(0, path_height_offset, 0)
	)


## Deterministic path query — called once per tick from the tick handler.
func _recompute_path() -> void:
	var nav_y: float = Air.Y if domain == NavigationConstants.Domain.AIR else 0.0
	var from := Vector3(_unit.global_transform.origin.x, nav_y, _unit.global_transform.origin.z)
	var to := Vector3(target_position.x, nav_y, target_position.z)
	_cached_path = NavigationServer3D.map_get_path(_nav_map_rid, from, to, true)
	_path_index = 0
	# Advance past waypoints we've already reached.
	_advance_past_close_waypoints()


## Skip waypoints that are closer than path_desired_distance.
func _advance_past_close_waypoints() -> void:
	while _path_index < _cached_path.size() - 1:
		var wp: Vector3 = _cached_path[_path_index]
		var d := Vector3(
			wp.x - _unit.global_transform.origin.x,
			0.0,
			wp.z - _unit.global_transform.origin.z,
		)
		if d.length() > path_desired_distance:
			break
		_path_index += 1


## Return the next waypoint to steer toward.
func _get_next_waypoint() -> Vector3:
	if _cached_path.is_empty() or _path_index >= _cached_path.size():
		return target_position
	return _cached_path[_path_index]


func _is_moving_actively() -> bool:
	return target_position != Vector3.INF


# ── stuck prevention ────────────────────────────────────────────────


func _get_stuck_direction() -> Variant:
	if not _is_moving_actively() or _side_moves_left == 0:
		return null

	# If we're stuck but already close to the final target, accept
	# arrival instead of jittering with side-steps.  This handles
	# the common case of a rally point blocked by another unit.
	var to_target: Vector3 = target_position - _unit.global_position
	to_target.y = 0.0
	var accept_dist: float = _unit.radius * _ARRIVAL_ACCEPT_FACTOR if _unit.radius else 1.5
	if to_target.length() < accept_dist:
		_side_moves_left = 0
		_stuck_dists.clear()
		_stuck_total = 0.0
		target_position = Vector3.INF
		movement_finished.emit()
		return null

	_side_moves_left -= 1
	var next_p: Vector3 = _get_next_waypoint()
	var d: Vector3 = next_p - _unit.global_position
	d.y = 0.0
	var dir_to := d.normalized()
	if _cached_path.size() <= 1 or _path_index == 0:
		return dir_to.rotated(Vector3.UP, PI / 2.0)
	var opt_a := dir_to.rotated(Vector3.UP, PI / 2.0)
	var opt_b := dir_to.rotated(Vector3.UP, -PI / 2.0)
	var prev_p: Vector3 = _cached_path[_path_index - 1]
	if (
		(_unit.global_position + opt_a).distance_to(prev_p)
		> (_unit.global_position + opt_b).distance_to(prev_p)
	):
		return opt_a
	return opt_b


func _update_stuck_prevention(vel: Vector3) -> void:
	if not _is_moving_actively():
		return
	_stuck_dists.append(vel.length())
	_stuck_total += vel.length()
	if _stuck_dists.size() > _STUCK_WINDOW:
		_stuck_total -= _stuck_dists.pop_front()
	var threshold: float = (
		speed * MatchConstants.TICK_DELTA * float(_STUCK_WINDOW) * _STUCK_THRESHOLD
	)
	if _stuck_dists.size() == _STUCK_WINDOW and _stuck_total < threshold:
		_side_moves_left = _STUCK_SIDE_MOVES


# ── passive movement tracking ──────────────────────────────────────


func _update_passive_movement(vel: Vector3) -> void:
	if _is_moving_actively() or vel.is_zero_approx():
		if _passive_movement_detected:
			_passive_movement_detected = false
			passive_movement_finished.emit()
		return
	if not _passive_movement_detected:
		_passive_movement_detected = true
		passive_movement_started.emit()


# ── terrain ─────────────────────────────────────────────────────────


func _apply_terrain_height_and_tilt(snap: bool = false) -> void:
	if terrain_move_type == NavigationConstants.TerrainMoveType.AIR:
		if not _match or not _match.map:
			return
		var pos := _unit.global_transform.origin
		var ty: float = _match.map.get_height_at_world(pos)
		var target_y: float = ty + Air.Y
		if snap:
			_unit.global_transform.origin.y = target_y
		else:
			_unit.global_transform.origin.y = lerpf(
				_unit.global_transform.origin.y,
				target_y,
				clampf(
					AIR_HEIGHT_LERP * MatchConstants.TICK_DELTA,
					0.0,
					1.0,
				),
			)
		return

	if not _match or not _match.map:
		return
	var land_pos := _unit.global_transform.origin
	_unit.global_transform.origin.y = (_match.map.get_height_at_world(land_pos))
	_apply_yaw()


func _can_enter_position(world_pos: Vector3) -> bool:
	if terrain_move_type == NavigationConstants.TerrainMoveType.AIR:
		return true
	if not _match or not _match.map:
		return true
	return (
		_match
		. map
		. can_unit_traverse(
			world_pos,
			terrain_move_type,
			_unit.global_transform.origin,
		)
	)


static func _wrap_angle(a: float) -> float:
	return fmod(a + 3.0 * PI, TAU) - PI


# ── unit collision resolution ───────────────────────────────────────


## Check new_pos against all other units. If it overlaps any unit,
## push it out to the edge of that unit's collision circle.
## Runs up to 3 iterations to resolve chain collisions.
func _resolve_unit_collisions(new_pos: Vector3) -> Vector3:
	var my_r: float = _unit.radius if _unit.radius != null else 0.25
	var pos_2d := Vector3(new_pos.x, 0.0, new_pos.z)

	for _iter in range(3):
		var resolved: bool = true
		for unit_id: int in EntityRegistry.entities:
			var other: Node3D = EntityRegistry.entities[unit_id]
			if other == null or other == _unit:
				continue
			if not is_instance_valid(other):
				continue
			if other.find_child("Movement") == null:
				continue
			if other.get_nav_domain() != _unit.get_nav_domain():
				continue

			var other_r: float = other.radius if other.radius != null else 0.25
			var other_2d := Vector3(
				other.global_transform.origin.x,
				0.0,
				other.global_transform.origin.z,
			)
			var diff := pos_2d - other_2d
			var dist := diff.length()
			var min_dist := my_r + other_r

			if dist >= min_dist or dist < 0.001:
				continue

			# Push out to edge of combined radii.
			var push_dir := diff / dist
			pos_2d = other_2d + push_dir * min_dist
			resolved = false

		if resolved:
			break

	new_pos.x = pos_2d.x
	new_pos.z = pos_2d.z
	return new_pos


# ── local avoidance ─────────────────────────────────────────────────


## Blend the navigation desired_dir with avoidance vectors from nearby
## units so this unit steers around them instead of walking into them.
## When multiple units block the path (a "wall"), picks the side with
## the least resistance by steering away from the weighted center of
## all blockers.  Also checks whether the gap between adjacent wall
## units is too narrow for this unit to fit through.
func _compute_avoidance_dir(desired_dir: Vector3) -> Vector3:
	if desired_dir.is_zero_approx():
		return desired_dir

	var my_pos := Vector3(
		_unit.global_transform.origin.x,
		0.0,
		_unit.global_transform.origin.z,
	)
	var my_r: float = _unit.radius if _unit.radius != null else 0.25

	# Collect all blockers ahead of us with their positions/radii.
	var blockers: Array[Dictionary] = []

	for unit_id: int in EntityRegistry.entities:
		var other: Node3D = EntityRegistry.entities[unit_id]
		if other == null or other == _unit:
			continue
		if not is_instance_valid(other):
			continue
		if other.find_child("Movement") == null:
			continue
		if other.get_nav_domain() != _unit.get_nav_domain():
			continue

		var other_pos := Vector3(
			other.global_transform.origin.x,
			0.0,
			other.global_transform.origin.z,
		)
		var other_r: float = other.radius if other.radius != null else 0.25
		var to_other := other_pos - my_pos
		var dist := to_other.length()
		var avoid_dist := (my_r + other_r) * _AVOIDANCE_RADIUS_FACTOR

		if dist >= avoid_dist or dist < 0.001:
			continue

		# Only consider units ahead of our movement direction.
		var to_other_n := to_other / dist
		var forward_dot := desired_dir.dot(to_other_n)
		if forward_dot < 0.1:
			continue

		(
			blockers
			. append(
				{
					"pos": other_pos,
					"r": other_r,
					"to": to_other,
					"dist": dist,
					"avoid_dist": avoid_dist,
					"fwd_dot": forward_dot,
				}
			)
		)

	if blockers.is_empty():
		return desired_dir

	# Check if any pair of blockers forms an impassable gap.
	# If so, merge them into a single virtual wall blocker.
	var merged_blockers: Array[Dictionary] = []
	var merged_flags: Array[bool] = []
	merged_flags.resize(blockers.size())
	merged_flags.fill(false)

	for i in range(blockers.size()):
		for j in range(i + 1, blockers.size()):
			var bi: Dictionary = blockers[i]
			var bj: Dictionary = blockers[j]
			var pair_dist: float = (bi["pos"] as Vector3).distance_to(bj["pos"] as Vector3)
			var gap: float = pair_dist - (bi["r"] as float) - (bj["r"] as float)
			# Gap too narrow for this unit to fit through?
			if gap < my_r * 2.0:
				merged_flags[i] = true
				merged_flags[j] = true
				# Virtual wall at midpoint with radius covering
				# both blockers.
				var mid: Vector3 = ((bi["pos"] as Vector3) + (bj["pos"] as Vector3)) * 0.5
				var cover_r: float = pair_dist * 0.5 + maxf(bi["r"] as float, bj["r"] as float)
				var to_mid := mid - my_pos
				var mid_dist := to_mid.length()
				var mid_avoid := (my_r + cover_r) * _AVOIDANCE_RADIUS_FACTOR
				if mid_dist < mid_avoid and mid_dist > 0.001:
					var mid_fwd := desired_dir.dot(to_mid / mid_dist)
					if mid_fwd > 0.1:
						(
							merged_blockers
							. append(
								{
									"to": to_mid,
									"dist": mid_dist,
									"avoid_dist": mid_avoid,
									"fwd_dot": mid_fwd,
								}
							)
						)

	# Build weighted blocker center from unmerged + merged.
	var blocker_center := Vector3.ZERO
	var total_weight: float = 0.0

	for i in range(blockers.size()):
		if merged_flags[i]:
			continue
		var b: Dictionary = blockers[i]
		var w: float = (
			(1.0 - (b["dist"] as float) / (b["avoid_dist"] as float)) * (b["fwd_dot"] as float)
		)
		blocker_center += (b["to"] as Vector3) * w
		total_weight += w

	for b in merged_blockers:
		var w: float = (
			(1.0 - (b["dist"] as float) / (b["avoid_dist"] as float)) * (b["fwd_dot"] as float)
		)
		# Merged walls get extra weight: they block harder.
		blocker_center += (b["to"] as Vector3) * w * 2.0
		total_weight += w * 2.0

	if total_weight < 0.001:
		return desired_dir

	blocker_center /= total_weight

	# Steer perpendicular to desired_dir, away from the blocker
	# center. This consistently picks the clearer side.
	var side := desired_dir.cross(Vector3.UP).normalized()
	if side.is_zero_approx():
		side = Vector3(1.0, 0.0, 0.0)
	# Pick the side AWAY from the blocker center.
	if side.dot(blocker_center) > 0.0:
		side = -side

	# When close to the blocker center, steer harder (up to fully
	# perpendicular). This lets units actually navigate around
	# walls instead of just nudging sideways.
	var center_dist: float = blocker_center.length()
	var closeness: float = clampf(
		1.0 - center_dist / (my_r * _AVOIDANCE_RADIUS_FACTOR * 2.0),
		0.0,
		1.0,
	)
	# blend: 0..1 from weight, closeness amplifies to steer harder
	var blend: float = minf(total_weight, 1.0)
	var steer_strength: float = _AVOIDANCE_WEIGHT * blend * (1.0 + closeness * 2.0)
	return (desired_dir + side * steer_strength).normalized()
