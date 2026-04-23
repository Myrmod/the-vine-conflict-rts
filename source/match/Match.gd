class_name Match

extends Node3D

# ──────────────────────────────────────────────────────────────────────
# Match: The SINGLE POINT OF AUTHORITY for all game state changes.
#
# ARCHITECTURE:
#   CommandBus holds all queued commands (from human, AI, and replay).
#   Match._execute_command() is the ONLY place that mutates game state.
#   No controller, UI, or AI may modify units/resources directly.
#
# DETERMINISM:
#   - Tick-based: a Timer fires TICK_RATE times/sec, advancing tick counter
#   - Each tick: all commands for that tick are fetched and executed in order
#   - RNG is a match-local RandomNumberGenerator seeded via Match.rng.seed
#   - All gameplay random calls go through Match.rng / MatchUtils.rng_shuffle()
#   - Replay = same seed + same commands in same tick order → identical game
#
# COMMAND FLOW:
#   Human/AI → CommandBus.push_command({tick, type, player_id, data}) → queued by tick
#   _on_tick() → CommandBus.get_commands_for_tick(tick)   → _execute_command()
#
# See Enums.CommandType for the full list of command types.
# See CommandBus.gd for validation and queuing.
# ──────────────────────────────────────────────────────────────────────

const Structure = preload("res://source/match/units/Structure.gd")
const _SEPARATION_STRENGTH := 0.4

@export var settings: Resource = null

var map:
	set = _set_map,
	get = _get_map
var visible_player = null:
	set = _set_visible_player
var visible_players = null:
	set = _ignore,
	get = _get_visible_players

var is_replay_mode = false

## Original path used to load the map (e.g. "res://maps/test.tres" for
## MapResource maps or a .tscn path for built-in maps).  Stored so the
## ReplayRecorder can save the correct path instead of the base template.
var map_source_path: String = ""

## When set, the match will restore state from this save instead of spawning
## fresh units. Set by Loading.gd when loading a save file or reconnecting.
var save_resource = null

@onready var navigation = $Navigation
@onready var fog_of_war = $FogOfWar
@onready var hud: CanvasLayer = $HUD
@onready var global_build_grid = $GlobalBuildGrid

@onready var _camera = $IsometricCamera3D
@onready var _players = $Players
@onready var _terrain = $Terrain

# Tick counter — drives deterministic command execution. Static so producers can read it.
static var tick := 0

# Match-local RNG. ALL gameplay randomness MUST go through this — never use global
# randi()/randf()/shuffle(). Seeded via Match.rng.seed by Loading.gd (or test harness)
# before the match enters the tree. Replays reproduce identically because the same seed
# produces the same sequence. Static so controllers and utils can access it directly.
static var rng := RandomNumberGenerator.new()

# The player controlled by THIS peer. In single-player this is the Human player.
# In multiplayer each peer gets a different _local_player based on their peer ID.
var _local_player: Player = null
var _match_ended: bool = false


func _enter_tree():
	assert(settings != null, "match cannot start without settings, see examples in tests/manual/")
	assert(map != null, "match cannot start without map, see examples in tests/manual/")


func _ready():
	if is_replay_mode:
		ReplayRecorder.start_replay()

	MatchSignals.setup_and_spawn_unit.connect(_setup_and_spawn_unit)
	_setup_subsystems_dependent_on_map()
	_setup_players()

	# Determine which player this peer controls — must be set before _setup_player_units()
	# so _setup_unit_groups() knows which units are "controlled" vs "adversary".
	var local_idx: int = _get_local_player_index()
	var all_players: Array = get_tree().get_nodes_in_group("players")
	_local_player = all_players[local_idx]

	if save_resource != null:
		_restore_from_save(save_resource)
	else:
		_setup_player_units()
		_spread_initial_creep()
	visible_player = _local_player
	_move_camera_to_initial_position()

	# Reset tick counter for this match (save restores it in _restore_from_save)
	if save_resource == null:
		tick = 0

	# Start the deterministic tick timer (10 ticks/sec = 100ms per tick)
	var timer := Timer.new()
	timer.wait_time = 1.0 / MatchConstants.TICK_RATE
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)

	# In multiplayer, catch up immediately when a stalled tick becomes ready
	# instead of waiting for the next timer fire.
	if NetworkCommandSync.is_active:
		NetworkCommandSync.tick_unblocked.connect(_on_tick_unblocked)
		_register_peer_uuids()
		NetworkCommandSync.player_reconnected_in_match.connect(_on_player_reconnected)
		NetworkCommandSync.reconnect_timer_expired.connect(_on_reconnect_timer_expired)
		NetworkCommandSync.server_disconnected.connect(_on_host_disconnected)
		# If this is a reconnect (loading from save), tell the host we're ready
		if save_resource != null:
			NetworkCommandSync.send_reconnect_ready()

	if settings.visibility == settings.Visibility.FULL:
		fog_of_war.reveal()
	MatchSignals.match_started.emit()
	MatchSignals.match_finished_with_victory.connect(_on_match_ended)
	MatchSignals.match_finished_with_defeat.connect(_on_match_ended)

	hud.set_replay_mode(is_replay_mode)
	wire_hud()

	if !is_replay_mode:
		ReplayRecorder.start_recording(self)


# ──────────────────────────────────────────────────────────────────────
# COMMAND INFRASTRUCTURE
# ──────────────────────────────────────────────────────────────────────


# Parse a target entry from command data into a normalised dictionary.
# Target entries use the deterministic schema: { "unit": int, "pos": Vector3?, "rot": Vector3? }
# No object references — only IDs and positions. This is what makes replay serialisation work.
func _parse_target_entry(entry: Variant, command_name: String) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		push_error(
			"%s command: target entry must be Dictionary, got %s" % [command_name, typeof(entry)]
		)
		return {}
	var unit_id = entry.get("unit", null)
	if unit_id == null:
		push_error("%s command: target entry missing 'unit' id (%s)" % [command_name, str(entry)])
		return {}
	return {
		"unit_id": unit_id,
		"pos": entry.get("pos", null),
		"rot": entry.get("rot", null),
	}


# Resolve an entity ID to a valid, living unit. Returns null on failure.
# Uses push_warning (not push_error) because commands may legitimately reference
# units that died between the tick the command was queued and the tick it executes.
func _resolve_unit(entity_id: int, context: String):
	var unit = EntityRegistry.get_unit(entity_id)
	if unit == null or not is_instance_valid(unit):
		push_warning("%s: entity_id %s is null or invalid" % [context, entity_id])
		return null
	if unit.is_queued_for_deletion():
		push_warning("%s: entity_id %s is queued for deletion" % [context, entity_id])
		return null
	return unit


# Resolve an entity ID specifically to a player. Returns null on failure.
func _resolve_player(player_id: int, context: String):
	for p in get_tree().get_nodes_in_group("players"):
		if p.id == player_id:
			if not is_instance_valid(p) or p.is_queued_for_deletion():
				push_warning("%s: player_id %s is invalid" % [context, player_id])
				return null
			return p
	push_warning("%s: player_id %s not found" % [context, player_id])
	return null


# Verify that a unit belongs to the commanding player. Returns true if valid.
func _verify_unit_ownership(unit, player_id: int, context: String) -> bool:
	if not "player" in unit or unit.player == null:
		push_warning(
			(
				"%s: entity %s has no player (is %s)"
				% [context, unit.id, unit.get_script().resource_path.get_file()]
			)
		)
		return false
	if unit.player.id != player_id:
		push_warning(
			(
				"%s: unit %s belongs to player %s, not commanding player %s"
				% [context, unit.id, unit.player.id, player_id]
			)
		)
		return false
	return true


