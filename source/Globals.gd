extends Node

const Options = preload("res://source/data-model/Options.gd")
const TERRAIN_LIBRARY = preload("uid://wobncmqv0prv")

var options = (
	load(Constants.get_options_file_path())
	if ResourceLoader.exists(Constants.get_options_file_path())
	else Options.new()
)
var terrain_library: TerrainLibrary
var terrain_types: Array[TerrainType]
var god_mode = false
var cache = {}


func _ready():
	terrain_library = TERRAIN_LIBRARY as TerrainLibrary

	if terrain_library == null:
		push_error("Failed to load TerrainLibrary")
		return

	terrain_types = terrain_library.terrain_types


func _unhandled_input(event):
	if event.is_action_pressed("toggle_god_mode"):
		_toggle_god_mode()


func _toggle_god_mode():
	if not FeatureFlags.god_mode:
		return
	god_mode = not god_mode
	if god_mode:
		Signals.god_mode_enabled.emit()
	else:
		Signals.god_mode_disabled.emit()
