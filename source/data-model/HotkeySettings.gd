class_name HotkeySettings
## Manages hotkey bindings for all input categories:
##   - production_grid: F1–F12 production grid slots
##   - production_tabs: Tab-switching keys (Q W E R T Y)
##   - unit_commands: Attack-move, Stop, Hold, Move, Patrol
##   - structure_actions: Repair, Sell, Disable
## Hotkeys are saved to a JSON file. Presets provide common layouts.

const SAVE_PATH = "user://hotkeys.json"
const PRESETS_DIR = "user://hotkey_presets/"
const SLOT_NAMES = [
	"F1",
	"F2",
	"F3",
	"F4",
	"F5",
	"F6",
	"F7",
	"F8",
	"F9",
	"F10",
	"F11",
	"F12",
]

const TAB_NAMES = ["tab_1", "tab_2", "tab_3", "tab_4", "tab_5", "tab_6"]
const UNIT_COMMAND_NAMES = [
	"attack_move",
	"stop",
	"hold_position",
	"move",
	"patrol",
	"reverse_move",
	"select_all_army",
]
const STRUCTURE_ACTION_NAMES = ["repair", "sell", "disable"]

# Maps slot name → physical key (KEY_* constant as int)
var bindings: Dictionary = {}
var tab_bindings: Dictionary = {}
var unit_command_bindings: Dictionary = {}
var structure_action_bindings: Dictionary = {}


static func get_default_bindings() -> Dictionary:
	return {
		"F1": KEY_Q,
		"F2": KEY_W,
		"F3": KEY_E,
		"F4": KEY_R,
		"F5": KEY_A,
		"F6": KEY_S,
		"F7": KEY_D,
		"F8": KEY_F,
		"F9": KEY_Z,
		"F10": KEY_X,
		"F11": KEY_C,
		"F12": KEY_V,
	}


static func get_default_tab_bindings() -> Dictionary:
	return {
		"tab_1": KEY_Q,
		"tab_2": KEY_W,
		"tab_3": KEY_E,
		"tab_4": KEY_R,
		"tab_5": KEY_T,
		"tab_6": KEY_Y,
	}


static func get_default_unit_command_bindings() -> Dictionary:
	return {
		"attack_move": KEY_A,
		"stop": KEY_S,
		"hold_position": KEY_H,
		"move": KEY_M,
		"patrol": KEY_P,
		"reverse_move": KEY_B,
		"select_all_army": KEY_QUOTELEFT,
	}


static func get_default_structure_action_bindings() -> Dictionary:
	return {
		"repair": KEY_U,
		"sell": KEY_I,
		"disable": KEY_O,
	}


