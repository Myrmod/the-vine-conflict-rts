extends Node3D

class_name Match

const Structure = preload("res://source/match/units/Structure.gd")
const Human = preload("res://source/match/players/human/Human.gd")

const CommandCenter = preload("res://source/match/units/CommandCenter.tscn")
const Drone = preload("res://source/match/units/Drone.tscn")
const Worker = preload("res://source/match/units/Worker.tscn")

@export var settings: Resource = null

var map:
	set = _set_map,
	get = _get_map
var visible_player = null:
	set = _set_visible_player
var visible_players = null:
	set = _ignore,
	get = _get_visible_players

var is_replay_mode = false

@onready var navigation = $Navigation
@onready var fog_of_war = $FogOfWar

@onready var _camera = $IsometricCamera3D
@onready var _players = $Players
@onready var _terrain = $Terrain

# required for replays
static var tick := 0

const TICK_RATE := 10 # RTS logic ticks per second

func _enter_tree():
	assert(settings != null, "match cannot start without settings, see examples in tests/manual/")
	assert(map != null, "match cannot start without map, see examples in tests/manual/")


func _ready():
	if is_replay_mode:
		ReplayRecorder.start_replay()

	MatchSignals.setup_and_spawn_unit.connect(_setup_and_spawn_unit)
	_setup_subsystems_dependent_on_map()
	_setup_players()
	_setup_player_units()
	visible_player = get_tree().get_nodes_in_group("players")[settings.visible_player]
	_move_camera_to_initial_position()
	
	# Clear command bus for new match
	CommandBus.clear()
	
	# clear ticks
	tick = 0
	
	# required for replays
	var timer := Timer.new()
	timer.wait_time = 1.0 / TICK_RATE
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)
	
	if settings.visibility == settings.Visibility.FULL:
		fog_of_war.reveal()
	MatchSignals.match_started.emit()

	if !is_replay_mode:
		ReplayRecorder.start_recording(self )

# Called every frame by the main game loop timer. This is where all game state updates happen.
# The tick counter drives deterministic execution: commands reference specific ticks, and we execute
# them exactly when those ticks arrive. This is how replays work - same ticks, same commands = identical game.
# For a 10 ticks/second rate, each tick is ~100ms of game time.
func _on_tick():
	tick += 1
	print('tick:', tick)
	_process_commands_for_tick()

# Retrieves all commands queued for the current tick from CommandBus and executes them sequentially.
# CommandBus handles two modes: live gameplay (retrieving from queue) and replay playback (extracting from loaded commands).
# By executing all commands for a tick before moving to the next tick, we ensure synchronized, deterministic execution:
# - Human player inputs (queued via UnitActionsController) get executed in tick order
# - AI decisions (queued via AutoAttackingBattlegroup) get executed identically during replay
# - No race conditions or frame-timing issues - everything is tick-based
func _process_commands_for_tick():
	var commands_for_tick = CommandBus.get_commands_for_tick(tick)
	if commands_for_tick.is_empty():
		return

	for cmd in commands_for_tick:
		_execute_command(cmd)

