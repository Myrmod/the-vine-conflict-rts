# CommandBus: Central command queue shared by ALL players (human, AI, and replay).
#
# DESIGN PRINCIPLE: Every game-changing action MUST flow through push_command() → record → execute.
# This is the ONLY way to modify game state deterministically. Direct calls to unit.action,
# production_queue.produce(), or MatchSignals.setup_and_spawn_unit are FORBIDDEN — they bypass
# the replay system and break determinism.
#
# PIPELINE:
#   Producer (human input / AI decision) → push_command() → validate → queue by tick
#     → ReplayRecorder.record_command() (if recording)
#   Match._on_tick() → get_commands_for_tick() → Match._execute_command() (applies state)
#
# REPLAY PLAYBACK:
#   get_commands_for_tick() checks ReplayRecorder.mode:
#     RECORD/OFF → serve from live queue
#     PLAY       → serve from loaded replay data
#
# SERIALIZATION RULE: Commands must contain ONLY serializable values (ints, floats, strings,
# vectors, dictionaries, arrays). NO object references, NO Resources, NO Nodes. Units are
# referenced by their EntityRegistry ID (int). Scenes by resource_path (string).
#
# COMMAND SCHEMA (required top-level fields):
#   { tick: int, type: Enums.CommandType, player_id: int, data: Dictionary }
#   - tick:      The game tick on which this command should execute
#   - type:      Enum identifying the action (see Enums.CommandType)
#   - player_id: The player who issued this command (Player.id). Used for debugging,
#                multiplayer authority checks, and replay attribution
#   - data:      Type-specific payload (validated by _validate_command_schema)

extends Node

# Command queue indexed by tick number.
# Structure: { tick_number: [command_dict, command_dict, ...] }
var commands := {} # int → Array[Dictionary]

# Clear all queued commands - used when starting a fresh live match
func clear():
	# Clear all stored commands
	commands.clear()


func _is_serializable_value(value: Variant) -> bool:
	var value_type = typeof(value)
	var allowed_types = [
		TYPE_NIL,
		TYPE_BOOL,
		TYPE_INT,
		TYPE_FLOAT,
		TYPE_STRING,
		TYPE_STRING_NAME,
		TYPE_VECTOR2,
		TYPE_VECTOR2I,
		TYPE_RECT2,
		TYPE_RECT2I,
		TYPE_VECTOR3,
		TYPE_VECTOR3I,
		TYPE_TRANSFORM2D,
		TYPE_VECTOR4,
		TYPE_VECTOR4I,
		TYPE_PLANE,
		TYPE_QUATERNION,
		TYPE_AABB,
		TYPE_BASIS,
		TYPE_TRANSFORM3D,
		TYPE_PROJECTION,
		TYPE_COLOR,
		TYPE_NODE_PATH,
		TYPE_DICTIONARY,
		TYPE_ARRAY,
		TYPE_PACKED_BYTE_ARRAY,
		TYPE_PACKED_INT32_ARRAY,
		TYPE_PACKED_INT64_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY,
		TYPE_PACKED_FLOAT64_ARRAY,
		TYPE_PACKED_STRING_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY,
		TYPE_PACKED_VECTOR3_ARRAY,
		TYPE_PACKED_COLOR_ARRAY,
	]
	if not allowed_types.has(value_type):
		return false

	if value_type == TYPE_ARRAY:
		for element in value:
			if not _is_serializable_value(element):
				return false
		return true

	if value_type == TYPE_DICTIONARY:
		for key in value.keys():
			if not _is_serializable_value(key):
				return false
			if not _is_serializable_value(value[key]):
				return false
		return true

	return true


func _validate_target_dict(entry: Variant, command_name: String, require_pos: bool) -> bool:
	if typeof(entry) != TYPE_DICTIONARY:
		push_error("CommandBus: %s target entry must be Dictionary" % command_name)
		return false
	if not entry.has("unit") or typeof(entry["unit"]) != TYPE_INT:
		push_error("CommandBus: %s target entry must contain int 'unit'" % command_name)
		return false
	if require_pos and (not entry.has("pos") or typeof(entry["pos"]) != TYPE_VECTOR3):
		push_error("CommandBus: %s target entry must contain Vector3 'pos'" % command_name)
		return false
	if entry.has("pos") and entry["pos"] != null and typeof(entry["pos"]) != TYPE_VECTOR3:
		push_error("CommandBus: %s target entry 'pos' must be Vector3 when present" % command_name)
		return false
	if entry.has("rot") and entry["rot"] != null and typeof(entry["rot"]) != TYPE_VECTOR3:
		push_error("CommandBus: %s target entry 'rot' must be Vector3 when present" % command_name)
		return false
	return true


