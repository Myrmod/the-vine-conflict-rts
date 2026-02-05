extends Node

enum Mode {OFF, RECORD, PLAY}

@export var mode: Mode = Mode.OFF
@export var replay := {
	"meta": {},
	"commands": []
}

func _ready():
	MatchSignals.connect("match_finished_with_defeat", _on_match_ended)
	MatchSignals.connect("match_finished_with_victory", _on_match_ended)
	MatchSignals.connect("match_aborted", _on_match_ended)

func start_recording(map_name: String, _seed: int, settings):
	mode = Mode.RECORD
	replay.meta = {
		"map": map_name,
		"seed": _seed,
		"settings": settings,
	}
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
	var path = get_replay_path()
	
	# Create directory if it doesn't exist
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var error = DirAccess.make_dir_recursive_absolute(dir_path)
		if error != OK:
			printerr("Failed to create directory: ", dir_path)
			return

	# Save the file
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Failed to open file for writing: ", path)
		return
	file.store_string(JSON.stringify(replay))
	file.close()

func load_from_file(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	replay = JSON.parse_string(file.get_as_text())
	file.close()

func start_replay():
	mode = Mode.PLAY

func get_replay_path():
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-") # Replace : with - for valid filename
	return "user://replays/replay_" + timestamp + ".save"

func _on_match_ended():
	stop_recording()
	save_to_file()