# This is the SINGLE POINT OF AUTHORITY for all game state changes in a match.
# Every action a player takes or an AI makes becomes a command that flows through here:
# Human input -> CommandBus.push_command() -> ReplayRecorder.record() -> stored in queue
# AI decision -> CommandBus.push_command() -> ReplayRecorder.record() -> stored in queue
# During replay -> CommandBus.load_from_replay_array() -> extracted back into queue
# Then when the right tick arrives, this function executes the command exactly.
#
# Why here and not in action constructors? Separation of concerns:
# - Action constructors just store data (can't fail)
# - This function applies actions to real units (can fail - unit deleted, wrong type, etc.)
# - We validate and log errors here so we catch corruption early
#
# The command.type determines which game system processes it. Each handler assigns an Action
# to the unit(s), which then executes the action during the regular Unit._process() frame loop.
func _execute_command(cmd: Dictionary):
	print('_execute_command', cmd)
	match cmd.type:
		Enums.CommandType.MOVE:
			for entry in cmd.data.targets:
				var unit = EntityRegistry.get_unit(entry.unit)
				if unit == null or not is_instance_valid(unit):
					continue
				if unit.is_queued_for_deletion():
					continue
				unit.action = Actions.Moving.new(entry.pos)
		Enums.CommandType.MOVING_TO_UNIT:
			for entry in cmd.data.targets:
				var unit = EntityRegistry.get_unit(entry)
				var target_unit = EntityRegistry.get_unit(cmd.data.target_unit)
				if unit == null or not is_instance_valid(unit) or target_unit == null or not is_instance_valid(target_unit):
					continue
				if unit.is_queued_for_deletion() or target_unit.is_queued_for_deletion():
					continue
				unit.action = Actions.MovingToUnit.new(target_unit)
		Enums.CommandType.FOLLOWING:
			for entry in cmd.data.targets:
				var unit = EntityRegistry.get_unit(entry)
				var target_unit = EntityRegistry.get_unit(cmd.data.target_unit)
				if unit == null or not is_instance_valid(unit) or target_unit == null or not is_instance_valid(target_unit):
					continue
				if unit.is_queued_for_deletion() or target_unit.is_queued_for_deletion():
					continue
				unit.action = Actions.Following.new(target_unit)
		Enums.CommandType.COLLECTING_RESOURCES_SEQUENTIALLY:
			for entry in cmd.data.targets:
				var unit = EntityRegistry.get_unit(entry)
				var target_unit = EntityRegistry.get_unit(cmd.data.target_unit)
				if unit == null or not is_instance_valid(unit) or target_unit == null or not is_instance_valid(target_unit):
					continue
				if unit.is_queued_for_deletion() or target_unit.is_queued_for_deletion():
					continue
				unit.action = Actions.CollectingResourcesSequentially.new(target_unit)
		Enums.CommandType.AUTO_ATTACKING:
			# Assign attack actions to multiple units targeting the same enemy
			for entry in cmd.data.targets:
				var unit = EntityRegistry.get_unit(entry)
				var target_unit = EntityRegistry.get_unit(cmd.data.target_unit)
				if unit == null or not is_instance_valid(unit) or target_unit == null or not is_instance_valid(target_unit):
					continue
				if unit.is_queued_for_deletion() or target_unit.is_queued_for_deletion():
					continue
				# Note: Team checking happens in AutoAttacking.is_applicable(), same-team attacks are rejected there
				unit.action = Actions.AutoAttacking.new(target_unit)
		Enums.CommandType.CONSTRUCTING:
			# Validate that the target is a real, valid Structure before assigning construction actions
			var structure = EntityRegistry.get_unit(cmd.data.structure)
			if structure == null or not is_instance_valid(structure):
				push_error("Constructing command: structure entity_id %s is null or invalid" % cmd.data.structure)
				return
			if structure.is_queued_for_deletion():
				push_error("Constructing command: structure entity_id %s is queued for deletion" % cmd.data.structure)
				return
			# Check that structure is actually a Structure type (not a Worker or other unit that got" " corrupted)
			if not structure.is_in_group("Structures"):
				push_error("Constructing command: entity_id %s is not a Structure, it's a %s" % [cmd.data.structure, structure.get_class()])
				return
			
			# Validate each constructor unit exists and is valid
			for entry in cmd.data.selected_constructors:
				var unit = EntityRegistry.get_unit(entry)
				if unit == null or not is_instance_valid(unit):
					push_error("Constructing command: constructor entity_id %s is null or invalid" % entry)
					continue
				if unit.is_queued_for_deletion():
					push_error("Constructing command: constructor entity_id %s is queued for deletion" % entry)
					continue
				# Check that unit is actually a Worker type capable of construction
				if not unit.is_in_group("Workers"):
					push_error("Constructing command: entity_id %s is not a Worker, it's a %s" % [entry, unit.get_class()])
					continue
				unit.action = Actions.Constructing.new(structure)
		Enums.CommandType.ENTITY_IS_QUEUED:
			var structure = EntityRegistry.get_unit(cmd.data.entity_id)
			print('structure for production command: ', structure, cmd.data.entity_id)
			if structure == null or not is_instance_valid(structure):
				return
			if structure.is_queued_for_deletion():
				return
			# Load the unit prototype and queue it for production
			var unit_prototype = load(cmd.data.unit_type)
			if unit_prototype != null and structure.has_node("ProductionQueue"):
				structure.production_queue.produce(unit_prototype)
		Enums.CommandType.STRUCTURE_PLACED:
			var player = null
			for p in get_tree().get_nodes_in_group("players"):
				if p.id == cmd.data.player_id:
					player = p
					break
			if player == null or not is_instance_valid(player):
				return
			if player.is_queued_for_deletion():
				return
			var self_constructing = cmd.data.get("self_constructing", false)
			MatchSignals.setup_and_spawn_unit.emit(
				load(cmd.data.structure_prototype).instantiate(),
				cmd.data.transform,
				player,
				self_constructing
			)
		Enums.CommandType.ENTITY_PRODUCTION_CANCELED:
			var structure = EntityRegistry.get_unit(cmd.data.entity_id)
			if structure == null or not is_instance_valid(structure):
				return
			if structure.is_queued_for_deletion():
				return
			# Find and cancel the queued element by unit type
			var unit_prototype = load(cmd.data.unit_type)
			if unit_prototype != null and structure.has_node("ProductionQueue"):
				for element in structure.production_queue.get_elements():
					if element.unit_prototype.resource_path == cmd.data.unit_type:
						structure.production_queue.cancel(element)
						break
		_:
			print('Cannot execute command: ', cmd)


