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

const _COMMON_RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

var _all_buttons: Dictionary = {}
var _awaiting_slot: String = ""
var _awaiting_button: Button = null
var _preset_names: Array[String] = []
var _resolution_values: Array[Vector2i] = []
var _conflict_existing_slot: String = ""
var _conflict_new_keycode: int = -1

@onready var _master_volume: HSlider = find_child("MasterVolume")
@onready var _master_volume_value: Label = find_child("MasterVolumeValue")
@onready var _music_volume: HSlider = find_child("MusicVolume")
@onready var _music_volume_value: Label = find_child("MusicVolumeValue")
@onready var _sfx_volume: HSlider = find_child("SfxVolume")
@onready var _sfx_volume_value: Label = find_child("SfxVolumeValue")
@onready var _voice_volume: HSlider = find_child("VoiceVolume")
@onready var _voice_volume_value: Label = find_child("VoiceVolumeValue")
@onready var _tab_container: TabContainer = find_child("TabContainer")
@onready var _screen = find_child("Screen")
@onready var _vsync_enabled: CheckBox = find_child("VsyncEnabled")
@onready var _resolution_select: OptionButton = find_child("ResolutionSelect")
@onready var _borderless_window: CheckBox = find_child("BorderlessWindow")
@onready var _mouse_movement_restricted = find_child("MouseMovementRestricted")
@onready var _edge_scroll_enabled: CheckBox = find_child("EdgeScrollEnabled")
@onready var _preset_select: OptionButton = find_child("PresetSelect")
@onready var _reset_hotkeys_button: Button = find_child("ResetHotkeysButton")
@onready var _hotkey_conflict_label: Label = find_child("HotkeyConflictLabel")
@onready var _player_name_input: LineEdit = find_child("PlayerNameInput")
@onready var _key_conflict_dialog: ConfirmationDialog = find_child("KeyConflictDialog")


func _ready():
	_set_tab_titles()
	_master_volume.value = Globals.options.master_volume * 100.0
	_music_volume.value = Globals.options.music_volume * 100.0
	_sfx_volume.value = Globals.options.sfx_volume * 100.0
	_voice_volume.value = Globals.options.voice_volume * 100.0
	_refresh_master_volume_label()
	_refresh_music_volume_label()
	_refresh_sfx_volume_label()
	_refresh_voice_volume_label()
	_mouse_movement_restricted.button_pressed = (Globals.options.mouse_restricted)
	_edge_scroll_enabled.button_pressed = Globals.options.edge_scroll_enabled
	_screen.selected = Globals.options.screen
	_vsync_enabled.button_pressed = Globals.options.vsync_enabled
	_populate_resolution_options()
	_sync_video_controls()
	_player_name_input.text = Globals.options.player_name
	_populate_preset_dropdown()
	_setup_all_hotkey_buttons()
	_setup_conflict_dialog()
	_refresh_hotkey_labels()
	_sync_preset_selection()
	if _hotkey_conflict_label != null:
		_hotkey_conflict_label.text = ""
	if _reset_hotkeys_button != null:
		_reset_hotkeys_button.disabled = false


func _setup_conflict_dialog() -> void:
	if _key_conflict_dialog == null:
		return
	if not _key_conflict_dialog.confirmed.is_connected(_on_conflict_dialog_confirmed):
		_key_conflict_dialog.confirmed.connect(_on_conflict_dialog_confirmed)
	if not _key_conflict_dialog.canceled.is_connected(_on_conflict_dialog_canceled):
		_key_conflict_dialog.canceled.connect(_on_conflict_dialog_canceled)
	_key_conflict_dialog.get_ok_button().text = "Swap"


func _set_tab_titles() -> void:
	if _tab_container == null:
		return
	var titles := ["Video", "Audio", "Hotkeys", "Game"]
	for index in range(min(_tab_container.get_tab_count(), titles.size())):
		_tab_container.set_tab_title(index, titles[index])


func _populate_preset_dropdown() -> void:
	var presets = HotkeySettings.get_presets()
	_preset_names.clear()
	_preset_select.clear()
	_preset_select.add_item("Custom", 0)
	var preset_names: Array = presets.keys()
	preset_names.sort()
	var idx := 1
	for preset_name_variant in preset_names:
		var preset_name := String(preset_name_variant)
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
	if _awaiting_button != null:
		_awaiting_button.text = "Press key"


func _on_hotkey_slot_pressed(slot: String, btn: Button) -> void:
	if _awaiting_button != null and _awaiting_button != btn:
		_refresh_hotkey_labels()
	_awaiting_slot = slot
	_awaiting_button = btn
	btn.text = "Press key"


