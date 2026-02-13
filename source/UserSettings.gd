extends Node


signal hotkeys_changed


var _hotkey_pack_scheme = "res://"
var _hotkey_pack_name = "grid"

func read_hotkeys(package: String, roles: Array) -> Array[Key]:
	var dict = _load_hotkey_data(package)
	var output: Array[Key] = []
	for r in roles:
		# Make it easy to just grab all child buttons
		if r == null:
			output.push_back(Key.KEY_NONE)
		else:
			var hotkey: String = dict[r]
			if typeof(hotkey) != TYPE_STRING or hotkey.length() != 1:
				print("invalid/missing hotkey for ", r)
				output.push_back(Key.KEY_NONE)
			else:
				output.push_back(OS.find_keycode_from_string(hotkey))
	return output

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	hotkeys_changed.emit()	
	
	
func _load_hotkey_data(purpose) -> Dictionary:
	var path = _resolve_hotkey_file(purpose)
	print("hotkey path ", path)
	if path == "":
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	var json_text = file.get_as_text()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error == OK:
		if typeof(json.data) == TYPE_DICTIONARY:
			return json.data
		print("malformed hotkey data - root was not a dictionary")
	print("failed to load hotkey data from ", path, error)
	return {}
	
func _resolve_hotkey_file(purpose) -> String:
	var base_path: String = ""
	if _hotkey_pack_scheme == "res://":
		base_path = _hotkey_pack_scheme.path_join("data").path_join("hotkeys")
	elif _hotkey_pack_scheme == "user://":
		base_path = _hotkey_pack_scheme.path_join("settings").path_join("hotkeys")
	else:
		log("invalid hotkey scheme: " + _hotkey_pack_scheme)
	return base_path.path_join(_hotkey_pack_name).path_join(purpose + ".json")