func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.is_action_pressed("shift_selecting"):
			return
		MatchSignals.deselect_all_units.emit()


func _set_map(a_map):
	assert(get_node_or_null("Map") == null, "map already set")
	a_map.name = "Map"
	add_child(a_map)
	a_map.owner = self


func _ignore(_value):
	pass


func _get_map():
	return get_node_or_null("Map")


func _set_visible_player(player):
	_conceal_player_units(visible_player)
	_reveal_player_units(player)
	visible_player = player


func _get_visible_players():
	if settings.visibility == settings.Visibility.PER_PLAYER:
		return [visible_player]
	return get_tree().get_nodes_in_group("players")


func _setup_subsystems_dependent_on_map():
	_terrain.update_shape(map.find_child("Terrain").mesh)
	fog_of_war.resize(map.size)
	_recalculate_camera_bounding_planes(map.size)
	navigation.setup(map)


func _recalculate_camera_bounding_planes(map_size: Vector2):
	_camera.bounding_planes[1] = Plane(-1, 0, 0, -map_size.x)
	_camera.bounding_planes[3] = Plane(0, 0, -1, -map_size.y)


func _setup_players():
	assert(
		_players.get_children().is_empty() or settings.players.is_empty(),
		"players can be defined either in settings or in scene tree, not in both"
	)
	if _players.get_children().is_empty():
		_create_players_from_settings()
	for node in _players.get_children():
		if node is Player:
			node.add_to_group("players")


func _create_players_from_settings():
	# Instantiate each player (Human or AI controller) from their configured controller scene
	for player_settings in settings.players:
		var player_scene = Constants.CONTROLLER_SCENES[player_settings.controller]
		var player = player_scene.instantiate()
		player.color = player_settings.color
		# TEAM ASSIGNMENT: Each player has a team ID. Units with same team cannot attack each other.
		# Teams are typically auto-assigned by Play.gd (player_index 0 -> team 0, player_index 1 -> team 1, etc.)
		# to ensure playable matches. Custom team assignments override this (for alliances, etc.)
		player.team = player_settings.team
		if player_settings.spawn_index_offset > 0:
			for _i in range(player_settings.spawn_index_offset):
				_players.add_child(Node.new())
		_players.add_child(player)


