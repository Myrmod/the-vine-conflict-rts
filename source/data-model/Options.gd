extends Resource

enum Screen { FULL = 0, WINDOW = 1 }

const _AUDIO_BUS_NAMES := [&"Music", &"SFX", &"Voice"]

@export var screen: Screen = Screen.FULL:
	set = _set_screen
@export var vsync_enabled: bool = true:
	set = _set_vsync_enabled
@export var window_borderless: bool = false:
	set = _set_window_borderless
@export var window_size: Vector2i = Vector2i(1920, 1080):
	set = _set_window_size
@export var mouse_restricted = false:
	set = _set_mouse_restricted
@export_range(0.0, 1.0, 0.01) var master_volume: float = 0.8:
	set = _set_master_volume
@export_range(0.0, 1.0, 0.01) var music_volume: float = 0.8:
	set = _set_music_volume
@export_range(0.0, 1.0, 0.01) var sfx_volume: float = 0.8:
	set = _set_sfx_volume
@export_range(0.0, 1.0, 0.01) var voice_volume: float = 0.8:
	set = _set_voice_volume
@export var edge_scroll_enabled: bool = true
@export var player_name: String = ""


func _init():
	_apply_stored_options()


func _set_screen(value):
	screen = value
	_apply_screen()
	_apply_windowed_preferences()


func _set_vsync_enabled(value):
	vsync_enabled = value
	_apply_vsync()


func _set_window_borderless(value):
	window_borderless = value
	_apply_windowed_preferences()


func _set_window_size(value):
	window_size = Vector2i(maxi(value.x, 640), maxi(value.y, 360))
	_apply_windowed_preferences()


func _set_mouse_restricted(value):
	mouse_restricted = value
	_apply_mouse_restricted()


func _set_master_volume(value):
	master_volume = clampf(value, 0.0, 1.0)
	_set_bus_linear_volume(&"Master", master_volume)


func _set_music_volume(value):
	music_volume = clampf(value, 0.0, 1.0)
	_set_bus_linear_volume(&"Music", music_volume)


func _set_sfx_volume(value):
	sfx_volume = clampf(value, 0.0, 1.0)
	_set_bus_linear_volume(&"SFX", sfx_volume)


func _set_voice_volume(value):
	voice_volume = clampf(value, 0.0, 1.0)
	_set_bus_linear_volume(&"Voice", voice_volume)


func _apply_stored_options():
	_ensure_audio_buses()
	_apply_screen()
	_apply_vsync()
	_apply_windowed_preferences()
	_apply_mouse_restricted()
	_set_bus_linear_volume(&"Master", master_volume)
	_set_bus_linear_volume(&"Music", music_volume)
	_set_bus_linear_volume(&"SFX", sfx_volume)
	_set_bus_linear_volume(&"Voice", voice_volume)


func _apply_screen():
	DisplayServer.window_set_mode(
		(
			DisplayServer.WINDOW_MODE_FULLSCREEN
			if screen == Screen.FULL
			else DisplayServer.WINDOW_MODE_WINDOWED
		)
	)


func _apply_vsync():
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)


func _apply_windowed_preferences():
	if screen != Screen.WINDOW:
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, window_borderless)
	DisplayServer.window_set_size(window_size)


func _apply_mouse_restricted():
	if mouse_restricted:
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _ensure_audio_buses():
	var master_index := AudioServer.get_bus_index(&"Master")
	if master_index < 0:
		return
	for bus_name in _AUDIO_BUS_NAMES:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus(AudioServer.get_bus_count())
		var new_index := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(new_index, bus_name)
		AudioServer.set_bus_send(new_index, &"Master")


func _set_bus_linear_volume(bus_name: StringName, linear_volume: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var volume := clampf(linear_volume, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, is_zero_approx(volume))
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(volume, 0.0001)))
