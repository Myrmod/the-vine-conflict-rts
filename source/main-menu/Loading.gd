extends Control

var match_settings = null
var map_path = null
var replay_resource = null

@onready var _label = find_child("Label")
@onready var _progress_bar = find_child("ProgressBar")


func _ready():
	_progress_bar.value = 0.0

	_label.text = tr("LOADING_STEP_PRELOADING")
	await get_tree().physics_frame
	_preload_scenes()
	_progress_bar.value = 0.2

	_label.text = tr("LOADING_STEP_LOADING_MAP")
	await get_tree().physics_frame
	var map = load(map_path).instantiate()
	_progress_bar.value = 0.4

	_label.text = tr("LOADING_STEP_LOADING_MATCH")
	await get_tree().physics_frame
	var match_prototype = load("res://source/match/Match.tscn")
	_progress_bar.value = 0.7

	_label.text = tr("LOADING_STEP_INSTANTIATING_MATCH")
	await get_tree().physics_frame
	var a_match = match_prototype.instantiate()
	# Restore settings from replay if needed (convert serialized players back to Resource objects)
	if replay_resource != null and not replay_resource.players_data.is_empty():
		match_settings.players = ReplayRecorder._restore_players(replay_resource.players_data)
	a_match.settings = match_settings
	a_match.map = map
	a_match.is_replay_mode = !!replay_resource

	# ── DETERMINISTIC SEED ──────────────────────────────────────────
	# Generate a match seed (or restore from replay) so all RNG (shuffle, randf, etc.)
	# reproduces identically. This is essential for replay determinism.
	if replay_resource != null and replay_resource.get("match_seed") != null:
		Match.rng.seed = replay_resource.match_seed
	else:
		Match.rng.seed = randi()

	# ── COMMAND BUS LIFECYCLE ───────────────────────────────────────
	# Clear before loading: ensures no stale commands from previous match
	CommandBus.clear()
	EntityRegistry.reset()
	PlayerManager.reset()

	# Load replay commands BEFORE adding Match to the tree, so they're available
	# when Match._ready() starts the tick timer
	if replay_resource != null:
		CommandBus.load_from_replay_array(replay_resource.commands)

	_progress_bar.value = 0.9

	_label.text = tr("LOADING_STEP_STARTING_MATCH")
	await get_tree().physics_frame
	get_parent().add_child(a_match)
	get_tree().current_scene = a_match
	queue_free()


func _preload_scenes():
	var scene_paths = []
	scene_paths += UnitConstants.PROJECTILES.values()
	scene_paths += UnitConstants.STRUCTURE_BLUEPRINTS.keys()
	for scene_path in scene_paths:
		Globals.cache[scene_path] = load(scene_path)