func _validate_command_schema(cmd: Dictionary) -> bool:
	match cmd.type:
		Enums.CommandType.MOVE:
			if not cmd.data.has("targets") or typeof(cmd.data.targets) != TYPE_ARRAY:
				push_error("CommandBus: MOVE requires Array data.targets")
				return false
			for entry in cmd.data.targets:
				if not _validate_target_dict(entry, "MOVE", true):
					return false
		Enums.CommandType.MOVING_TO_UNIT, Enums.CommandType.FOLLOWING, \
		Enums.CommandType.COLLECTING_RESOURCES_SEQUENTIALLY, Enums.CommandType.AUTO_ATTACKING:
			if not cmd.data.has("target_unit") or typeof(cmd.data.target_unit) != TYPE_INT:
				push_error("CommandBus: command requires int data.target_unit")
				return false
			if not cmd.data.has("targets") or typeof(cmd.data.targets) != TYPE_ARRAY:
				push_error("CommandBus: command requires Array data.targets")
				return false
			for entry in cmd.data.targets:
				if not _validate_target_dict(entry, "TARGETED_ACTION", false):
					return false
		Enums.CommandType.CONSTRUCTING:
			if not cmd.data.has("structure") or typeof(cmd.data.structure) != TYPE_INT:
				push_error("CommandBus: CONSTRUCTING requires int data.structure")
				return false
			if not cmd.data.has("selected_constructors") or typeof(cmd.data.selected_constructors) != TYPE_ARRAY:
				push_error("CommandBus: CONSTRUCTING requires Array data.selected_constructors")
				return false
			for entry in cmd.data.selected_constructors:
				if not _validate_target_dict(entry, "CONSTRUCTING", false):
					return false
		Enums.CommandType.ENTITY_IS_QUEUED:
			# Queue unit production at a structure. data.entity_id = structure ID, data.unit_type = scene path.
			if not cmd.data.has("entity_id") or typeof(cmd.data.entity_id) != TYPE_INT:
				push_error("CommandBus: ENTITY_IS_QUEUED requires int data.entity_id")
				return false
			if not cmd.data.has("unit_type") or typeof(cmd.data.unit_type) != TYPE_STRING:
				push_error("CommandBus: ENTITY_IS_QUEUED requires String data.unit_type")
				return false
		Enums.CommandType.STRUCTURE_PLACED:
			# Place a new structure. data.structure_prototype = scene path. Player comes from cmd.player_id.
			if not cmd.data.has("structure_prototype") or typeof(cmd.data.structure_prototype) != TYPE_STRING:
				push_error("CommandBus: STRUCTURE_PLACED requires String data.structure_prototype")
				return false
			if not cmd.data.has("transform") or typeof(cmd.data.transform) != TYPE_TRANSFORM3D:
				push_error("CommandBus: STRUCTURE_PLACED requires Transform3D data.transform")
				return false
		Enums.CommandType.ENTITY_PRODUCTION_CANCELED:
			if not cmd.data.has("entity_id") or typeof(cmd.data.entity_id) != TYPE_INT:
				push_error("CommandBus: ENTITY_PRODUCTION_CANCELED requires int data.entity_id")
				return false
			if not cmd.data.has("unit_type") or typeof(cmd.data.unit_type) != TYPE_STRING:
				push_error("CommandBus: ENTITY_PRODUCTION_CANCELED requires String data.unit_type")
				return false
		Enums.CommandType.PRODUCTION_CANCEL_ALL:
			# Cancel all production at a structure. data.entity_id = structure ID.
			if not cmd.data.has("entity_id") or typeof(cmd.data.entity_id) != TYPE_INT:
				push_error("CommandBus: PRODUCTION_CANCEL_ALL requires int data.entity_id")
				return false
		Enums.CommandType.ACTION_CANCEL:
			if not cmd.data.has("targets") or typeof(cmd.data.targets) != TYPE_ARRAY:
				push_error("CommandBus: ACTION_CANCEL requires Array data.targets")
				return false
			for entry in cmd.data.targets:
				if not _validate_target_dict(entry, "ACTION_CANCEL", false):
					return false
		Enums.CommandType.CANCEL_CONSTRUCTION:
			# Cancel an under-construction structure (refunds resources, frees node).
			if not cmd.data.has("entity_id") or typeof(cmd.data.entity_id) != TYPE_INT:
				push_error("CommandBus: CANCEL_CONSTRUCTION requires int data.entity_id")
				return false
		Enums.CommandType.SET_RALLY_POINT:
			# Set rally point to terrain position. data.entity_id = structure, data.position = Vector3.
			if not cmd.data.has("entity_id") or typeof(cmd.data.entity_id) != TYPE_INT:
				push_error("CommandBus: SET_RALLY_POINT requires int data.entity_id")
				return false
			if not cmd.data.has("position") or typeof(cmd.data.position) != TYPE_VECTOR3:
				push_error("CommandBus: SET_RALLY_POINT requires Vector3 data.position")
				return false
		Enums.CommandType.SET_RALLY_POINT_TO_UNIT:
			# Set rally point to follow a unit. data.entity_id = structure, data.target_unit = unit ID.
			if not cmd.data.has("entity_id") or typeof(cmd.data.entity_id) != TYPE_INT:
				push_error("CommandBus: SET_RALLY_POINT_TO_UNIT requires int data.entity_id")
				return false
			if not cmd.data.has("target_unit") or typeof(cmd.data.target_unit) != TYPE_INT:
				push_error("CommandBus: SET_RALLY_POINT_TO_UNIT requires int data.target_unit")
				return false
		_:
			push_error("CommandBus: unknown command type %s" % cmd.type)
			return false
	return true