# ──────────────────────────────────────────────────────────────────────
# TICK LOOP
# ──────────────────────────────────────────────────────────────────────

# Called by the Timer at TICK_RATE Hz. Advances the deterministic tick counter
# and executes all commands queued for this tick. This is the heartbeat of the
# game simulation — identical ticks + identical commands = identical game state.
var _tick_stalled: bool = false


func _on_tick():
	# MULTIPLAYER: wait until all peers have submitted commands for the next tick.
	if NetworkCommandSync.is_active:
		# Send our "tick ready" signal so other peers know we have no more
		# commands for this upcoming tick.
		NetworkCommandSync.send_tick_ready(tick + 1)
		if not NetworkCommandSync.is_tick_ready(tick + 1):
			_tick_stalled = true
			return  # stall — not all peers have sent their commands yet
		NetworkCommandSync.cleanup_tick(tick)

	_advance_tick()


func _on_tick_unblocked():
	if not _tick_stalled:
		return
	_tick_stalled = false
	if NetworkCommandSync.is_tick_ready(tick + 1):
		NetworkCommandSync.cleanup_tick(tick)
		_advance_tick()


func _advance_tick():
	tick += 1
	_process_commands_for_tick()
	# Notify AI controllers and other tick-driven systems.
	# This fires AFTER commands are executed, so listeners see up-to-date game state.
	MatchSignals.tick_advanced.emit()
	# Deterministic unit separation — runs AFTER all Movement handlers have
	# updated positions, so every unit's tick transform is final before we
	# resolve overlaps.  Processes units in sorted-ID order for determinism.
	_apply_unit_separation()
	# MULTIPLAYER: periodically exchange state checksums for desync detection.
	NetworkCommandSync.maybe_check_state(tick)


# ──────────────────────────────────────────────────────────────────────
# DETERMINISTIC UNIT SEPARATION
# ──────────────────────────────────────────────────────────────────────


func _apply_unit_separation() -> void:
	# Collect mobile units together with their Movement node.
	var mobile_units: Array = []
	var movements: Dictionary = {}  # unit.id → Movement
	for unit_id in EntityRegistry.entities:
		var unit = EntityRegistry.entities[unit_id]
		if unit == null or not is_instance_valid(unit):
			continue
		var mov = unit.find_child("Movement")
		if mov == null:
			continue
		mobile_units.append(unit)
		movements[unit.id] = mov

	if mobile_units.size() < 2:
		return

	mobile_units.sort_custom(func(a, b): return a.id < b.id)

	# Build per-unit push accumulators so each pair contributes
	# independently (order-independent within a single pass).
	var pushes := {}  # unit.id → Vector3
	for u in mobile_units:
		pushes[u.id] = Vector3.ZERO

	for i in range(mobile_units.size()):
		var unit_a: Node3D = mobile_units[i]
		var r_a: float = unit_a.radius if unit_a.radius != null else 0.25
		# Use authoritative tick position, NOT interpolated global_transform.
		var tick_a: Transform3D = movements[unit_a.id]._tick_transform
		var pos_a := Vector3(tick_a.origin.x, 0.0, tick_a.origin.z)

		for j in range(i + 1, mobile_units.size()):
			var unit_b: Node3D = mobile_units[j]
			var r_b: float = unit_b.radius if unit_b.radius != null else 0.25

			if unit_a.get_nav_domain() != unit_b.get_nav_domain():
				continue

			var tick_b: Transform3D = movements[unit_b.id]._tick_transform
			var pos_b := Vector3(tick_b.origin.x, 0.0, tick_b.origin.z)

			var diff := pos_a - pos_b
			var dist := diff.length()
			var min_dist := r_a + r_b

			if dist >= min_dist:
				continue

			var push_dir: Vector3
			if dist < 0.001:
				push_dir = Vector3(1, 0, 0)
			else:
				push_dir = diff / dist

			# When both units are actively moving, bias separation
			# perpendicular to push_dir so they slide past each other.
			var mov_a = movements[unit_a.id]
			var mov_b = movements[unit_b.id]
			var a_moving: bool = mov_a.is_moving()
			var b_moving: bool = mov_b.is_moving()
			if a_moving and b_moving:
				var perp := push_dir.cross(Vector3.UP).normalized()
				if not perp.is_zero_approx():
					push_dir = (push_dir + perp * 0.5).normalized()

			var overlap := min_dist - dist
			var half_push := push_dir * overlap * _SEPARATION_STRENGTH * 0.5
			pushes[unit_a.id] += half_push
			pushes[unit_b.id] -= half_push

	# Apply accumulated pushes to the authoritative tick transform.
	for unit in mobile_units:
		var push: Vector3 = pushes[unit.id]
		if push.is_zero_approx():
			continue
		# Cap the push so it never exceeds one tick of movement.
		var mov = movements[unit.id]
		var max_push: float = mov.speed * MatchConstants.TICK_DELTA
		if push.length() > max_push:
			push = push.normalized() * max_push
		mov._tick_transform.origin.x += push.x
		mov._tick_transform.origin.z += push.z
		mov.resync_tick_transform()


# Fetch and execute every command for the current tick.
# CommandBus decides the source: live queue during gameplay, replay data during playback.
func _process_commands_for_tick():
	var commands_for_tick = CommandBus.get_commands_for_tick(tick)
	if commands_for_tick.is_empty():
		return
	# Sort commands by player_id to guarantee identical execution order on all
	# peers regardless of RPC arrival order.
	commands_for_tick.sort_custom(func(a, b): return a.player_id < b.player_id)
	for cmd in commands_for_tick:
		_execute_command(cmd)


# ──────────────────────────────────────────────────────────────────────
# COMMAND EXECUTION — THE SINGLE POINT OF AUTHORITY
# ──────────────────────────────────────────────────────────────────────
#
# ALL game state mutations happen here. No other code may:
#   - Set unit.action directly
#   - Call production_queue.produce() / cancel() / cancel_all()
#   - Call MatchSignals.setup_and_spawn_unit.emit()
#   - Call player.subtract_resources() / add_resources()
#   - Call structure.cancel_construction()
#   - Set rally_point.target_unit or rally_point.global_position
#
# If it changes game state, it MUST be a command type handled here.
# ──────────────────────────────────────────────────────────────────────