func _unhandled_key_input(event: InputEvent) -> void:
	if _awaiting_slot == "":
		return
	if not event is InputEventKey:
		return
	if not event.pressed:
		return
	var key_event: InputEventKey = event
	if key_event.physical_keycode == KEY_ESCAPE:
		_clear_pending_hotkey_capture()
		_refresh_hotkey_labels()
		if _hotkey_conflict_label != null:
			_hotkey_conflict_label.text = ""
		get_viewport().set_input_as_handled()
		return
	if key_event.physical_keycode in [KEY_BACKSPACE, KEY_DELETE]:
		_apply_binding_and_save(_awaiting_slot, -1)
		_clear_pending_hotkey_capture()
		_refresh_hotkey_labels()
		_sync_preset_selection()
		if _hotkey_conflict_label != null:
			_hotkey_conflict_label.text = "Binding cleared."
		get_viewport().set_input_as_handled()
		return
	var existing_slot := _find_slot_by_key(key_event.physical_keycode)
	if existing_slot != "" and existing_slot != _awaiting_slot:
		_open_conflict_dialog(existing_slot, key_event.physical_keycode)
		get_viewport().set_input_as_handled()
		return
	elif _hotkey_conflict_label != null:
		_hotkey_conflict_label.text = ""
	_apply_binding_and_save(_awaiting_slot, key_event.physical_keycode)
	_clear_pending_hotkey_capture()
	_refresh_hotkey_labels()
	_sync_preset_selection()
	get_viewport().set_input_as_handled()


func _on_preset_selected(index: int) -> void:
	if index == 0:
		return  # "Custom" — do nothing
	var preset_name = _preset_names[index - 1]
	Globals.hotkey_settings.apply_preset(preset_name)
	Globals.hotkey_settings.save()
	_clear_pending_hotkey_capture()
	if _hotkey_conflict_label != null:
		_hotkey_conflict_label.text = ""
	_refresh_hotkey_labels()
	_sync_preset_selection()


func _open_conflict_dialog(existing_slot: String, new_keycode: int) -> void:
	_conflict_existing_slot = existing_slot
	_conflict_new_keycode = new_keycode
	if _key_conflict_dialog != null:
		var key_label := _format_keycode_for_ui(new_keycode)
		_key_conflict_dialog.dialog_text = (
			"%s is already bound to %s. Swap bindings?"
			% [key_label, _get_slot_display_name(existing_slot)]
		)
		_key_conflict_dialog.popup_centered()
	if _hotkey_conflict_label != null:
		_hotkey_conflict_label.text = ""


func _on_conflict_dialog_confirmed() -> void:
	if _awaiting_slot == "" or _conflict_existing_slot == "" or _conflict_new_keycode < 0:
		return
	var previous_key := _get_key_for_slot(_awaiting_slot)
	_apply_binding_and_save(_conflict_existing_slot, previous_key)
	_apply_binding_and_save(_awaiting_slot, _conflict_new_keycode)
	_clear_conflict_pending()
	_clear_pending_hotkey_capture()
	_refresh_hotkey_labels()
	_sync_preset_selection()
	if _hotkey_conflict_label != null:
		_hotkey_conflict_label.text = "Bindings swapped to avoid duplicates."


func _on_conflict_dialog_canceled() -> void:
	_clear_conflict_pending()
	if _hotkey_conflict_label != null:
		_hotkey_conflict_label.text = "Rebind canceled. Press a different key."


func _clear_conflict_pending() -> void:
	_conflict_existing_slot = ""
	_conflict_new_keycode = -1


func _apply_binding_and_save(slot_name: String, keycode: int) -> void:
	Globals.hotkey_settings.set_binding(slot_name, keycode)
	Globals.hotkey_settings.save()


func _format_keycode_for_ui(keycode: int) -> String:
	var logical := DisplayServer.keyboard_get_keycode_from_physical(keycode)
	if logical != KEY_NONE:
		return OS.get_keycode_string(logical)
	return OS.get_keycode_string(keycode)


func _clear_pending_hotkey_capture() -> void:
	_awaiting_slot = ""
	_awaiting_button = null


func _sync_preset_selection() -> void:
	var presets = HotkeySettings.get_presets()
	_preset_select.selected = 0
	for index in range(_preset_names.size()):
		var preset_name := _preset_names[index]
		if Globals.hotkey_settings.matches_data(presets.get(preset_name, {})):
			_preset_select.selected = index + 1
			return


func _save_options() -> void:
	ResourceSaver.save(Globals.options, Constants.get_options_file_path())


func _refresh_master_volume_label() -> void:
	_master_volume_value.text = "%d%%" % int(round(_master_volume.value))


func _refresh_music_volume_label() -> void:
	_music_volume_value.text = "%d%%" % int(round(_music_volume.value))


