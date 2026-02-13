extends GridContainer

class_name Hotkeys


var hotkey_buttons = {}

func register_button(name: String, button: Button) -> void:
	hotkey_buttons[name] = button

func _ready():
	_assign_grid_shortcuts()
	UserSettings.hotkeys_changed.connect(_assign_grid_shortcuts)

func _assign_grid_shortcuts():
	var button_roles: Array = hotkey_buttons.keys()
	
	var hotkeys = UserSettings.read_hotkeys("VehicleFactory", button_roles)
	
	for i in range(0, button_roles.size()):
		if hotkeys[i] == null:
			print("no hotkey assignment for " + button_roles[i])
			continue
		var button: Button = hotkey_buttons[button_roles[i]]
		
		var keycode = hotkeys[i]
		
		var ev := InputEventKey.new()
		var sc := Shortcut.new()
		ev.keycode = keycode
		sc.events = [ev]
		button.shortcut = sc