func _execute_command(cmd: Dictionary):
	match cmd.type:
		# ── MOVEMENT ──────────────────────────────────────────────────
		Enums.CommandType.MOVE:
			for entry in cmd.data.targets:
				var parsed = _parse_target_entry(entry, "MOVE")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "MOVE")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "MOVE"):
					continue
				if parsed["pos"] == null:
					push_error("MOVE command: target entry missing 'pos' (%s)" % str(entry))
					continue
				unit._stopped = false
				if cmd.data.get("queued", false) and unit.action != null:
					unit._enqueue_command(cmd.type, {"pos": parsed["pos"]})
				else:
					unit.action = Actions.Moving.new(parsed["pos"])

		Enums.CommandType.MOVING_TO_UNIT:
			var target_unit = _resolve_unit(cmd.data.target_unit, "MOVING_TO_UNIT.target")
			if target_unit == null:
				return
			for entry in cmd.data.targets:
				var parsed = _parse_target_entry(entry, "MOVING_TO_UNIT")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "MOVING_TO_UNIT")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "MOVING_TO_UNIT"):
					continue
				unit.action = Actions.MovingToUnit.new(target_unit)

		Enums.CommandType.FOLLOWING:
			var target_unit = _resolve_unit(cmd.data.target_unit, "FOLLOWING.target")
			if target_unit == null:
				return
			for entry in cmd.data.targets:
				var parsed = _parse_target_entry(entry, "FOLLOWING")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "FOLLOWING")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "FOLLOWING"):
					continue
				unit.action = Actions.Following.new(target_unit)

		# ── ECONOMY ───────────────────────────────────────────────────
		Enums.CommandType.COLLECTING_RESOURCES_SEQUENTIALLY:
			var target_unit = _resolve_unit(cmd.data.target_unit, "COLLECTING.target")
			if target_unit == null:
				return
			for entry in cmd.data.targets:
				var parsed = _parse_target_entry(entry, "COLLECTING")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "COLLECTING")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "COLLECTING"):
					continue
				unit.action = Actions.CollectingResourcesSequentially.new(target_unit)

		# ── COMBAT ────────────────────────────────────────────────────
		Enums.CommandType.AUTO_ATTACKING:
			var target_unit = _resolve_unit(cmd.data.target_unit, "AUTO_ATTACKING.target")
			if target_unit == null:
				return
			var force: bool = cmd.data.get("force", false)
			for entry in cmd.data.targets:
				var parsed = _parse_target_entry(entry, "AUTO_ATTACKING")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "AUTO_ATTACKING")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "AUTO_ATTACKING"):
					continue
				if not force and not Actions.AutoAttacking.is_applicable(unit, target_unit):
					push_warning(
						(
							"AUTO_ATTACKING: unit %s cannot attack target %s (no attack_range or wrong domain)"
							% [parsed["unit_id"], cmd.data.target_unit]
						)
					)
					continue
				elif force and (unit.attack_range == null or unit.attack_range <= 0):
					continue
				unit.action = Actions.AutoAttacking.new(target_unit)

		# ── CONSTRUCTION ──────────────────────────────────────────────
		Enums.CommandType.CONSTRUCTING:
			var structure = _resolve_unit(cmd.data.structure, "CONSTRUCTING.structure")
			if structure == null:
				return
			if not structure is Structure:
				push_error("CONSTRUCTING: entity_id %s is not a Structure" % cmd.data.structure)
				return
			if not _verify_unit_ownership(structure, cmd.player_id, "CONSTRUCTING.structure"):
				return
			for entry in cmd.data.selected_constructors:
				var parsed = _parse_target_entry(entry, "CONSTRUCTING")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "CONSTRUCTING.constructor")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "CONSTRUCTING.constructor"):
					continue
				if not Actions.Constructing.is_applicable(unit, structure):
					push_error(
						(
							"CONSTRUCTING: entity_id %s cannot construct structure %s"
							% [parsed["unit_id"], cmd.data.structure]
						)
					)
					continue
				unit.action = Actions.Constructing.new(structure)

		# ── STRUCTURE PLACEMENT ───────────────────────────────────────
		# Places a new structure on the map. Cost handling depends on the
		# structure_production_type of the producing structure:
		#   TRICKLE:       no upfront cost — structure deducts resources over build_time
		#   DONT_TRICKLE:  full cost deducted here before spawning
		#   OFF_FIELD:     cost already paid during queue construction; quick 0.5 s build
		Enums.CommandType.STRUCTURE_PLACED:
			var player = _resolve_player(cmd.player_id, "STRUCTURE_PLACED")
			if player == null:
				return
			var structure_scene_id: int = cmd.data.structure_prototype
			if _is_duplicate_structure_placement(player, structure_scene_id, cmd.data.transform):
				push_warning(
					(
						"STRUCTURE_PLACED: ignored duplicate placement for scene id %s at %s"
						% [structure_scene_id, str(cmd.data.transform.origin)]
					)
				)
				return
			var structure_scene_path: String = UnitConstants.get_scene_path(structure_scene_id)
			if structure_scene_path == "":
				push_error("STRUCTURE_PLACED: unknown scene id %s" % structure_scene_id)
				return
			var structure_prototype: PackedScene = load(structure_scene_path) as PackedScene
			if structure_prototype == null:
				push_error("STRUCTURE_PLACED: cannot load %s" % structure_scene_path)
				return
			var self_constructing: bool = cmd.data.get("self_constructing", false)
			var off_field_deploy: bool = cmd.data.get("off_field_deploy", false)
			var is_trickle: bool = cmd.data.get("trickle", false)
			var preview_structure: Node = structure_prototype.instantiate()
			var requires_seedling_to_start: bool = (
				preview_structure.get("requires_seedling_to_start") == true
			)
			preview_structure.queue_free()
			var seedling_constructor: Unit = null
			if requires_seedling_to_start:
				seedling_constructor = _find_available_radix_seedling(
					player,
					cmd.data.transform.origin,
				)
				if seedling_constructor == null:
					push_warning(
						(
							"STRUCTURE_PLACED: player %s has no available Seedling for %s"
							% [player.id, structure_scene_path]
						)
					)
					return
				self_constructing = false
			var construction_cost: Variant = (
				UnitConstants.get_default_properties(structure_scene_id).get("costs", null)
			)
			if off_field_deploy:
				# Cost already handled during queue production. Deploy with quick build.
				var producer_id: int = cmd.data.get("producer_id", -1)
				if producer_id >= 0:
					var producer: Unit = _resolve_unit(producer_id, "STRUCTURE_PLACED")
					if producer != null and producer.has_node("ProductionQueue"):
						producer.production_queue.deploy_completed(structure_scene_id)
				var unit: Node = structure_prototype.instantiate()
				MatchSignals.setup_and_spawn_unit.emit(unit, cmd.data.transform, player, true)
				if unit is Structure:
					unit._self_construction_speed = 2.0  # 0.5 s build
				if seedling_constructor != null:
					seedling_constructor.action = Actions.Constructing.new(unit)
			elif is_trickle:
				# ON_FIELD + TRICKLE: no upfront cost — structure trickles during construction
				var unit: Node = structure_prototype.instantiate()
				if unit is Structure and construction_cost != null:
					unit._trickle_cost = construction_cost.duplicate()
				MatchSignals.setup_and_spawn_unit.emit(
					unit, cmd.data.transform, player, self_constructing
				)
				if requires_seedling_to_start and unit is Structure:
					unit.mark_as_under_construction(false)
					# Add to producer's queue for HUD tracking
					var producer_id: int = cmd.data.get("producer_id", -1)
					if producer_id >= 0:
						var producer: Unit = _resolve_unit(
							producer_id, "STRUCTURE_PLACED/seedling-queue"
						)
						if producer != null and producer.has_node("ProductionQueue"):
							_add_seedling_structure_to_queue(producer, unit, structure_scene_id)
				if seedling_constructor != null:
					seedling_constructor.action = Actions.Constructing.new(unit)
			else:
				# DONT_TRICKLE: deduct full cost upfront (also used by AI)
				if construction_cost != null:
					if not player.has_resources(construction_cost):
						push_warning(
							(
								"STRUCTURE_PLACED: player %s cannot afford %s"
								% [player.id, structure_scene_path]
							)
						)
						return
					player.subtract_resources(construction_cost)
				var unit: Node = structure_prototype.instantiate()
				(
					MatchSignals
					. setup_and_spawn_unit
					. emit(
						unit,
						cmd.data.transform,
						player,
						self_constructing,
					)
				)
				if requires_seedling_to_start and unit is Structure:
					unit.mark_as_under_construction(false)
					# Add to producer's queue for HUD tracking
					var producer_id: int = cmd.data.get("producer_id", -1)
					if producer_id >= 0:
						var producer: Unit = _resolve_unit(
							producer_id, "STRUCTURE_PLACED/seedling-queue"
						)
						if producer != null and producer.has_node("ProductionQueue"):
							_add_seedling_structure_to_queue(producer, unit, structure_scene_id)
				if seedling_constructor != null:
					seedling_constructor.action = Actions.Constructing.new(unit)

		# ── PRODUCTION ────────────────────────────────────────────────
		# Queues a unit for production. Resources are checked and deducted by the
		# ProductionQueue.produce() call (which is the execution point, not the producer).
		Enums.CommandType.ENTITY_IS_QUEUED:
			var structure = _resolve_unit(cmd.data.entity_id, "ENTITY_IS_QUEUED")
			if structure == null:
				return
			if not _verify_unit_ownership(structure, cmd.player_id, "ENTITY_IS_QUEUED"):
				return
			if structure is Structure and structure.is_disabled:
				return
			var unit_scene_id: int = cmd.data.unit_type
			var unit_scene_path: String = UnitConstants.get_scene_path(unit_scene_id)
			if unit_scene_path == "":
				push_error("ENTITY_IS_QUEUED: unknown scene id %s" % unit_scene_id)
				return
			var unit_prototype = load(unit_scene_path)
			if unit_prototype == null:
				push_error("ENTITY_IS_QUEUED: cannot load %s" % unit_scene_path)
				return
			if structure.has_node("ProductionQueue"):
				structure.production_queue.produce(
					unit_prototype, cmd.data.get("ignore_limit", false)
				)

		Enums.CommandType.ENTITY_PRODUCTION_CANCELED:
			var structure = _resolve_unit(cmd.data.entity_id, "ENTITY_PRODUCTION_CANCELED")
			if structure == null:
				return
			if not _verify_unit_ownership(structure, cmd.player_id, "ENTITY_PRODUCTION_CANCELED"):
				return
			var canceled_scene_id: int = cmd.data.unit_type
			var canceled_scene_path: String = UnitConstants.get_scene_path(canceled_scene_id)
			var unit_prototype = load(canceled_scene_path)
			if unit_prototype == null or not structure.has_node("ProductionQueue"):
				return
			for element in structure.production_queue.get_elements():
				if element.unit_prototype.resource_path == canceled_scene_path:
					structure.production_queue.cancel(element)
					break

		Enums.CommandType.ENTITY_PRODUCTION_PAUSED:
			var structure = _resolve_unit(cmd.data.entity_id, "ENTITY_PRODUCTION_PAUSED")
			if structure == null:
				return
			if not _verify_unit_ownership(structure, cmd.player_id, "ENTITY_PRODUCTION_PAUSED"):
				return
			if structure.has_node("ProductionQueue"):
				structure.production_queue.toggle_pause(cmd.data.unit_type)

		Enums.CommandType.PRODUCTION_CANCEL_ALL:
			var structure = _resolve_unit(cmd.data.entity_id, "PRODUCTION_CANCEL_ALL")
			if structure == null:
				return
			if not _verify_unit_ownership(structure, cmd.player_id, "PRODUCTION_CANCEL_ALL"):
				return
			if structure.has_node("ProductionQueue"):
				structure.production_queue.cancel_all()

		# ── ACTION MANAGEMENT ─────────────────────────────────────────
		Enums.CommandType.ACTION_CANCEL:
			for entry in cmd.data.targets:
				var parsed = _parse_target_entry(entry, "ACTION_CANCEL")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "ACTION_CANCEL")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "ACTION_CANCEL"):
					continue
				unit.action = null

		Enums.CommandType.CANCEL_CONSTRUCTION:
			var structure = _resolve_unit(cmd.data.entity_id, "CANCEL_CONSTRUCTION")
			if structure == null:
				return
			if not _verify_unit_ownership(structure, cmd.player_id, "CANCEL_CONSTRUCTION"):
				return
			if not structure is Structure:
				push_error(
					"CANCEL_CONSTRUCTION: entity_id %s is not a Structure" % cmd.data.entity_id
				)
				return
			if not structure.is_under_construction():
				push_error(
					"CANCEL_CONSTRUCTION: entity_id %s is already constructed" % cmd.data.entity_id
				)
				return
			# cancel_construction() refunds resources and queue_frees the structure
			structure.cancel_construction()

		Enums.CommandType.PAUSE_CONSTRUCTION:
			var structure = _resolve_unit(cmd.data.entity_id, "PAUSE_CONSTRUCTION")
			if structure == null:
				return
			if not _verify_unit_ownership(structure, cmd.player_id, "PAUSE_CONSTRUCTION"):
				return
			if not structure is Structure:
				push_error(
					"PAUSE_CONSTRUCTION: entity_id %s is not a Structure" % cmd.data.entity_id
				)
				return
			if not structure.is_under_construction():
				push_error(
					"PAUSE_CONSTRUCTION: entity_id %s is already constructed" % cmd.data.entity_id
				)
				return
			structure.pause_construction()

		# ── RALLY POINTS ──────────────────────────────────────────────
		Enums.CommandType.SET_RALLY_POINT:
			var structure = _resolve_unit(cmd.data.entity_id, "SET_RALLY_POINT")
			if structure == null:
				return
			if not _verify_unit_ownership(structure, cmd.player_id, "SET_RALLY_POINT"):
				return
			var rally_point = structure.find_child("RallyPoint")
			if rally_point == null:
				push_error("SET_RALLY_POINT: entity_id %s has no RallyPoint" % cmd.data.entity_id)
				return
			rally_point.target_unit = null
			rally_point.global_position = cmd.data.position

		Enums.CommandType.SET_RALLY_POINT_TO_UNIT:
			var structure = _resolve_unit(cmd.data.entity_id, "SET_RALLY_POINT_TO_UNIT")
			if structure == null:
				return
			if not _verify_unit_ownership(structure, cmd.player_id, "SET_RALLY_POINT_TO_UNIT"):
				return
			var target_unit = _resolve_unit(cmd.data.target_unit, "SET_RALLY_POINT_TO_UNIT.target")
			if target_unit == null:
				return
			var rally_point = structure.find_child("RallyPoint")
			if rally_point == null:
				push_error(
					"SET_RALLY_POINT_TO_UNIT: entity_id %s has no RallyPoint" % cmd.data.entity_id
				)
				return
			rally_point.target_unit = target_unit

		# ── STRUCTURE ACTIONS ──────────────────────────────────────────
		Enums.CommandType.SELL_ENTITY:
			var structure = _resolve_unit(cmd.data.entity_id, "SELL_ENTITY")
			if structure == null:
				return
			if not structure is Structure:
				push_error("SELL_ENTITY: entity %s is not a Structure" % cmd.data.entity_id)
				return
			if not _verify_unit_ownership(structure, cmd.player_id, "SELL_ENTITY"):
				return
			structure.toggle_sell()

		Enums.CommandType.REPAIR_ENTITY:
			var structure = _resolve_unit(cmd.data.entity_id, "REPAIR_ENTITY")
			if structure == null:
				return
			if not structure is Structure:
				push_error("REPAIR_ENTITY: entity %s is not a Structure" % cmd.data.entity_id)
				return
			if not _verify_unit_ownership(structure, cmd.player_id, "REPAIR_ENTITY"):
				return
			structure.toggle_repair()

		Enums.CommandType.DISABLE_ENTITY:
			var structure = _resolve_unit(cmd.data.entity_id, "DISABLE_ENTITY")
			if structure == null:
				return
			if not structure is Structure:
				push_error("DISABLE_ENTITY: entity %s is not a Structure" % cmd.data.entity_id)
				return
			if not _verify_unit_ownership(structure, cmd.player_id, "DISABLE_ENTITY"):
				return
			structure.toggle_disable()

		# ── NEW UNIT COMMANDS ─────────────────────────────────────────
		Enums.CommandType.ATTACK_MOVE:
			for entry in cmd.data.targets:
				var parsed = _parse_target_entry(entry, "ATTACK_MOVE")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "ATTACK_MOVE")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "ATTACK_MOVE"):
					continue
				if parsed["pos"] == null:
					push_error("ATTACK_MOVE: target entry missing 'pos'")
					continue
				unit._stopped = false
				if cmd.data.get("queued", false) and unit.action != null:
					unit._enqueue_command(cmd.type, {"pos": parsed["pos"]})
				else:
					unit.action = Actions.AttackMoving.new(parsed["pos"])

		Enums.CommandType.STOP:
			for entry in cmd.data.targets:
				var parsed = _parse_target_entry(entry, "STOP")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "STOP")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "STOP"):
					continue
				unit._stopped = true
				if unit.has_node("UnitCommandQueue"):
					unit.get_node("UnitCommandQueue").clear()
				unit.action = null

		Enums.CommandType.HOLD_POSITION:
			for entry in cmd.data.targets:
				var parsed = _parse_target_entry(entry, "HOLD_POSITION")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "HOLD_POSITION")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "HOLD_POSITION"):
					continue
				unit._stopped = false
				if cmd.data.get("queued", false) and unit.action != null:
					unit._enqueue_command(cmd.type, {})
				else:
					unit.action = Actions.HoldPosition.new()

		Enums.CommandType.MOVE_NO_ATTACK:
			for entry in cmd.data.targets:
				var parsed = _parse_target_entry(entry, "MOVE_NO_ATTACK")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "MOVE_NO_ATTACK")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "MOVE_NO_ATTACK"):
					continue
				if parsed["pos"] == null:
					push_error("MOVE_NO_ATTACK: target entry missing 'pos'")
					continue
				unit._stopped = false
				if cmd.data.get("queued", false) and unit.action != null:
					unit._enqueue_command(cmd.type, {"pos": parsed["pos"]})
				else:
					# Move without attack: set stopped so idle action doesn't trigger after arrival
					unit._stopped = true
					unit.action = Actions.Moving.new(parsed["pos"])

		Enums.CommandType.PATROL:
			for entry in cmd.data.targets:
				var parsed = _parse_target_entry(entry, "PATROL")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "PATROL")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "PATROL"):
					continue
				if parsed["pos"] == null:
					push_error("PATROL: target entry missing 'pos'")
					continue
				unit._stopped = false
				var origin = cmd.data.get("patrol_origin", unit.global_position)
				if cmd.data.get("queued", false) and unit.action != null:
					unit._enqueue_command(cmd.type, {"pos": parsed["pos"], "patrol_origin": origin})
				else:
					unit.action = Actions.Patrolling.new(origin, parsed["pos"])

		Enums.CommandType.REVERSE_MOVE:
			for entry in cmd.data.targets:
				var parsed = _parse_target_entry(entry, "REVERSE_MOVE")
				if parsed.is_empty():
					continue
				var unit = _resolve_unit(parsed["unit_id"], "REVERSE_MOVE")
				if unit == null:
					continue
				if not _verify_unit_ownership(unit, cmd.player_id, "REVERSE_MOVE"):
					continue
				if parsed["pos"] == null:
					push_error("REVERSE_MOVE: target entry missing 'pos'")
					continue
				if not Actions.ReverseMoving.is_applicable(unit):
					continue
				unit._stopped = false
				if cmd.data.get("queued", false) and unit.action != null:
					unit._enqueue_command(cmd.type, {"pos": parsed["pos"]})
				else:
					unit.action = Actions.ReverseMoving.new(parsed["pos"])

		_:
			push_error("Match: unknown command type %s — %s" % [cmd.type, cmd])


