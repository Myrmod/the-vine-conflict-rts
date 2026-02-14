extends Control

# Mode A — normal:
# Main → Play → Loading → Match

# Mode B — replay:
# ReplayMenu → Play (replay mode) → Loading → Match

const PlayerSettingsScene = preload("res://source/main-menu/PlayerSettings.tscn")
const LoadingScene = preload("res://source/main-menu/Loading.tscn")

var _map_paths = []
var replay_resource = null

@onready var _start_button = find_child("StartButton")
@onready var _map_list = find_child("MapList")
@onready var _map_details = find_child("MapDetailsLabel")


func _ready():
	if replay_resource != null:
		_start_from_replay()
		return

	_setup_map_list()
	_on_map_list_item_selected(0)


func _setup_map_list():
	var maps = Utils.Dict.items(MatchConstants.MAPS)
	maps.sort_custom(func(map_a, map_b): return map_a[1]["players"] < map_b[1]["players"])
	_map_paths = maps.map(func(map): return map[0])
	_map_list.clear()
	for map_path in _map_paths:
		_map_list.add_item(MatchConstants.MAPS[map_path]["name"])
	_map_list.select(0)


func _configure_team_options(team_select: OptionButton, num_teams: int):
	# Remove all items except the first num_teams
	while team_select.item_count > num_teams:
		team_select.remove_item(team_select.item_count - 1)


func _create_match_settings():
	# Build MatchSettings from UI selections (controller type, color, team, spawn position).
	# This is called when user clicks \"Play\" in the main menu.
	var match_settings = MatchSettings.new()

	var player_settings_nodes = find_child("GridContainer").get_children()
	var spawn_index_offset = 0
	for player_index in range(player_settings_nodes.size()):
		var player_container = player_settings_nodes[player_index]
		var play_select = player_container.find_child("PlaySelect")
		var color_picker = player_container.find_child("ColorPickerButton")
		var team_select = player_container.find_child("TeamSelect")
		# TODO: the spawn settings should be added as soon as we have proper map visuals, since currently nothing can be decided

		var player_controller = play_select.selected
		if player_controller != Constants.PlayerType.NONE:
			var player_settings = PlayerSettings.new()
			player_settings.controller = player_controller
			player_settings.color = color_picker.color
			# TEAM ASSIGNMENT: Read from UI selection. If 0 (default), users can override team memberships for alliances.
			# Match.gd will use these team values when creating Player nodes.
			player_settings.team = team_select.selected
			player_settings.spawn_index_offset = spawn_index_offset
			match_settings.players.append(player_settings)
			spawn_index_offset = 0
		else:
			spawn_index_offset += 1

	match_settings.visible_player = -1
	for player_id in range(match_settings.players.size()):
		var player = match_settings.players[player_id]
		if player.controller == Constants.PlayerType.HUMAN:
			match_settings.visible_player = player_id
	if match_settings.visible_player == -1:
		match_settings.visibility = match_settings.Visibility.ALL_PLAYERS

	return match_settings


func _get_selected_map_path():
	return _map_paths[_map_list.get_selected_items()[0]]


func _on_start_button_pressed():
	hide()
	var new_scene = LoadingScene.instantiate()
	new_scene.match_settings = _create_match_settings()
	new_scene.map_path = _get_selected_map_path()
	get_parent().add_child(new_scene)
	get_tree().current_scene = new_scene
	queue_free()

func _on_back_button_pressed():
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")


func _align_player_controls_visibility_to_map(map):
	var grid_container = find_child("GridContainer")
	var num_players = map["players"]
	
	# Clear existing player settings
	for child in grid_container.get_children():
		child.queue_free()
	
	# Create new player settings for each spawn point
	for player_index in range(num_players):
		var player_settings_instance = PlayerSettingsScene.instantiate()
		grid_container.add_child(player_settings_instance)
		
		# Set the player number label
		var number_label = player_settings_instance.find_child("Number")
		number_label.text = str(player_index + 1) + "."
		
		# Configure team select to only show teams matching spawn points
		var team_select = player_settings_instance.find_child("TeamSelect")
		_configure_team_options(team_select, num_players)
		team_select.selected = player_index
		
		# Set default color
		var color_picker = player_settings_instance.find_child("ColorPickerButton")
		color_picker.color = Constants.COLORS[player_index % Constants.COLORS.size()]
		
		# Set default controller type
		var play_select = player_settings_instance.find_child("PlaySelect")
		if player_index == 0:
			play_select.selected = Constants.PlayerType.HUMAN
		elif player_index == 1:
			play_select.selected = Constants.PlayerType.SIMPLE_CLAIRVOYANT_AI
		play_select.item_selected.connect(_on_player_selected.bind(player_index))


func _on_player_selected(selected_option_id, selected_player_id):
	_start_button.disabled = false
	if selected_option_id == Constants.PlayerType.HUMAN:
		var player_settings_nodes = find_child("GridContainer").get_children()
		for player_index in range(player_settings_nodes.size()):
			if player_index != selected_player_id:
				var play_select = player_settings_nodes[player_index].find_child("PlaySelect")
				if play_select.selected == Constants.PlayerType.HUMAN:
					play_select.selected = Constants.PlayerType.SIMPLE_CLAIRVOYANT_AI
	elif selected_option_id == Constants.PlayerType.NONE:
		var player_settings_nodes = find_child("GridContainer").get_children()
		var human_count = 0
		for player_container in player_settings_nodes:
			var play_select = player_container.find_child("PlaySelect")
			if play_select.selected != Constants.PlayerType.NONE:
				human_count += 1
		if human_count < 2:
			_start_button.disabled = true


func _on_map_list_item_selected(index):
	var map = MatchConstants.MAPS[_map_paths[index]]

	# set the map description text
	_map_details.text = "[u]Players:[/u] {0}\n[u]Size:[/u] {1}x{2}".format(
		[map["players"], map["size"].x, map["size"].y]
	)

	# Generate player settings for each spawn point
	_align_player_controls_visibility_to_map(map)
	
	# Reset start button state
	_start_button.disabled = false

func _start_from_replay():
	hide()
	var loading = LoadingScene.instantiate()
	loading.match_settings = replay_resource.settings
	loading.map_path = replay_resource.map
	loading.replay_resource = replay_resource
	# change_scene_to_node() expects a fresh node that is NOT inside the tree yet.
	get_tree().change_scene_to_node(loading)
