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
const Human = preload("res://source/match/players/human/Human.gd")

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


func _enter_tree():
	assert(settings != null, "match cannot start without settings, see examples in tests/manual/")
	assert(map != null, "match cannot start without map, see examples in tests/manual/")


func _ready():
	if is_replay_mode:
		ReplayRecorder.start_replay()

	MatchSignals.setup_and_spawn_unit.connect(_setup_and_spawn_unit)
	_setup_subsystems_dependent_on_map()
	_setup_players()
	_setup_player_units()
	visible_player = get_tree().get_nodes_in_group("players")[settings.visible_player]
	_move_camera_to_initial_position()

	# Reset tick counter for this match
	tick = 0

	# Start the deterministic tick timer (10 ticks/sec = 100ms per tick)
	var timer := Timer.new()
	timer.wait_time = 1.0 / MatchConstants.TICK_RATE
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)

	if settings.visibility == settings.Visibility.FULL:
		fog_of_war.reveal()
	MatchSignals.match_started.emit()

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
func _on_tick():
	tick += 1
	_process_commands_for_tick()
	# Notify AI controllers and other tick-driven systems.
	# This fires AFTER commands are executed, so listeners see up-to-date game state.
	MatchSignals.tick_advanced.emit()


# Fetch and execute every command for the current tick.
# CommandBus decides the source: live queue during gameplay, replay data during playback.
func _process_commands_for_tick():
	var commands_for_tick = CommandBus.get_commands_for_tick(tick)
	if commands_for_tick.is_empty():
		return
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
			var structure_prototype = load(cmd.data.structure_prototype)
			if structure_prototype == null:
				push_error("STRUCTURE_PLACED: cannot load %s" % cmd.data.structure_prototype)
				return
			var self_constructing = cmd.data.get("self_constructing", false)
			var off_field_deploy = cmd.data.get("off_field_deploy", false)
			var is_trickle = cmd.data.get("trickle", false)
			var construction_cost = (
				UnitConstants
				. DEFAULT_PROPERTIES
				. get(cmd.data.structure_prototype, {})
				. get("costs", null)
			)
			if off_field_deploy:
				# Cost already handled during queue production. Deploy with quick build.
				var unit = structure_prototype.instantiate()
				MatchSignals.setup_and_spawn_unit.emit(unit, cmd.data.transform, player, true)
				if unit is Structure:
					unit._self_construction_speed = 2.0  # 0.5 s build
			elif is_trickle:
				# ON_FIELD + TRICKLE: no upfront cost — structure trickles during construction
				var unit = structure_prototype.instantiate()
				if unit is Structure and construction_cost != null:
					unit._trickle_cost = construction_cost.duplicate()
				MatchSignals.setup_and_spawn_unit.emit(unit, cmd.data.transform, player, true)
			else:
				# DONT_TRICKLE: deduct full cost upfront (also used by AI)
				if construction_cost != null:
					if not player.has_resources(construction_cost):
						push_warning(
							(
								"STRUCTURE_PLACED: player %s cannot afford %s"
								% [player.id, cmd.data.structure_prototype]
							)
						)
						return
					player.subtract_resources(construction_cost)
				(
					MatchSignals
					. setup_and_spawn_unit
					. emit(
						structure_prototype.instantiate(),
						cmd.data.transform,
						player,
						self_constructing,
					)
				)

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
			var unit_prototype = load(cmd.data.unit_type)
			if unit_prototype == null:
				push_error("ENTITY_IS_QUEUED: cannot load %s" % cmd.data.unit_type)
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
			var unit_prototype = load(cmd.data.unit_type)
			if unit_prototype == null or not structure.has_node("ProductionQueue"):
				return
			for element in structure.production_queue.get_elements():
				if element.unit_prototype.resource_path == cmd.data.unit_type:
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
	MatchGlobal.map = a_map  # for static access by other classes, e.g. VineSpawner


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
	_terrain.update_shape_from_map_size(map.size)
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
	# Instantiate each player (Human or AI controller) from their configured controller scene
	for player_settings in settings.players:
		var player_scene = Constants.CONTROLLER_SCENES[player_settings.controller]
		var player = player_scene.instantiate()
		player.color = player_settings.color
		# TEAM ASSIGNMENT: Each player has a team ID. Units with same team cannot attack each other.
		# Teams are typically auto-assigned by Play.gd (player_index 0 -> team 0, player_index 1 -> team 1, etc.)
		# to ensure playable matches. Custom team assignments override this (for alliances, etc.)
		player.team = player_settings.team
		player.faction = player_settings.faction
		# set starting resources
		player.initialize_resources(Factions.get_starting_resource())
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
	var spawn_unit = faction.new().spawn_unit
	var spawn_unit_instant = faction.new().spawn_unit.instantiate()
	_setup_and_spawn_unit(faction.new().spawn_unit.instantiate(), spawn_transform, player, false)


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
	if player == _get_human_player():
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


func _get_human_player():
	var human_players = get_tree().get_nodes_in_group("players").filter(
		func(player): return player is Human
	)
	assert(human_players.size() <= 1, "more than one human player is not allowed")
	if not human_players.is_empty():
		return human_players[0]
	return null


func _move_camera_to_initial_position():
	var human_player = _get_human_player()
	if human_player != null:
		_move_camera_to_player_units_crowd_pivot(human_player)
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
