extends GridContainer

class_name Hotkeys


var container = ""
var hotkey_buttons = []

# Declare the container name
# This is used during hotkey lookups as the container path
# It must be called before the first invocation of _assign_grid_shortcuts or no hotkeys will be loaded
# You should do this in _ready before calling super._ready()
func declare_hotkey_container(c: String) -> void:
	container = c
	
# Declare a button and a corresponding action
# You should do this in _ready before calling super._ready()
func declare_hotkey_button(action: String, button: Button) -> void:
	hotkey_buttons.append([button, action])

func _ready():
	_assign_grid_shortcuts()
	UserSettings.hotkeys_changed.connect(_assign_grid_shortcuts)

func _assign_grid_shortcuts():	
	for tuple in hotkey_buttons:
		var button: Button = tuple[0]
		var action: String = tuple[1]
		
		var keycode = UserSettings.get_hotkey(container, action)
		if keycode == Key.KEY_NONE:
			push_warning("no hotkey assignment for ", container, action)
		var ev := InputEventKey.new()
		var sc := Shortcut.new()
		ev.keycode = keycode
		sc.events = [ev]
		button.shortcut = sc