func _is_valid_command(cmd: Variant) -> bool:
	if typeof(cmd) != TYPE_DICTIONARY:
		push_error("CommandBus: command must be a Dictionary")
		return false
	if not cmd.has("tick") or typeof(cmd.tick) != TYPE_INT:
		push_error("CommandBus: command missing int tick")
		return false
	if not cmd.has("type") or typeof(cmd.type) != TYPE_INT:
		push_error("CommandBus: command missing int type")
		return false
	if not cmd.has("player_id") or typeof(cmd.player_id) != TYPE_INT:
		push_error("CommandBus: command missing int player_id (every command must identify its issuing player)")
		return false
	if not cmd.has("data") or typeof(cmd.data) != TYPE_DICTIONARY:
		push_error("CommandBus: command missing Dictionary data")
		return false
	if not _is_serializable_value(cmd):
		push_error("CommandBus: command contains non-serializable values or object references")
		return false
	if not _validate_command_schema(cmd):
		return false
	return true


func push_command(cmd: Dictionary):
	# Validate, store, and record a command for execution at the specified tick.
	# Called by human input handlers (UnitActionsController, StructurePlacementHandler)
	# and AI controllers (EconomyController, OffenseController, etc.) alike.
	# During replay, all commands come from the replay data — block any new commands
	# to prevent AI controllers from interfering with deterministic playback.
	if ReplayRecorder.mode == ReplayRecorder.Mode.PLAY:
		return
	if not _is_valid_command(cmd):
		return
	var t: int = cmd.tick
	if not commands.has(t):
		commands[t] = []
	commands[t].append(cmd)
	# Record for replay file so this exact command replays identically later
	ReplayRecorder.record_command(cmd)

func get_commands_for_tick(a_tick: int) -> Array:
	# Returns all commands that should execute on this tick.
	# During replay: reads from the loaded replay data (ReplayRecorder.replay.commands).
	# During live play: reads from the local queue populated by push_command().
	if ReplayRecorder.mode == ReplayRecorder.Mode.PLAY:
		return _replay_commands_for_tick(a_tick)
	else:
		return _live_commands_for_tick(a_tick)

func _replay_commands_for_tick(a_tick: int) -> Array:
	# Return commands for this tick from the tick-indexed map built by load_from_replay_array().
	if not commands.has(a_tick):
		return []
	return commands[a_tick]

func _live_commands_for_tick(a_tick: int) -> Array:
	# Return commands queued for this tick during live gameplay.
	if not commands.has(a_tick):
		return []
	return commands[a_tick]

func load_from_replay_array(arr: Array):
	# Bulk-load all commands from a replay file into the queue.
	# Called by Loading.gd when a replay is selected for playback.
	commands.clear()

	for entry in arr:
		var tick = entry.tick
		var cmd = entry

		if not commands.has(tick):
			commands[tick] = []

		commands[tick].append(cmd)