func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		# Right-click cancels active command mode
		if (
			event.button_index == MOUSE_BUTTON_RIGHT
			and MatchSignals.active_command_mode != Enums.UnitCommandMode.NORMAL
		):
			MatchSignals.active_command_mode = Enums.UnitCommandMode.NORMAL
			MatchSignals.command_mode_changed.emit(Enums.UnitCommandMode.NORMAL)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Don't deselect during command mode clicks or shift-select
			if MatchSignals.active_command_mode != Enums.UnitCommandMode.NORMAL:
				return
			if Input.is_action_pressed("shift_selecting"):
				return
			MatchSignals.deselect_all_units.emit()


func _set_map(a_map):
	assert(get_node_or_null("Map") == null, "map already set")
	a_map.name = "Map"
	add_child(a_map)
	a_map.owner = self
	MatchGlobal.map = a_map  # for static access by other classes


func _ignore(_value):
	pass


func _get_map():
	return get_node_or_null("Map")


func _set_visible_player(player):
	_conceal_player_units(visible_player)
	_reveal_player_units(player)
	visible_player = player


func _get_visible_players():
	if settings.visibility == settings.Visibility.PER_PLAYER:
		return [visible_player]
	return get_tree().get_nodes_in_group("players")


func _setup_subsystems_dependent_on_map():
	# Ensure TerrainSystem has its mesh geometry. For MapResource maps this is
	# already done by MapSceneBuilder.initialize_terrain_from_meta(); for
	# predefined .tscn maps that have no MapResource we create it now so
	# the navmesh bake has geometry to work with.
	if map.terrain_system:
		map.terrain_system.ensure_mesh(map.size)
	_terrain.update_shape_from_map(map)
	fog_of_war.resize(map.size)
	_recalculate_camera_bounding_planes(map.size)
	navigation.setup(map)
	global_build_grid.build(map)


