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

# required for replays
func _on_tick():
	tick += 1
	print('tick:', tick)
	_process_commands_for_tick()

# required for replays
func _process_commands_for_tick():
	var commands_for_tick = CommandBus.get_commands_for_tick(tick)
	if commands_for_tick.is_empty():
		return

	for cmd in commands_for_tick:
		_execute_command(cmd)

func _execute_command(cmd: Dictionary):
	print('_execute_command', cmd)
	match cmd.type:
		Enums.CommandType.MOVE:
			for entry in cmd.data.targets:
				var unit: Unit = EntityRegistry.get_unit(entry.unit)
				if unit == null or not is_instance_valid(unit):
					continue
				if unit.is_queued_for_deletion():
					continue
				unit.action = Actions.Moving.new(entry.pos)
		Enums.CommandType.MOVING_TO_UNIT:
			for entry in cmd.data.targets:
				var unit: Unit = EntityRegistry.get_unit(entry)
				var target_unit = EntityRegistry.get_unit(cmd.data.target_unit)
				if unit == null or not is_instance_valid(unit) or target_unit == null or not is_instance_valid(target_unit):
					continue
				if unit.is_queued_for_deletion() or target_unit.is_queued_for_deletion():
					continue
				unit.action = Actions.MovingToUnit.new(target_unit)
		Enums.CommandType.FOLLOWING:
			for entry in cmd.data.targets:
				var unit: Unit = EntityRegistry.get_unit(entry)
				var target_unit = EntityRegistry.get_unit(cmd.data.target_unit)
				if unit == null or not is_instance_valid(unit) or target_unit == null or not is_instance_valid(target_unit):
					continue
				if unit.is_queued_for_deletion() or target_unit.is_queued_for_deletion():
					continue
				unit.action = Actions.Following.new(target_unit)
		Enums.CommandType.COLLECTING_RESOURCES_SEQUENTIALLY:
			for entry in cmd.data.targets:
				var unit: Unit = EntityRegistry.get_unit(entry)
				var target_unit = EntityRegistry.get_unit(cmd.data.target_unit)
				if unit == null or not is_instance_valid(unit) or target_unit == null or not is_instance_valid(target_unit):
					continue
				if unit.is_queued_for_deletion() or target_unit.is_queued_for_deletion():
					continue
				unit.action = Actions.CollectingResourcesSequentially.new(target_unit)
		Enums.CommandType.AUTO_ATTACKING:
			for entry in cmd.data.targets:
				var unit: Unit = EntityRegistry.get_unit(entry)
				var target_unit = EntityRegistry.get_unit(cmd.data.target_unit)
				if unit == null or not is_instance_valid(unit) or target_unit == null or not is_instance_valid(target_unit):
					continue
				if unit.is_queued_for_deletion() or target_unit.is_queued_for_deletion():
					continue
				unit.action = Actions.AutoAttacking.new(target_unit)
		Enums.CommandType.CONSTRUCTING:
			var structure = EntityRegistry.get_unit(cmd.data.structure)
			if structure == null or not is_instance_valid(structure):
				return
			if structure.is_queued_for_deletion():
				return
			for entry in cmd.data.selected_constructors:
				var unit: Unit = EntityRegistry.get_unit(entry)
				if unit == null or not is_instance_valid(unit):
					continue
				if unit.is_queued_for_deletion():
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
			MatchSignals.setup_and_spawn_unit.emit(
				load(cmd.data.structure_prototype).instantiate(),
				cmd.data.transform,
				player
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
	for player_settings in settings.players:
		var player_scene = Constants.CONTROLLER_SCENES[player_settings.controller]
		var player = player_scene.instantiate()
		player.color = player_settings.color
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


func _setup_and_spawn_unit(unit, a_transform, player, mark_structure_under_construction = true):
	unit.global_transform = a_transform
	if unit is Structure and mark_structure_under_construction:
		unit.mark_as_under_construction()
	_setup_unit_groups(unit, player)
	player.add_child(unit)
	MatchSignals.unit_spawned.emit(unit)


func _setup_unit_groups(unit, player):
	unit.add_to_group("units")
	if player == _get_human_player():
		unit.add_to_group("controlled_units")
	else:
		unit.add_to_group("adversary_units")
	# Add to revealed_units if player is visible, or if on same team as a visible player
	if player in visible_players:
		unit.add_to_group("revealed_units")
	else:
		# Check if any visible player is on the same team
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
