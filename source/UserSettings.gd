extends Node

signal hotkeys_changed

var _hotkey_pack_scheme = "res://"
var _hotkey_pack_name = "grid"

var _hotkey_data: Dictionary

# What is a good nesting strategy here? container -> action? or do we need a third level
func get_hotkey(container: String, action: String) -> Key:
	var container_json = _hotkey_data[container]
	if typeof(container_json) != TYPE_DICTIONARY:
		push_error("malformed hotkey data at ", container)
		return Key.KEY_NONE
	var action_json = container_json[action]
	if typeof(action_json) != TYPE_STRING:
		push_error("malformed hotkey data at ", container, action)
		return Key.KEY_NONE
	return OS.find_keycode_from_string(action_json)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_load_hotkeys()
	hotkeys_changed.emit()
	
func _load_hotkeys() -> void:
	var path = _resolve_hotkey_file()
	if path == "":
		push_error("unable to find hotkey file for " + _hotkey_pack_scheme + " <> " + _hotkey_pack_name)
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("unable to open hotkey file: ", FileAccess.get_open_error())
		return
		
	var content = file.get_as_text()
	if file.get_error() != OK:
		push_error("failed to read hotkey file", file.get_error())
		return
	
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		push_error("failed to parse hotkey file: ", json.get_error_line(), json.get_error_message())
		return
	
	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("hotkey file is not dictionary")
		return
		
	_hotkey_data = json.data
	

func _resolve_hotkey_file() -> String:
	var base_path: String = ""
	if _hotkey_pack_scheme == "res://":
		base_path = _hotkey_pack_scheme.path_join("data").path_join("hotkeys")
	elif _hotkey_pack_scheme == "user://":
		base_path = _hotkey_pack_scheme.path_join("settings").path_join("hotkeys")
	else:
		push_error("invalid hotkey scheme: " + _hotkey_pack_scheme)
		return ""
	return base_path.path_join(_hotkey_pack_name + ".json")