func _recalculate_camera_bounding_planes(map_size: Vector2):
	_camera.bounding_planes[1] = Plane(-1, 0, 0, -map_size.x)
	_camera.bounding_planes[3] = Plane(0, 0, -1, -map_size.y)


func _setup_players():
	assert(
		_players.get_children().is_empty() or settings.players.is_empty(),
		"players can be defined either in settings or in scene tree, not in both"
	)
	if _players.get_children().is_empty():
		_create_players_from_settings()
	for node in _players.get_children():
		if node is Player:
			node.add_to_group("players")


func _create_players_from_settings():
	# Instantiate each player (Human or AI controller) from their configured controller scene.
	# In multiplayer only the LOCAL peer's Human keeps input controllers;
	# remote Human players have their input nodes removed so they don't
	# react to local UI signals (their commands arrive via NetworkCommandSync).
	var local_idx: int = _get_local_player_index()
	for player_idx: int in range(settings.players.size()):
		var player_settings: PlayerSettings = settings.players[player_idx]
		var player_scene = Constants.CONTROLLER_SCENES[player_settings.controller]
		var player = player_scene.instantiate()
		player.color = player_settings.color
		# TEAM ASSIGNMENT: Each player has a team ID. Units with same team cannot attack each other.
		# Teams are typically auto-assigned by Play.gd (player_index 0 -> team 0, player_index 1 -> team 1, etc.)
		# to ensure playable matches. Custom team assignments override this (for alliances, etc.)
		player.team = player_settings.team
		player.faction = player_settings.faction
		player.uuid = player_settings.uuid
		# set starting resources
		player.initialize_resources(Factions.get_starting_resource())

		# Strip input controllers from remote Human players in multiplayer.
		# In replay mode, strip ALL human input controllers since commands
		# come from the replay data — no player should generate new input.
		var should_strip_input: bool = (
			is_replay_mode
			or (
				NetworkCommandSync.is_active
				and player_settings.controller == Constants.PlayerType.HUMAN
				and player_idx != local_idx
			)
		)
		if should_strip_input and player_settings.controller == Constants.PlayerType.HUMAN:
			for child_name in [
				"UnitActionsController",
				"StructurePlacementHandler",
				"StructureActionHandler",
				"VoiceNarratorController",
				"UnitVoicesController",
			]:
				var child: Node = player.get_node_or_null(child_name)
				if child:
					player.remove_child(child)
					child.queue_free()

		_players.add_child(player)


