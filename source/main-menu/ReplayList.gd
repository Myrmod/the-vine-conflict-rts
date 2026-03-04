extends VBoxContainer

const ReplayItemScene = preload("res://source/main-menu/ReplayItem.tscn")

var _is_starting_replay := false

func _ready():
	print('ReplayList Scene')
	# Create directory if it doesn't exist
	var dir_path = "user://replays/"
	if not DirAccess.dir_exists_absolute(dir_path):
		var error = DirAccess.make_dir_recursive_absolute(dir_path)
		if error != OK:
			printerr("Failed to create directory: ", dir_path)
			return
			
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			# Skip directories and unwanted files
			if not dir.current_is_dir() and not file_name.begins_with(".") and not file_name.ends_with(".import"):
				var full_path = dir_path + file_name
				var item = ReplayItemScene.instantiate()
				self.add_child(item)
				item.setup(full_path)
				item.watch_requested.connect(_on_watch_replay)
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		print("Error: Could not open directory.")

func _on_watch_replay(path: String):
	if _is_starting_replay:
		return
	_is_starting_replay = true

	var replay = ReplayRecorder.load_from_file(path)
	if replay == null:
		push_error("Could not load replay from path: %s" % path)
		_is_starting_replay = false
		return

	# adding commands to the CommandBus
	CommandBus.load_from_replay_array(replay.commands)

	var play_scene = preload("res://source/main-menu/Play.tscn")
	var play = play_scene.instantiate()

	play.replay_resource = replay
	# change_scene_to_node() will attach the new scene and replace the current one.
	var tree = get_tree()
	if tree == null:
		push_error("ReplayList: scene tree is unavailable while starting replay")
		_is_starting_replay = false
		return
	tree.change_scene_to_node(play)
