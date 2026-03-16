extends Control

## Maps HotkeySettings slot names to scene button node names.
const _SLOT_TO_NODE := {
	"tab_1": "Tab1Button",
	"tab_2": "Tab2Button",
	"tab_3": "Tab3Button",
	"tab_4": "Tab4Button",
	"tab_5": "Tab5Button",
	"tab_6": "Tab6Button",
	"attack_move": "AttackMoveButton",
	"stop": "StopButton",
	"hold_position": "HoldPositionButton",
	"move": "MoveButton",
	"patrol": "PatrolButton",
	"reverse_move": "ReverseMoveButton",
	"select_all_army": "SelectAllArmyButton",
	"repair": "RepairButton",
	"sell": "SellButton",
	"disable": "DisableButton",
}

var _all_buttons: Dictionary = {}
var _awaiting_slot: String = ""
var _preset_names: Array[String] = []

@onready var _screen = find_child("Screen")
@onready var _mouse_movement_restricted = find_child("MouseMovementRestricted")
@onready var _preset_select: OptionButton = find_child("PresetSelect")
@onready var _player_name_input: LineEdit = find_child("PlayerNameInput")


func _ready():
	_mouse_movement_restricted.button_pressed = (Globals.options.mouse_restricted)
	_screen.selected = Globals.options.screen
	_player_name_input.text = Globals.options.player_name
	_populate_preset_dropdown()
	_setup_all_hotkey_buttons()
	_refresh_hotkey_labels()


func _populate_preset_dropdown() -> void:
	var presets = HotkeySettings.get_presets()
	_preset_names.clear()
	_preset_select.clear()
	_preset_select.add_item("Custom", 0)
	var idx := 1
	for preset_name in presets:
		if preset_name == "Custom":
			continue
		_preset_names.append(preset_name)
		_preset_select.add_item(preset_name, idx)
		idx += 1


func _setup_all_hotkey_buttons() -> void:
	# Production grid slots (F1–F12)
	for i in range(12):
		var slot_name = HotkeySettings.SLOT_NAMES[i]
		var btn: Button = find_child("Slot%dButton" % (i + 1))
		btn.pressed.connect(_on_hotkey_slot_pressed.bind(slot_name, btn))
		_all_buttons[slot_name] = btn
	# Extra categories (tabs, commands, actions)
	for slot_name in _SLOT_TO_NODE:
		var btn: Button = find_child(_SLOT_TO_NODE[slot_name])
		btn.pressed.connect(_on_hotkey_slot_pressed.bind(slot_name, btn))
		_all_buttons[slot_name] = btn


func _refresh_hotkey_labels() -> void:
	var hs = Globals.hotkey_settings
	for slot_name in _all_buttons:
		_all_buttons[slot_name].text = hs.get_key_label(slot_name)


func _on_hotkey_slot_pressed(slot: String, btn: Button) -> void:
	_awaiting_slot = slot
	btn.text = "..."


func _unhandled_key_input(event: InputEvent) -> void:
	if _awaiting_slot == "":
		return
	if not event is InputEventKey:
		return
	if not event.pressed:
		return
	var key_event: InputEventKey = event
	Globals.hotkey_settings.set_binding(_awaiting_slot, key_event.physical_keycode)
	Globals.hotkey_settings.save()
	_awaiting_slot = ""
	_refresh_hotkey_labels()
	_preset_select.selected = 0  # Switch to "Custom"
	get_viewport().set_input_as_handled()


func _on_preset_selected(index: int) -> void:
	if index == 0:
		return  # "Custom" — do nothing
	var preset_name = _preset_names[index - 1]
	Globals.hotkey_settings.apply_preset(preset_name)
	Globals.hotkey_settings.save()
	_refresh_hotkey_labels()


func _on_mouse_movement_restricted_pressed():
	Globals.options.mouse_restricted = (_mouse_movement_restricted.button_pressed)
	ResourceSaver.save(Globals.options, Constants.get_options_file_path())


func _on_screen_item_selected(index):
	Globals.options.screen = {
		0: Globals.options.Screen.FULL,
		1: Globals.options.Screen.WINDOW,
	}[index]
	ResourceSaver.save(Globals.options, Constants.get_options_file_path())


func _on_player_name_changed(new_text: String) -> void:
	Globals.options.player_name = new_text
	ResourceSaver.save(Globals.options, Constants.get_options_file_path())


func _on_back_button_pressed():
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")