func _setup_player_units():
	var spawn_points = map.find_child("SpawnPoints").get_children()
	var num_spawns = spawn_points.size()

	# Build list of explicitly claimed spawn indices
	var claimed_spawns: Dictionary = {}  # spawn_index -> player_index
	var players_needing_spawn: Array[int] = []
	var player_list: Array[Player] = []

	for player in _players.get_children():
		if player is Player:
			player_list.append(player)

	for player_idx in range(player_list.size()):
		var spawn_idx = settings.players[player_idx].spawn_index
		if spawn_idx >= 0 and spawn_idx < num_spawns:
			claimed_spawns[spawn_idx] = player_idx
		else:
			players_needing_spawn.append(player_idx)

	# Deterministically assign remaining spawn points to players with random (-1)
	var available_spawns: Array[int] = []
	for i in range(num_spawns):
		if not claimed_spawns.has(i):
			available_spawns.append(i)

	for player_idx in players_needing_spawn:
		if available_spawns.is_empty():
			break
		claimed_spawns[available_spawns[0]] = player_idx
		available_spawns.remove_at(0)

	# Spawn units at assigned positions
	for player_idx in range(player_list.size()):
		var player = player_list[player_idx]
		var predefined_units = player.get_children().filter(func(child): return child is Unit)
		if not predefined_units.is_empty():
			predefined_units.map(func(unit): _setup_unit_groups(unit, unit.player))
		else:
			# Find this player's spawn index
			for spawn_idx in claimed_spawns:
				if claimed_spawns[spawn_idx] == player_idx:
					_spawn_player_units(player, spawn_points[spawn_idx].global_transform)
					break


# here player starting units are defined on a per faction basis
func _spawn_player_units(player, spawn_transform):
	var faction = Factions.get_faction_by_enum(player.faction)
	var new_faction = faction.new()
	var spawn_structure = new_faction.spawn_unit.instantiate()
	_setup_and_spawn_unit(spawn_structure, spawn_transform, player, false)

	if player.faction != Enums.Faction.RADIX:
		return

	var seedling_scene_path := UnitConstants.get_scene_path(Enums.SceneId.RADIX_SEEDLING)
	if seedling_scene_path.is_empty():
		return
	var seedling_scene: PackedScene = load(seedling_scene_path)
	if seedling_scene == null:
		return

	var spawn_positions: Array[Vector3] = []
	for child: Node in spawn_structure.get_children():
		if not (child is Node3D) or not child.name.begins_with("SpawningFlowerBulb"):
			continue
		var bulb := child as Node3D
		var spawn_position := bulb.global_position
		if bulb.has_method("get_spawn_world_position"):
			spawn_position = bulb.get_spawn_world_position()
		var outward: Vector3 = (spawn_position - spawn_structure.global_position) * Vector3(1, 0, 1)
		if outward.length_squared() > 0.0:
			spawn_position += outward.normalized() * 0.45
		spawn_positions.append(spawn_position)

	if spawn_positions.is_empty():
		for seedling_index in range(3):
			var angle := TAU * (float(seedling_index) / 3.0)
			spawn_positions.append(
				spawn_structure.global_position + Vector3.FORWARD.rotated(Vector3.UP, angle) * 1.75
			)

	for seedling_index in range(min(3, spawn_positions.size())):
		var seedling = seedling_scene.instantiate()
		_setup_and_spawn_unit(
			seedling, Transform3D(Basis(), spawn_positions[seedling_index]), player, false
		)


func _spread_initial_creep() -> void:
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is CreepSource:
			node.spread_creep_instantly()


func _find_available_radix_seedling(player: Player, target_position: Vector3) -> Unit:
	var best_seedling: Unit = null
	var best_distance_sq: float = INF
	for child: Node in player.get_children():
		if not (child is Unit):
			continue
		var seedling: Unit = child
		if UnitConstants.get_scene_id(seedling.scene_file_path) != Enums.SceneId.RADIX_SEEDLING:
			continue
		if seedling.action != null and seedling.action is Actions.Constructing:
			continue
		var distance_sq: float = seedling.global_position.distance_squared_to(target_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_seedling = seedling
	return best_seedling


func _is_duplicate_structure_placement(
	player: Player,
	structure_scene_id: int,
	target_transform: Transform3D,
) -> bool:
	for child: Node in player.get_children():
		if not (child is Structure):
			continue
		var existing_structure: Structure = child
		if not is_instance_valid(existing_structure) or existing_structure.is_queued_for_deletion():
			continue
		var existing_scene_path: String = existing_structure.scene_file_path
		if existing_scene_path.is_empty():
			existing_scene_path = existing_structure.get_script().resource_path.replace(
				".gd", ".tscn"
			)
		if UnitConstants.get_scene_id(existing_scene_path) != structure_scene_id:
			continue
		# Duplicate placement commands generated in the same spot should only spawn one structure.
		if existing_structure.global_position.distance_squared_to(target_transform.origin) < 0.0001:
			return true
	return false


func _add_seedling_structure_to_queue(producer: Unit, structure: Structure, scene_id: int) -> void:
	# Create a queue element to track the seedling-started structure's construction
	var scene_path: String = UnitConstants.get_scene_path(scene_id)
	var build_time: float = UnitConstants.get_default_properties(scene_id).get("build_time", 5.0)
	var queue_element = producer.production_queue.ProductionQueueElement.new()
	queue_element.unit_prototype = load(scene_path)
	queue_element.time_total = build_time
	queue_element.time_left = build_time
	queue_element.is_tracking_only = true
	queue_element.tracking_entity_id = structure.id
	queue_element.paused = structure.is_construction_paused
	# Listen for construction completion
	if not structure.constructed.is_connected(
		_on_seedling_structure_constructed.bind(producer, queue_element, structure)
	):
		structure.constructed.connect(
			_on_seedling_structure_constructed.bind(producer, queue_element, structure)
		)
	var tick_callable := _on_seedling_structure_queue_tick.bind(structure, queue_element)
	if not MatchSignals.tick_advanced.is_connected(tick_callable):
		MatchSignals.tick_advanced.connect(tick_callable)
	producer.production_queue._enqueue_element(queue_element)


func _on_seedling_structure_constructed(
	producer: Unit, queue_element, structure: Structure
) -> void:
	# Remove from queue when construction finishes
	var tick_callable := _on_seedling_structure_queue_tick.bind(structure, queue_element)
	if MatchSignals.tick_advanced.is_connected(tick_callable):
		MatchSignals.tick_advanced.disconnect(tick_callable)
	if producer != null and producer.has_node("ProductionQueue"):
		producer.production_queue._remove_element(queue_element)


func _on_seedling_structure_queue_tick(structure: Structure, queue_element) -> void:
	if structure == null or not is_instance_valid(structure):
		return
	if queue_element == null:
		return
	var total: float = 5.0
	if queue_element.time_total != null:
		total = maxf(float(queue_element.time_total), 0.001)
	var progress: float = clampf(structure.construction_progress, 0.0, 1.0)
	queue_element.time_left = maxf(0.0, total * (1.0 - progress))
	queue_element.paused = structure.is_construction_paused


func _setup_and_spawn_unit(unit, a_transform, player, self_constructing = false):
	unit.global_transform = a_transform
	if unit is Structure and self_constructing:
		unit.mark_as_under_construction(true)
	_setup_unit_groups(unit, player)
	player.add_child(unit)
	MatchSignals.unit_spawned.emit(unit)


func _setup_unit_groups(unit, player):
	# Categorize units into groups that the UI and game systems use for visibility/filtering
	unit.add_to_group("units")
	if player == _get_local_player():
		unit.add_to_group("controlled_units")
	else:
		unit.add_to_group("adversary_units")

	# TEAM-BASED VISION SHARING: Units are visible if their player is visible OR on same team.
	# This is how team vision works: all units controlled by your team are automatically revealed.
	# The UI systems (like FogOfWar) check for \"revealed_units\" group membership to decide what to show.
	# If a teammate's unit is visible, it goes into revealed_units and the UI renders it.
	if player in visible_players:
		unit.add_to_group("revealed_units")
	else:
		# Check if any visible player is on the same team — if so, share vision
		for candidate_visible_player in visible_players:
			if candidate_visible_player != null and candidate_visible_player.team == player.team:
				unit.add_to_group("revealed_units")
				break


## Returns the player controlled by this peer.
## In multiplayer each peer has a different local player. In single-player
## this is the Human player (or the first player if no human exists).
func _get_local_player() -> Player:
	if _local_player != null:
		return _local_player
	# Fallback for early calls before _ready sets _local_player (e.g. tests)
	var all_players: Array = get_tree().get_nodes_in_group("players")
	if all_players.is_empty():
		return null
	return all_players[_get_local_player_index()]


## Compute which player index this peer controls.
## Peers are sorted by ID; each gets the matching player slot.
func _get_local_player_index() -> int:
	if not NetworkCommandSync.is_active:
		# Single-player: use settings.visible_player (the human slot)
		return settings.visible_player if settings.visible_player >= 0 else 0
	var peers: Array = NetworkCommandSync.get_peer_ids()
	peers.sort()
	return peers.find(multiplayer.get_unique_id())


func _move_camera_to_initial_position():
	var local_player: Player = _get_local_player()
	if local_player != null:
		_move_camera_to_player_units_crowd_pivot(local_player)
	else:
		_move_camera_to_player_units_crowd_pivot(get_tree().get_nodes_in_group("players")[0])


func _move_camera_to_player_units_crowd_pivot(player):
	var player_units = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit.player == player
	)
	assert(not player_units.is_empty(), "player must have at least one initial unit")
	var crowd_pivot = MatchUtils.Movement.calculate_aabb_crowd_pivot_yless(player_units)
	_camera.set_position_safely(crowd_pivot)


