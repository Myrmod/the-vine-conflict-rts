# REPLAY SYSTEM: Records all game-changing commands and settings so matches can be perfectly replayed.
# The core idea: every action a player or AI takes becomes a command queued through CommandBus.
# These commands are recorded by ReplayRecorder, which saves them along with match settings.
# During replay: the same commands execute in the same tick order → deterministic identical outcome.
#
# REPLAY FLOW:
# 1. Match starts: ReplayRecorder.start_recording() initializes
# 2. During gameplay: CommandBus.push_command() calls ReplayRecorder.record_command()
# 3. Human/AI generates commands, they're stored in replay.commands array
# 4. Match ends: ReplayRecorder saves to file (ReplayResource)
# 5. User selects replay: Play.gd loads replay → CommandBus.load_from_replay_array()
# 6. Replay playback: CommandBus returns commands from loaded replay instead of queue
# 7. Match executes: identical ticks and commands = identical game (deterministic)
#
# See CommandBus.get_commands_for_tick() for how it switches between live queue and replay playback.
extends Node

enum Mode {OFF, RECORD, PLAY}

@export var mode: Mode = Mode.OFF
@export var replay := ReplayResource.new()

func _ready():
	MatchSignals.connect("match_finished_with_defeat", _on_match_finished_with_defeat)
	MatchSignals.connect("match_finished_with_victory", _on_match_finished_with_victory)
	MatchSignals.connect("match_aborted", _on_match_aborted)

func start_recording(match: Match):
	# Initialize replay recording with match metadata and settings.
	# All subsequent commands will be recorded via record_command().
	mode = Mode.RECORD
	replay = ReplayResource.new()  # Reset to a fresh replay
	replay.tick_rate = match.TICK_RATE
	replay.settings = match.settings
	replay.map = match.map.scene_file_path
	replay.match_seed = Match.rng.seed
	replay.commands.clear()
	# Store serialized player data separately to avoid Resource reference issues
	replay.players_data = _serialize_players(match.settings.players)

## Record command for replay playback
func record_command(cmd: Dictionary):
	# Called by CommandBus.push_command() every time a command is queued.
	# Stores a copy so we can save it to disk and replay it later.
	if mode != Mode.RECORD:
		return
	replay.commands.append(cmd.duplicate(true))

func stop_recording():
	mode = Mode.OFF

## replay_2026-02-05T19-00-22.save
func save_to_file():
	# Clear players from settings since we store them separately in players_data
	# This avoids storing Resource objects which cause serialization issues
	replay.settings.players = []
	
	if not Utils._detect_potential_recursion(replay, {}, "replay", {}):
		push_error("Replay validation failed — not saving")
		return
	var path = get_replay_path()
	var err = Utils.FileIO.save_resource(replay, path)
	if err != OK:
		printerr("Replay save failed:", err)

func load_from_file(path: String) -> ReplayResource:
	replay = Utils.FileIO.load_resource(path)
	return replay

func start_replay():
	mode = Mode.PLAY

func get_replay_path():
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-") # Replace : with - for valid filename
	return "user://replays/replay_" + timestamp + ".tres"

func _on_match_finished_with_defeat():
	if mode == Mode.RECORD:
		var match = find_parent("Match")
		if match:
			replay.final_time = float(match.tick) / match.TICK_RATE
		replay.final_state = "defeat"
		save_to_file()
	mode = Mode.OFF


func _on_match_finished_with_victory():
	if mode == Mode.RECORD:
		var match = find_parent("Match")
		if match:
			replay.final_time = float(match.tick) / match.TICK_RATE
		replay.final_state = "victory"
		save_to_file()
	mode = Mode.OFF


func _on_match_aborted():
	if mode == Mode.RECORD:
		var match = find_parent("Match")
		if match:
			replay.final_time = float(match.tick) / match.TICK_RATE
		replay.final_state = "aborted"
		save_to_file()
	mode = Mode.OFF


func _serialize_players(players: Array[Resource]) -> Array:
	# Convert player Resource objects to dictionaries for serialization
	var serialized: Array = []
	for player_settings in players:
		var player_dict = {
			"color": player_settings.color,
			"controller": player_settings.controller,
			"team": player_settings.team,
			"spawn_index_offset": player_settings.spawn_index_offset,
		}
		serialized.append(player_dict)
	return serialized


func _restore_players(players_data: Array) -> Array[Resource]:
	# Convert player dictionaries back to PlayerSettings Resource objects
	var restored_players: Array[Resource] = []
	for index in range(players_data.size()):
		var player_data = players_data[index]
		var player_settings = PlayerSettings.new()
		var data_variant: Variant = player_data
		if data_variant is Dictionary:
			player_settings.color = data_variant.get("color") if data_variant.has("color") else Color.BLUE
			player_settings.controller = data_variant.get("controller") if data_variant.has("controller") else Constants.PlayerType.SIMPLE_CLAIRVOYANT_AI
			# Backward compatibility: old replays might not include team.
			# Use unique team per player index to preserve expected combat behavior.
			player_settings.team = data_variant.get("team") if data_variant.has("team") else index
			player_settings.spawn_index_offset = data_variant.get("spawn_index_offset") if data_variant.has("spawn_index_offset") else 0
		else:
			player_settings = player_data as PlayerSettings
			if player_settings != null and player_settings.team == null:
				player_settings.team = index
		restored_players.append(player_settings)
	return restored_players
