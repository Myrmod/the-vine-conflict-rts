extends Control

@onready var _logos = find_child("Logos")


func _ready():
	if _is_dedicated_server():
		get_tree().change_scene_to_file.call_deferred(
			"res://source/multiplayer/DedicatedServer.tscn"
		)
		return
	_logos.tree_exited.connect(
		get_tree().change_scene_to_file.bind("res://source/main-menu/Main.tscn")
	)


static func _is_dedicated_server() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	for arg in OS.get_cmdline_user_args():
		if arg == "--server":
			return true
	return false