func _reveal_player_units(player):
	if player == null:
		return
	for unit in get_tree().get_nodes_in_group("units").filter(
		func(a_unit): return a_unit.player == player
	):
		unit.add_to_group("revealed_units")


func _conceal_player_units(player):
	if player == null:
		return
	for unit in get_tree().get_nodes_in_group("units").filter(
		func(a_unit): return a_unit.player == player
	):
		unit.remove_from_group("revealed_units")


## here the HUD will be wired up with everything from the match
func wire_hud():
	hud.set_player_settings(settings)
	# Refresh credits/energy display — the restore may have set them
	# before the HUD knew which player to display.
	if visible_player:
		MatchSignals.player_resource_changed.emit(
			visible_player, visible_player.credits, Enums.ResourceType.CREDITS
		)
		MatchSignals.player_resource_changed.emit(
			visible_player, visible_player.energy, Enums.ResourceType.ENERGY
		)


# ──────────────────────────────────────────────────────────────────────
# MULTIPLAYER RECONNECT / DISCONNECT
# ──────────────────────────────────────────────────────────────────────


func _register_peer_uuids() -> void:
	var peers: Array = NetworkCommandSync.get_peer_ids()
	peers.sort()
	var uuids: Array = []
	var all_players: Array = get_tree().get_nodes_in_group("players")
	all_players.sort_custom(func(a, b): return a.id < b.id)
	for i in range(mini(peers.size(), all_players.size())):
		uuids.append(all_players[i].uuid)
	NetworkCommandSync.register_peer_uuids(peers, uuids)


func _on_player_reconnected(peer_id: int, uuid: String) -> void:
	# Host sends the full game state snapshot to the reconnecting peer
	if multiplayer.is_server():
		var state_data: Dictionary = SaveSystem.serialize_match_to_dict(self)
		NetworkCommandSync.send_state_snapshot(peer_id, state_data)


func _on_reconnect_timer_expired(peer_id: int) -> void:
	if _match_ended:
		return
	# Find the disconnected player by UUID and reassign their units
	var uuid: String = NetworkCommandSync.get_uuid_for_peer(peer_id)
	var disconnected_player: Player = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.uuid == uuid:
			disconnected_player = p
			break
	if disconnected_player == null:
		return

	# Find a teammate (same team, different player)
	var teammate: Player = null
	for p in get_tree().get_nodes_in_group("players"):
		if p != disconnected_player and p.team == disconnected_player.team:
			teammate = p
			break

	# Reassign or destroy all units belonging to disconnected player
	var units_to_process: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.player == disconnected_player:
			units_to_process.append(unit)

	for unit in units_to_process:
		if teammate != null:
			# Transfer to teammate — reparent so unit.player (get_parent()) is correct
			var old_pos: Vector3 = unit.global_position
			var old_rot: Vector3 = unit.rotation
			unit.get_parent().remove_child(unit)
			teammate.add_child(unit)
			unit._player_ref = teammate  # _ready() won't re-run after reparent
			unit.global_position = old_pos
			unit.rotation = old_rot
			# Update group membership
			unit.remove_from_group("controlled_units")
			unit.remove_from_group("adversary_units")
			if teammate == _local_player:
				unit.add_to_group("controlled_units")
			else:
				unit.add_to_group("adversary_units")
			# Update vision
			if teammate in visible_players:
				if not unit.is_in_group("revealed_units"):
					unit.add_to_group("revealed_units")
		else:
			# No teammate — destroy the unit
			unit.hp = 0

	# Transfer resources to teammate
	if teammate != null:
		teammate.credits += disconnected_player.credits
		teammate.energy += disconnected_player.energy
		disconnected_player.credits = 0
		disconnected_player.energy = 0


func _on_match_ended() -> void:
	_match_ended = true


func _on_host_disconnected() -> void:
	# Ignore if match already ended (statistics screen handles exit)
	if _match_ended:
		return
	# Auto-save the game state so it can be rehosted from lobby
	SaveSystem.save_game()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")


# ──────────────────────────────────────────────────────────────────────
# SAVE / LOAD RESTORATION
# ──────────────────────────────────────────────────────────────────────