func _refresh_sfx_volume_label() -> void:
	_sfx_volume_value.text = "%d%%" % int(round(_sfx_volume.value))


func _refresh_voice_volume_label() -> void:
	_voice_volume_value.text = "%d%%" % int(round(_voice_volume.value))


func _on_master_volume_value_changed(value: float) -> void:
	Globals.options.master_volume = value / 100.0
	_refresh_master_volume_label()
	_save_options()


func _on_music_volume_value_changed(value: float) -> void:
	Globals.options.music_volume = value / 100.0
	_refresh_music_volume_label()
	_save_options()


func _on_sfx_volume_value_changed(value: float) -> void:
	Globals.options.sfx_volume = value / 100.0
	_refresh_sfx_volume_label()
	_save_options()


func _on_voice_volume_value_changed(value: float) -> void:
	Globals.options.voice_volume = value / 100.0
	_refresh_voice_volume_label()
	_save_options()


func _on_mouse_movement_restricted_toggled(toggled_on: bool) -> void:
	Globals.options.mouse_restricted = toggled_on
	_save_options()


func _on_screen_item_selected(index: int) -> void:
	Globals.options.screen = {
		0: Globals.options.Screen.FULL,
		1: Globals.options.Screen.WINDOW,
	}[index]
	_sync_video_controls()
	_save_options()


func _on_vsync_enabled_toggled(toggled_on: bool) -> void:
	Globals.options.vsync_enabled = toggled_on
	_save_options()


func _populate_resolution_options() -> void:
	if _resolution_select == null:
		return
	_resolution_select.clear()
	_resolution_values.clear()
	var seen := {}
	var current_size := DisplayServer.window_get_size()
	var candidates: Array[Vector2i] = []
	for res in _COMMON_RESOLUTIONS:
		candidates.append(res)
	candidates.append(current_size)
	candidates.append(Globals.options.window_size)
	for res in candidates:
		if res.x < 640 or res.y < 360:
			continue
		var key := "%dx%d" % [res.x, res.y]
		if seen.has(key):
			continue
		seen[key] = true
		_resolution_values.append(res)
	_resolution_values.sort_custom(func(a, b): return a.x * a.y < b.x * b.y)
	for i in range(_resolution_values.size()):
		var res := _resolution_values[i]
		_resolution_select.add_item("%d x %d" % [res.x, res.y], i)
	var selected := 0
	for i in range(_resolution_values.size()):
		if _resolution_values[i] == Globals.options.window_size:
			selected = i
			break
	_resolution_select.selected = selected


func _sync_video_controls() -> void:
	var window_mode_enabled: bool = (Globals.options.screen == Globals.options.Screen.WINDOW)
	if _resolution_select != null:
		_resolution_select.disabled = not window_mode_enabled
	if _borderless_window != null:
		_borderless_window.disabled = not window_mode_enabled
		_borderless_window.button_pressed = Globals.options.window_borderless


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= _resolution_values.size():
		return
	Globals.options.window_size = _resolution_values[index]
	_save_options()


func _on_borderless_window_toggled(toggled_on: bool) -> void:
	Globals.options.window_borderless = toggled_on
	_save_options()


func _on_edge_scroll_enabled_toggled(toggled_on: bool) -> void:
	Globals.options.edge_scroll_enabled = toggled_on
	_save_options()


func _on_player_name_changed(new_text: String) -> void:
	Globals.options.player_name = new_text
	_save_options()


func _on_reset_hotkeys_button_pressed() -> void:
	Globals.hotkey_settings.reset_to_defaults()
	Globals.hotkey_settings.save()
	_clear_pending_hotkey_capture()
	if _hotkey_conflict_label != null:
		_hotkey_conflict_label.text = "Hotkeys reset to default layout."
	_refresh_hotkey_labels()
	_sync_preset_selection()


func _find_slot_by_key(keycode: int) -> String:
	for slot_name in _all_buttons:
		if _get_key_for_slot(slot_name) == keycode:
			return slot_name
	return ""


func _get_key_for_slot(slot_name: String) -> int:
	var hs = Globals.hotkey_settings
	if hs.bindings.has(slot_name):
		return int(hs.bindings[slot_name])
	if hs.tab_bindings.has(slot_name):
		return int(hs.tab_bindings[slot_name])
	if hs.unit_command_bindings.has(slot_name):
		return int(hs.unit_command_bindings[slot_name])
	if hs.structure_action_bindings.has(slot_name):
		return int(hs.structure_action_bindings[slot_name])
	return -1


func _get_slot_display_name(slot_name: String) -> String:
	if slot_name.begins_with("tab_"):
		return slot_name.capitalize().replace("_", " ")
	return slot_name.capitalize().replace("_", " ")


func _on_back_button_pressed():
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")
