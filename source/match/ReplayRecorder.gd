extends Node

enum Mode {OFF, RECORD, PLAY}

@export var mode: Mode = Mode.OFF
@export var replay := ReplayResource.new()

func _ready():
	MatchSignals.connect("match_finished_with_defeat", _on_match_ended)
	MatchSignals.connect("match_finished_with_victory", _on_match_ended)
	MatchSignals.connect("match_aborted", _on_match_ended)

func start_recording(match: Match):
	mode = Mode.RECORD
	replay.tick_rate = match.TICK_RATE
	replay.settings = match.settings
	replay.map = match.map.scene_file_path
	#replay.seed = match.seed
	replay.commands.clear()

## Example command
## {
##     "tick": 120,
##     "player": 0,
##     "type": "move",
##     "units": [1, 3, 7],
##     "target": Vector3(10, 0, 25)
## }
func record_command(cmd: Dictionary):
	if mode != Mode.RECORD:
		return
	replay.commands.append(cmd.duplicate())

func stop_recording():
	mode = Mode.OFF

## replay_2026-02-05T19-00-22.save
func save_to_file():
	if not Utils._detect_potential_recursion(replay, {}, "replay"):
		push_error("Replay validation failed — not saving")
		return
	var path = get_replay_path()
	
	# Create directory if it doesn't exist
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var error = DirAccess.make_dir_recursive_absolute(dir_path)
		if error != OK:
			printerr("Failed to create directory: ", dir_path)
			return

	# Save the file
	var err = ResourceSaver.save(replay, path)
	if err != OK:
		printerr("Replay save failed:", err)

func load_from_file(path: String) -> ReplayResource:
	replay = ResourceLoader.load(path)

	return replay

func start_replay():
	mode = Mode.PLAY

func get_replay_path():
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-") # Replace : with - for valid filename
	return "user://replays/replay_" + timestamp + ".tres"

func _on_match_ended():
	# don't save if a replay was played
	if mode == Mode.RECORD:
		save_to_file()
	stop_recording()