func _setup_player_units():
	for player in _players.get_children():
		if not player is Player:
			continue
		var player_index = player.get_index()
		var predefined_units = player.get_children().filter(func(child): return child is Unit)
		if not predefined_units.is_empty():
			predefined_units.map(func(unit): _setup_unit_groups(unit, unit.player))
		else:
			_spawn_player_units(
				player, map.find_child("SpawnPoints").get_child(player_index).global_transform
			)


func _spawn_player_units(player, spawn_transform):
	_setup_and_spawn_unit(CommandCenter.instantiate(), spawn_transform, player, false)
	_setup_and_spawn_unit(
		Drone.instantiate(), spawn_transform.translated(Vector3(-2, 0, -2)), player
	)
	_setup_and_spawn_unit(
		Worker.instantiate(), spawn_transform.translated(Vector3(-3, 0, 3)), player
	)
	_setup_and_spawn_unit(
		Worker.instantiate(), spawn_transform.translated(Vector3(3, 0, 3)), player
	)


func _setup_and_spawn_unit(unit, a_transform, player, self_constructing = false):
	unit.global_transform = a_transform
	if unit is Structure and self_constructing:
		unit.mark_as_under_construction(true)
	_setup_unit_groups(unit, player)
	player.add_child(unit)
	MatchSignals.unit_spawned.emit(unit)


func _setup_unit_groups(unit, player):
	# Categorize units into groups that the UI and game systems use for visibility/filtering
	unit.add_to_group("units")
	if player == _get_human_player():
		unit.add_to_group("controlled_units")
	else:
		unit.add_to_group("adversary_units")
	
	# TEAM-BASED VISION SHARING: Units are visible if their player is visible OR on same team.
	# This is how team vision works: all units controlled by your team are automatically revealed.
	# The UI systems (like FogOfWar) check for \"revealed_units\" group membership to decide what to show.
	# If a teammate's unit is visible, it goes into revealed_units and the UI renders it.
	if player in visible_players:
		unit.add_to_group("revealed_units")
	else:
		# Check if any visible player is on the same team - if so, include their units too
		for visible_player in visible_players:
			if visible_player != null and visible_player.team == player.team:
				unit.add_to_group("revealed_units")
				break


func _get_human_player():
	var human_players = get_tree().get_nodes_in_group("players").filter(
		func(player): return player is Human
	)
	assert(human_players.size() <= 1, "more than one human player is not allowed")
	if not human_players.is_empty():
		return human_players[0]
	return null


func _move_camera_to_initial_position():
	var human_player = _get_human_player()
	if human_player != null:
		_move_camera_to_player_units_crowd_pivot(human_player)
	else:
		_move_camera_to_player_units_crowd_pivot(get_tree().get_nodes_in_group("players")[0])


func _move_camera_to_player_units_crowd_pivot(player):
	var player_units = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit.player == player
	)
	assert(not player_units.is_empty(), "player must have at least one initial unit")
	var crowd_pivot = Utils.MatchUtils.Movement.calculate_aabb_crowd_pivot_yless(player_units)
	_camera.set_position_safely(crowd_pivot)


func _reveal_player_units(player):
	if player == null:
		return
	for unit in get_tree().get_nodes_in_group("units").filter(
		func(a_unit): return a_unit.player == player
	):
		unit.add_to_group("revealed_units")


func _conceal_player_units(player):
	if player == null:
		return
	for unit in get_tree().get_nodes_in_group("units").filter(
		func(a_unit): return a_unit.player == player
	):
		unit.remove_from_group("revealed_units")