func _restore_from_save(save: SaveGameResource) -> void:
	tick = save.match_tick

	# Restore player state — match by player ID, not array index
	var player_by_id: Dictionary = {}
	for p in get_tree().get_nodes_in_group("players"):
		player_by_id[p.id] = p
	for pd: Dictionary in save.players_data:
		var pid: int = pd.get("id", -1)
		var player: Player = player_by_id.get(pid, null)
		if player == null:
			continue
		player.credits = int(pd.get("credits", 0))
		player.energy = int(pd.get("energy", 0))
		if pd.has("support_powers"):
			player.support_powers = pd["support_powers"].duplicate(true)

	# Set EntityRegistry next_id so new entities get IDs after saved ones
	EntityRegistry._next_id = save.entity_registry_next_id

	# ── CLEAN UP MAP-SPAWNED RESOURCES ──────────────────────────────
	# The fresh map spawns ALL resource nodes, but some may have been
	# depleted during the match. Remove any ResourceUnit entities whose
	# IDs are NOT present in the save data so the EntityRegistry matches
	# the host's state exactly.
	var saved_resource_ids: Dictionary = {}
	for ed: Dictionary in save.entities_data:
		if ed.get("entity_type", "unit") != "resource":
			continue
		saved_resource_ids[ed.get("entity_id", -1)] = true

	var stale_resources: Array = []
	for eid: int in EntityRegistry.entities:
		var e = EntityRegistry.entities[eid]
		if e != null and is_instance_valid(e) and e is ResourceUnit:
			if not saved_resource_ids.has(eid):
				stale_resources.append(e)
	for e in stale_resources:
		EntityRegistry.unregister(e)
		e.queue_free()

	# ── RESTORE RESOURCE AMOUNTS / SPAWN MISSING RESOURCES ─────────
	for ed: Dictionary in save.entities_data:
		if ed.get("entity_type", "unit") != "resource":
			continue
		var eid: int = ed.get("entity_id", -1)
		var existing = EntityRegistry.get_unit(eid)
		if existing:
			if ed.has("resource_amount"):
				existing.resource = ed["resource_amount"]
		else:
			# Dynamically spawned resource — instantiate it on the client.
			var rsc_path: String = ed.get("scene_path", "")
			if rsc_path.is_empty():
				continue
			var rsc_proto = load(rsc_path)
			if rsc_proto == null:
				push_warning("RESTORE: cannot load resource scene %s" % rsc_path)
				continue
			var rsc = rsc_proto.instantiate()
			var rsc_pos: Vector3 = SaveSystem._arr_to_vec3(ed.get("position", [0, 0, 0]))
			rsc._saved_id = eid
			rsc.position = rsc_pos
			get_tree().current_scene.add_child(rsc)
			rsc.global_position = rsc_pos
			if ed.has("resource_amount"):
				rsc.resource = ed["resource_amount"]

	# ── SPAWN UNIT ENTITIES ─────────────────────────────────────────
	for ed: Dictionary in save.entities_data:
		if ed.get("entity_type", "unit") != "unit":
			continue

		var scene_path: String = ed.get("scene_path", "")
		if scene_path.is_empty():
			push_warning(
				"RESTORE: skipping entity with empty scene_path, id=%d" % ed.get("entity_id", -1)
			)
			continue
		var proto = load(scene_path)
		if proto == null:
			push_warning("_restore_from_save: cannot load %s" % scene_path)
			continue
		var entity = proto.instantiate()
		var pos: Vector3 = SaveSystem._arr_to_vec3(ed.get("position", [0, 0, 0]))
		var rot: Vector3 = SaveSystem._arr_to_vec3(ed.get("rotation", [0, 0, 0]))
		var spawn_transform := Transform3D(Basis.from_euler(rot), pos)

		var player_id: int = ed.get("player_id", -1)
		var player: Player = player_by_id.get(player_id, null)
		if player == null:
			push_warning("_restore_from_save: no player with id %d" % player_id)
			entity.queue_free()
			continue

		var _fk: String = Enums.Faction.keys()[player.faction]
		push_warning(
			(
				"RESTORE: entity=%d player_id=%d faction=%s scene=%s"
				% [ed.get("entity_id", -1), player_id, _fk, scene_path.get_file()]
			)
		)

		# Pre-set the entity ID before adding to tree (so EntityRegistry gets the right ID)
		entity._saved_id = ed.get("entity_id", -1)

		var is_structure: bool = ed.get("is_structure", false)
		var self_constructing: bool = ed.get("self_constructing", false)

		# Pass the transform directly — do NOT read entity.global_transform
		# before add_child, as the getter returns identity when not in tree.
		_setup_and_spawn_unit(entity, spawn_transform, player, self_constructing)

		# Re-apply position AFTER add_child to guarantee correctness
		entity.global_position = pos
		entity.rotation = rot

		# Restore HP
		if ed.has("hp"):
			entity.hp = ed["hp"]
		if ed.has("hp_max"):
			entity.hp_max = ed["hp_max"]
		if ed.has("stopped"):
			entity._stopped = ed["stopped"]

		# Restore structure-specific state
		if is_structure:
			if ed.has("construction_progress") and ed["construction_progress"] != null:
				entity._construction_progress = ed["construction_progress"]
			if entity.has_method("refresh_construction_visuals"):
				entity.refresh_construction_visuals()
			if ed.get("is_disabled", false):
				entity.is_disabled = true
			if ed.get("is_selling", false):
				entity.is_selling = true
			if ed.get("is_repairing", false):
				entity.is_repairing = true
			if ed.get("is_construction_paused", false):
				entity.is_construction_paused = true
			if ed.has("sell_ticks_remaining"):
				entity._sell_ticks_remaining = ed["sell_ticks_remaining"]
			if ed.has("self_construction_speed"):
				entity._self_construction_speed = ed["self_construction_speed"]
			if ed.has("trickle_cost") and ed["trickle_cost"] != null:
				entity._trickle_cost = ed["trickle_cost"]
			if ed.has("trickle_cost_deducted"):
				entity._trickle_cost_deducted = ed["trickle_cost_deducted"]

			# Restore production queue
			var pq = entity.find_child("ProductionQueue")
			if pq and ed.has("production_queue"):
				SaveSystem.restore_production_queue(pq, ed["production_queue"])

			# Restore rally point
			var rally = entity.find_child("RallyPoint")
			if rally:
				if ed.has("rally_position") and ed["rally_position"] != null:
					rally.global_position = SaveSystem._arr_to_vec3(ed["rally_position"])
				var rally_target_id: int = ed.get("rally_target_unit", -1)
				if rally_target_id >= 0:
					var target = EntityRegistry.get_unit(rally_target_id)
					if target:
						rally.target_unit = target

	# Restore actions AFTER all entities are spawned (so cross-references resolve)
	for ed in save.entities_data:
		if ed.get("entity_type", "unit") != "unit":
			continue
		var eid: int = ed.get("entity_id", -1)
		var entity = EntityRegistry.get_unit(eid)
		if entity == null:
			continue
		if ed.has("action"):
			SaveSystem.restore_action_on_unit(entity, ed["action"])
		# Restore command queue
		var queue_node = entity.find_child("UnitCommandQueue")
		if queue_node and ed.has("command_queue"):
			SaveSystem.restore_command_queue(queue_node, ed["command_queue"])

	# ── FORCE NAVMESH SYNC ─────────────────────────────────────────
	# MovementObstacle._ready() awaits a process frame before
	# registering with the navigation group and requesting a rebake.
	# The tick timer starts right after _ready(), so the first ticks
	# would use a navmesh WITHOUT structure carve-outs, causing path
	# divergence vs the host.  Fix: register obstacles immediately
	# and perform a synchronous rebake before any ticks fire.
	for eid: int in EntityRegistry.entities:
		var e = EntityRegistry.entities[eid]
		if e == null or not is_instance_valid(e):
			continue
		var obstacle = e.find_child("MovementObstacle")
		if obstacle and obstacle.affect_navigation_mesh:
			var grp: String = NavigationConstants.DOMAIN_TO_GROUP_MAPPING[obstacle.domain]
			if not obstacle.is_in_group(grp):
				obstacle.add_to_group(grp)
			obstacle.set_navigation_map(
				navigation.get_navigation_map_rid_by_domain(obstacle.domain)
			)
	navigation.rebake_terrain_sync()
	_rebuild_wall_connections()


## Re-derive wall section connections between constructed WallPillars.
## Called after restoring from a save since WallSections are not serialized.
func _rebuild_wall_connections() -> void:
	for unit in get_tree().get_nodes_in_group("units"):
		if not "wall_sections" in unit:
			continue
		if not "connection_length" in unit:
			continue
		if not unit.is_constructed():
			continue
		unit._connect_to_nearby_pillars()