static func get_presets() -> Dictionary:
	_ensure_preset_dir()
	var result := {}
	var dir = DirAccess.open(PRESETS_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var preset_name = file_name.get_basename()
			var data = _load_preset_file(PRESETS_DIR + file_name)
			if data != null:
				result[preset_name] = data
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


static func _ensure_preset_dir() -> void:
	if not DirAccess.dir_exists_absolute(PRESETS_DIR):
		DirAccess.make_dir_recursive_absolute(PRESETS_DIR)

	_seed_default_preset(
		"FunctionKeys",
		{
			"F1": KEY_F1,
			"F2": KEY_F2,
			"F3": KEY_F3,
			"F4": KEY_F4,
			"F5": KEY_F5,
			"F6": KEY_F6,
			"F7": KEY_F7,
			"F8": KEY_F8,
			"F9": KEY_F9,
			"F10": KEY_F10,
			"F11": KEY_F11,
			"F12": KEY_F12,
		},
	)


static func _seed_default_preset(name: String, grid: Dictionary) -> void:
	var path = PRESETS_DIR + name + ".json"
	if FileAccess.file_exists(path):
		return
	var data := {
		"production_grid": grid,
		"production_tabs": get_default_tab_bindings(),
		"unit_commands": get_default_unit_command_bindings(),
		"structure_actions": get_default_structure_action_bindings(),
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


static func _load_preset_file(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return null
	var data = json.data
	if not data is Dictionary:
		return null
	return data


static func save_preset(preset_name: String, data: Dictionary) -> void:
	_ensure_preset_dir()
	var path = PRESETS_DIR + preset_name + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


func _init():
	bindings = get_default_bindings()
	tab_bindings = get_default_tab_bindings()
	unit_command_bindings = get_default_unit_command_bindings()
	structure_action_bindings = get_default_structure_action_bindings()


func save() -> void:
	var data := _build_data_dict()
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	save_preset("Custom", data)


func _build_data_dict() -> Dictionary:
	var data := {
		"production_grid": {},
		"production_tabs": {},
		"unit_commands": {},
		"structure_actions": {},
	}
	for slot in bindings:
		data["production_grid"][slot] = bindings[slot]
	for slot in tab_bindings:
		data["production_tabs"][slot] = tab_bindings[slot]
	for slot in unit_command_bindings:
		data["unit_commands"][slot] = unit_command_bindings[slot]
	for slot in structure_action_bindings:
		data["structure_actions"][slot] = structure_action_bindings[slot]
	return data


func load_from_file() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("HotkeySettings: failed to parse %s" % SAVE_PATH)
		return
	var data = json.data
	if not data is Dictionary:
		return
	# Support both old flat format and new categorized format
	if data.has("production_grid") and data["production_grid"] is Dictionary:
		for slot in SLOT_NAMES:
			if data["production_grid"].has(slot):
				bindings[slot] = int(data["production_grid"][slot])
	else:
		# Legacy flat format (just production grid keys)
		for slot in SLOT_NAMES:
			if data.has(slot):
				bindings[slot] = int(data[slot])
	if data.has("production_tabs") and data["production_tabs"] is Dictionary:
		for slot in TAB_NAMES:
			if data["production_tabs"].has(slot):
				tab_bindings[slot] = int(data["production_tabs"][slot])
	if data.has("unit_commands") and data["unit_commands"] is Dictionary:
		for slot in UNIT_COMMAND_NAMES:
			if data["unit_commands"].has(slot):
				unit_command_bindings[slot] = int(data["unit_commands"][slot])
	if data.has("structure_actions") and data["structure_actions"] is Dictionary:
		for slot in STRUCTURE_ACTION_NAMES:
			if data["structure_actions"].has(slot):
				structure_action_bindings[slot] = int(data["structure_actions"][slot])


func apply_preset(preset_name: String) -> void:
	var presets = get_presets()
	if not presets.has(preset_name):
		return
	var p: Dictionary = presets[preset_name]
	_apply_data_dict(p)


func _apply_data_dict(p: Dictionary) -> void:
	if p.has("production_grid") and p["production_grid"] is Dictionary:
		for slot in SLOT_NAMES:
			if p["production_grid"].has(slot):
				bindings[slot] = int(p["production_grid"][slot])
	if p.has("production_tabs") and p["production_tabs"] is Dictionary:
		for slot in TAB_NAMES:
			if p["production_tabs"].has(slot):
				tab_bindings[slot] = int(p["production_tabs"][slot])
	if p.has("unit_commands") and p["unit_commands"] is Dictionary:
		for slot in UNIT_COMMAND_NAMES:
			if p["unit_commands"].has(slot):
				unit_command_bindings[slot] = int(p["unit_commands"][slot])
	if p.has("structure_actions") and p["structure_actions"] is Dictionary:
		for slot in STRUCTURE_ACTION_NAMES:
			if p["structure_actions"].has(slot):
				structure_action_bindings[slot] = int(p["structure_actions"][slot])


func get_key_label(slot: String) -> String:
	var phys := -1
	if bindings.has(slot):
		phys = bindings[slot]
	elif tab_bindings.has(slot):
		phys = tab_bindings[slot]
	elif unit_command_bindings.has(slot):
		phys = unit_command_bindings[slot]
	elif structure_action_bindings.has(slot):
		phys = structure_action_bindings[slot]
	if phys < 0:
		return ""
	var logical = DisplayServer.keyboard_get_keycode_from_physical(phys)
	if logical != KEY_NONE:
		return OS.get_keycode_string(logical)
	return OS.get_keycode_string(phys)


func set_binding(slot: String, keycode: int) -> void:
	if bindings.has(slot):
		bindings[slot] = keycode
	elif tab_bindings.has(slot):
		tab_bindings[slot] = keycode
	elif unit_command_bindings.has(slot):
		unit_command_bindings[slot] = keycode
	elif structure_action_bindings.has(slot):
		structure_action_bindings[slot] = keycode


## Get binding for a specific category and action name
func get_binding(category: String, action_name: String) -> int:
	match category:
		"production_grid":
			return bindings.get(action_name, -1)
		"production_tabs":
			return tab_bindings.get(action_name, -1)
		"unit_commands":
			return unit_command_bindings.get(action_name, -1)
		"structure_actions":
			return structure_action_bindings.get(action_name, -1)
	return -1
