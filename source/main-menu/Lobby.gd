extends Control

## Lobby UI: browse LAN games, create/join, configure match settings, and chat.

const PlayerSettingsScene: PackedScene = preload("res://source/main-menu/PlayerSettings.tscn")
const LoadingScene: PackedScene = preload("res://source/main-menu/Loading.tscn")

var _is_host: bool = false
var _local_ready: bool = false
## Password of the game the client is attempting to join.
var _pending_password: String = ""
var _map_paths: Array = []
var _map_info: Dictionary = {}
var _num_spawns: int = 0
var _reconnect_button: Button = null

# ── Browse panel refs ─────────────────────────────
@onready var _browse_panel: PanelContainer = find_child("BrowsePanel")
@onready var _games_list: ItemList = find_child("GamesList")
@onready var _browse_chat_display: RichTextLabel = find_child("BrowseChatDisplay")
@onready var _browse_chat_input: LineEdit = find_child("BrowseChatInput")
@onready var _join_button: Button = find_child("JoinButton")

# ── Room panel refs ───────────────────────────────
@onready var _room_panel: PanelContainer = find_child("RoomPanel")
@onready var _map_list: ItemList = find_child("RoomMapList")
@onready var _map_details: RichTextLabel = find_child("RoomMapDetails")
@onready var _map_preview: Control = find_child("RoomMapPreview")
@onready var _player_grid: VBoxContainer = find_child("PlayerGrid")
@onready var _room_chat_display: RichTextLabel = find_child("RoomChatDisplay")
@onready var _room_chat_input: LineEdit = find_child("RoomChatInput")
@onready var _start_button: Button = find_child("StartButton")
@onready var _ready_button: Button = find_child("ReadyButton")
@onready var _room_title: Label = find_child("RoomTitle")


func _ready() -> void:
	_show_browse()
	_build_reconnect_button()
	NetworkCommandSync.peer_connected.connect(_on_peer_connected)
	NetworkCommandSync.peer_disconnected.connect(_on_peer_disconnected)
	NetworkCommandSync.connection_failed.connect(_on_connection_failed)
	NetworkCommandSync.server_disconnected.connect(_on_server_disconnected)
	NetworkCommandSync.lobby_chat_received.connect(_on_chat_received)
	NetworkCommandSync.lobby_settings_received.connect(_on_settings_received)
	NetworkCommandSync.lobby_map_changed.connect(_on_map_changed)
	NetworkCommandSync.lobby_ready_changed.connect(_on_lobby_ready_changed)
	NetworkCommandSync.lobby_room_state_received.connect(_on_room_state_received)
	NetworkCommandSync.lobby_password_rejected.connect(_on_password_rejected)
	NetworkCommandSync.lobby_player_setting_changed.connect(_on_player_setting_received)
	NetworkCommandSync.browse_chat_received.connect(_on_browse_chat_received)
	NetworkCommandSync.reconnect_state_received.connect(_on_reconnect_state_received)
	NetworkCommandSync.start_lan_discovery()


func _exit_tree() -> void:
	NetworkCommandSync.stop_lan_discovery()
	NetworkCommandSync.stop_lan_broadcast()
	NetworkCommandSync.peer_connected.disconnect(_on_peer_connected)
	NetworkCommandSync.peer_disconnected.disconnect(_on_peer_disconnected)
	NetworkCommandSync.connection_failed.disconnect(_on_connection_failed)
	NetworkCommandSync.server_disconnected.disconnect(_on_server_disconnected)
	NetworkCommandSync.lobby_chat_received.disconnect(_on_chat_received)
	NetworkCommandSync.lobby_settings_received.disconnect(_on_settings_received)
	NetworkCommandSync.lobby_map_changed.disconnect(_on_map_changed)
	NetworkCommandSync.lobby_ready_changed.disconnect(_on_lobby_ready_changed)
	NetworkCommandSync.lobby_room_state_received.disconnect(_on_room_state_received)
	NetworkCommandSync.lobby_password_rejected.disconnect(_on_password_rejected)
	NetworkCommandSync.lobby_player_setting_changed.disconnect(_on_player_setting_received)
	NetworkCommandSync.browse_chat_received.disconnect(_on_browse_chat_received)
	NetworkCommandSync.reconnect_state_received.disconnect(_on_reconnect_state_received)


func _process(_delta: float) -> void:
	if _browse_panel.visible:
		_refresh_games_list()


# ──────────────────────────────────────────────────────────────────────
# PANEL SWITCHING
# ──────────────────────────────────────────────────────────────────────


func _show_browse() -> void:
	_browse_panel.visible = true
	_room_panel.visible = false


func _show_room() -> void:
	_browse_panel.visible = false
	_room_panel.visible = true
	_start_button.visible = _is_host
	_ready_button.visible = not _is_host
	_local_ready = false
	_ready_button.text = "READY"
	_map_list.focus_mode = Control.FOCUS_ALL if _is_host else Control.FOCUS_NONE

	# Both host and client need the map registry
	_setup_map_list()

	if _is_host:
		_start_button.disabled = true  # wait for clients to ready
		if not _map_paths.is_empty():
			_map_list.select(0)
			_on_map_list_item_selected(0)


# ──────────────────────────────────────────────────────────────────────
# GAMES BROWSER
# ──────────────────────────────────────────────────────────────────────


func _refresh_games_list() -> void:
	var games: Dictionary = NetworkCommandSync.get_discovered_games()
	# Only update when item count changes to avoid flickering
	if _games_list.item_count == games.size():
		return
	var selected_key: String = ""
	var sel: PackedInt32Array = _games_list.get_selected_items()
	if not sel.is_empty():
		selected_key = _games_list.get_item_metadata(sel[0])
	_games_list.clear()
	var new_select: int = -1
	var idx: int = 0
	for key: String in games:
		var info: Dictionary = games[key]
		var pw_icon: String = "\U0001f512 " if info.get("password_protected", false) else ""
		var label: String = (
			"%s%s (%d/%d) - %s"
			% [
				pw_icon,
				info.get("name", "?"),
				info.get("current", 1),
				info.get("max", 8),
				info.get("map", "?"),
			]
		)
		_games_list.add_item(label)
		_games_list.set_item_metadata(idx, key)
		if key == selected_key:
			new_select = idx
		idx += 1
	if new_select >= 0:
		_games_list.select(new_select)


# ──────────────────────────────────────────────────────────────────────
# BROWSE PANEL HANDLERS
# ──────────────────────────────────────────────────────────────────────


func _on_create_button_pressed() -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Create Game"
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var name_label: Label = Label.new()
	name_label.text = "Game Name:"
	vbox.add_child(name_label)
	var name_input: LineEdit = LineEdit.new()
	name_input.placeholder_text = "My Game"
	name_input.text = "Game"
	name_input.name = "NameInput"
	vbox.add_child(name_input)

	var pw_label: Label = Label.new()
	pw_label.text = "Password (optional):"
	vbox.add_child(pw_label)
	var pw_input: LineEdit = LineEdit.new()
	pw_input.placeholder_text = "Leave empty for no password"
	pw_input.secret = true
	pw_input.name = "PasswordInput"
	vbox.add_child(pw_input)

	dialog.add_child(vbox)
	dialog.confirmed.connect(
		func() -> void:
			var game_name: String = name_input.text.strip_edges()
			if game_name.is_empty():
				game_name = "Game"
			var password: String = pw_input.text
			NetworkCommandSync.stop_lan_discovery()
			var err: Error = NetworkCommandSync.host_game()
			if err != OK:
				_append_browse_chat(
					"[color=red]Failed to create game: %s[/color]" % error_string(err)
				)
				NetworkCommandSync.start_lan_discovery()
				return
			_is_host = true
			NetworkCommandSync.lobby_name = game_name
			NetworkCommandSync.lobby_password = password
			NetworkCommandSync.start_lan_broadcast()
			_show_room()
			_room_title.text = game_name
			_append_room_chat("[color=green]Game created. Waiting for players...[/color]")
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(350, 180))


func _on_join_button_pressed() -> void:
	var selected: PackedInt32Array = _games_list.get_selected_items()
	if selected.is_empty():
		return
	var key: String = _games_list.get_item_metadata(selected[0])
	var games: Dictionary = NetworkCommandSync.get_discovered_games()
	var info: Dictionary = games.get(key, {})
	var is_pw_protected: bool = info.get("password_protected", false)

	if is_pw_protected:
		_show_password_dialog(key)
	else:
		_join_by_key(key, "")


func _on_direct_connect_pressed() -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Direct Connect"
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	var addr_label: Label = Label.new()
	addr_label.text = "Host address:"
	vbox.add_child(addr_label)
	var input: LineEdit = LineEdit.new()
	input.placeholder_text = "192.168.1.100"
	input.name = "AddressInput"
	vbox.add_child(input)
	var pw_label: Label = Label.new()
	pw_label.text = "Password (if any):"
	vbox.add_child(pw_label)
	var pw_input: LineEdit = LineEdit.new()
	pw_input.secret = true
	pw_input.name = "PasswordInput"
	vbox.add_child(pw_input)
	dialog.add_child(vbox)
	dialog.confirmed.connect(
		func() -> void:
			var addr: String = input.text.strip_edges()
			if addr.is_empty():
				return
			var parts: PackedStringArray = addr.split(":")
			var host: String = parts[0]
			var port: int = int(parts[1]) if parts.size() > 1 else NetworkCommandSync.DEFAULT_PORT
			NetworkCommandSync.stop_lan_discovery()
			_pending_password = pw_input.text
			var err: Error = NetworkCommandSync.join_game(host, port)
			if err != OK:
				_append_browse_chat("[color=red]Failed to connect: %s[/color]" % error_string(err))
				NetworkCommandSync.start_lan_discovery()
				_pending_password = ""
			else:
				_is_host = false
				_show_room()
				_append_room_chat("[color=green]Connecting to %s...[/color]" % addr)
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(350, 180))


func _on_browse_back_pressed() -> void:
	NetworkCommandSync.stop_lan_discovery()
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")


func _show_password_dialog(key: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Password Required"
	var vbox: VBoxContainer = VBoxContainer.new()
	var label: Label = Label.new()
	label.text = "Enter password:"
	vbox.add_child(label)
	var pw_input: LineEdit = LineEdit.new()
	pw_input.secret = true
	pw_input.name = "PasswordInput"
	vbox.add_child(pw_input)
	dialog.add_child(vbox)
	dialog.confirmed.connect(func() -> void: _join_by_key(key, pw_input.text))
	add_child(dialog)
	dialog.popup_centered(Vector2i(300, 120))


func _join_by_key(key: String, password: String) -> void:
	var games: Dictionary = NetworkCommandSync.get_discovered_games()
	var info: Dictionary = games.get(key, {})
	var address: String = info.get("address", "127.0.0.1")
	var port: int = int(info.get("port", NetworkCommandSync.DEFAULT_PORT))
	NetworkCommandSync.stop_lan_discovery()
	_pending_password = password
	var err: Error = NetworkCommandSync.join_game(address, port)
	if err != OK:
		_append_browse_chat("[color=red]Failed to join: %s[/color]" % error_string(err))
		NetworkCommandSync.start_lan_discovery()
		_pending_password = ""
		return
	_is_host = false
	_show_room()
	_append_room_chat("[color=green]Connecting...[/color]")


func _on_browse_send_pressed() -> void:
	var msg: String = _browse_chat_input.text.strip_edges()
	if msg.is_empty():
		return
	_browse_chat_input.text = ""
	NetworkCommandSync.send_browse_chat(msg)


func _on_browse_chat_submitted(_text: String) -> void:
	_on_browse_send_pressed()


# ──────────────────────────────────────────────────────────────────────
# ROOM PANEL HANDLERS
# ──────────────────────────────────────────────────────────────────────


func _on_start_button_pressed() -> void:
	if not _is_host:
		return
	if not NetworkCommandSync.are_all_lobby_peers_ready():
		_append_room_chat("[color=red]Not all players are ready![/color]")
		return
	var match_settings: MatchSettings = _create_match_settings()
	var map_path: String = _get_selected_map_path()

	# Share seed and settings with clients
	var seed_val: int = randi()
	NetworkCommandSync.share_match_seed(seed_val)
	NetworkCommandSync.sync_lobby_settings(_serialize_match_settings(match_settings), map_path)

	# Start locally
	_start_match(match_settings, map_path, seed_val)


func _on_leave_button_pressed() -> void:
	NetworkCommandSync.stop_lan_broadcast()
	NetworkCommandSync.disconnect_game()
	_is_host = false
	_local_ready = false
	_show_browse()
	NetworkCommandSync.start_lan_discovery()


func _on_room_send_pressed() -> void:
	var msg: String = _room_chat_input.text.strip_edges()
	if msg.is_empty():
		return
	_room_chat_input.text = ""
	NetworkCommandSync.send_chat_message(msg)


func _on_room_chat_submitted(_text: String) -> void:
	_on_room_send_pressed()


func _on_ready_button_pressed() -> void:
	_local_ready = not _local_ready
	_ready_button.text = "UNREADY" if _local_ready else "READY"
	NetworkCommandSync.set_lobby_ready(_local_ready)


# ──────────────────────────────────────────────────────────────────────
# MAP SELECTION (adapted from Play.gd)
# ──────────────────────────────────────────────────────────────────────


func _setup_map_list() -> void:
	_map_info = MatchConstants.MAPS.duplicate(true)
	_scan_custom_maps("res://maps/")

	var entries: Array = Utils.Dict.items(_map_info)
	entries.sort_custom(
		func(a, b):
			if a[1]["players"] != b[1]["players"]:
				return a[1]["players"] < b[1]["players"]
			return a[1]["name"] < b[1]["name"]
	)

	_map_paths = entries.map(func(e): return e[0])
	_map_list.clear()
	for path: String in _map_paths:
		_map_list.add_item(_map_info[path]["name"])
	if not _map_paths.is_empty():
		_map_list.select(0)


func _scan_custom_maps(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres"):
			continue
		var full_path: String = dir_path + file_name
		var res: Resource = load(full_path)
		if res is MapResource:
			var map_res: MapResource = res
			_map_info[full_path] = {
				"name":
				map_res.map_name if not map_res.map_name.is_empty() else file_name.get_basename(),
				"players": map_res.get_max_players(),
				"size": map_res.size,
			}
	dir.list_dir_end()


func _on_map_list_item_selected(index: int) -> void:
	if not _is_host:
		return
	var map_path: String = _map_paths[index]
	var map: Dictionary = _map_info[map_path]

	_map_details.text = "[u]Players:[/u] {0}\n[u]Size:[/u] {1}x{2}".format(
		[map["players"], map["size"].x, map["size"].y]
	)

	if map_path.ends_with(".tres"):
		_map_preview.set_map_data_from_resource(map_path)
	else:
		_map_preview.set_map_data(map_path)

	_align_player_controls_to_map(map)
	_update_start_button()

	# Update broadcast info and sync to clients
	NetworkCommandSync.update_broadcast_info(map["name"], map["players"])
	if NetworkCommandSync.is_active:
		NetworkCommandSync.sync_map_selection(map_path, index)
		# Map changed — reset readiness
		NetworkCommandSync._lobby_ready.clear()
		_update_start_button()
		_update_player_ready_highlight()


# ──────────────────────────────────────────────────────────────────────
# PLAYER SETTINGS
# ──────────────────────────────────────────────────────────────────────


func _align_player_controls_to_map(map: Dictionary) -> void:
	var num_players: int = map["players"]
	_num_spawns = num_players

	for child: Node in _player_grid.get_children():
		child.queue_free()

	var peer_ids: Array = NetworkCommandSync.get_peer_ids() if NetworkCommandSync.is_active else [1]
	peer_ids.sort()

	for player_index: int in range(num_players):
		var ps: Node = PlayerSettingsScene.instantiate()
		_player_grid.add_child(ps)

		var play_select: OptionButton = ps.find_child("PlaySelect")
		var faction_select: OptionButton = ps.find_child("FactionSelect")
		var team_select: OptionButton = ps.find_child("TeamSelect")
		var spawn_select: OptionButton = ps.find_child("SpawnSelect")
		var color_picker: ColorPickerButton = ps.find_child("ColorPickerButton")
		var number_label: Label = ps.find_child("Number")

		number_label.text = "%d." % (player_index + 1)

		# Spawn select
		_populate_spawn_select(spawn_select, num_players)
		spawn_select.item_selected.connect(_on_spawn_selected.bind(player_index))

		# Team select
		_configure_team_options(team_select, num_players)
		team_select.selected = player_index
		team_select.item_selected.connect(_on_team_selected.bind(player_index))

		# Default color
		color_picker.color = Constants.COLORS[player_index % Constants.COLORS.size()]
		color_picker.color_changed.connect(_on_color_changed.bind(player_index))

		# Faction
		faction_select.item_selected.connect(_on_faction_selected.bind(player_index))

		# Controller type defaults
		if player_index < peer_ids.size():
			play_select.selected = Constants.PlayerType.HUMAN
			var pname: String = Globals.options.player_name.strip_edges()
			play_select.set_item_text(
				Constants.PlayerType.HUMAN, pname if not pname.is_empty() else "Human"
			)
		else:
			play_select.selected = Constants.PlayerType.SIMPLE_CLAIRVOYANT_AI
		play_select.item_selected.connect(_on_player_type_selected.bind(player_index))

		# Client permissions: only faction for own slot, rest disabled
		if not _is_host:
			play_select.disabled = true
			team_select.disabled = true
			spawn_select.disabled = true
			var local_slot: int = _get_local_slot()
			faction_select.disabled = (player_index != local_slot)
		else:
			# Host cannot change faction of peer-occupied slots
			if player_index < peer_ids.size() and peer_ids[player_index] != 1:
				faction_select.disabled = true

	# Apply ready highlights after building all slots
	_update_player_ready_highlight()


func _get_local_slot() -> int:
	if not NetworkCommandSync.is_active:
		return 0
	var peers: Array = NetworkCommandSync.get_peer_ids()
	peers.sort()
	var my_id: int = multiplayer.get_unique_id()
	return peers.find(my_id)


func _configure_team_options(team_select: OptionButton, num_teams: int) -> void:
	while team_select.item_count > num_teams:
		team_select.remove_item(team_select.item_count - 1)


func _populate_spawn_select(spawn_select: OptionButton, num_spawns: int) -> void:
	spawn_select.clear()
	spawn_select.add_item("Random", 0)
	for i: int in range(num_spawns):
		spawn_select.add_item("Pos " + str(i + 1), i + 1)
	spawn_select.selected = 0


func _on_spawn_selected(selected_id: int, player_index: int) -> void:
	if selected_id == 0:
		return
	var nodes: Array[Node] = _player_grid.get_children()
	for i: int in range(nodes.size()):
		if i == player_index:
			continue
		var other_spawn: OptionButton = nodes[i].find_child("SpawnSelect")
		if other_spawn.selected == selected_id:
			other_spawn.selected = 0
	NetworkCommandSync.sync_player_setting(player_index, "spawn", selected_id)


func _on_faction_selected(selected_id: int, player_index: int) -> void:
	NetworkCommandSync.sync_player_setting(player_index, "faction", selected_id)


func _on_team_selected(selected_id: int, player_index: int) -> void:
	NetworkCommandSync.sync_player_setting(player_index, "team", selected_id)


func _on_color_changed(_color: Color, _player_index: int) -> void:
	pass  # Color is local-only — each player picks colors for their own view


func _on_player_type_selected(selected_option: int, player_index: int) -> void:
	_start_button.disabled = false
	if selected_option == Constants.PlayerType.HUMAN:
		var nodes: Array[Node] = _player_grid.get_children()
		for i: int in range(nodes.size()):
			if i != player_index:
				var ps: OptionButton = nodes[i].find_child("PlaySelect")
				if ps.selected == Constants.PlayerType.HUMAN:
					ps.selected = Constants.PlayerType.SIMPLE_CLAIRVOYANT_AI
					NetworkCommandSync.sync_player_setting(
						i, "controller", Constants.PlayerType.SIMPLE_CLAIRVOYANT_AI
					)
	elif selected_option == Constants.PlayerType.NONE:
		var nodes: Array[Node] = _player_grid.get_children()
		var active: int = 0
		for node: Node in nodes:
			if node.find_child("PlaySelect").selected != Constants.PlayerType.NONE:
				active += 1
		if active < 2:
			_start_button.disabled = true
	NetworkCommandSync.sync_player_setting(player_index, "controller", selected_option)


# ──────────────────────────────────────────────────────────────────────
# MATCH CREATION
# ──────────────────────────────────────────────────────────────────────


func _create_match_settings() -> MatchSettings:
	var match_settings: MatchSettings = MatchSettings.new()
	var nodes: Array[Node] = _player_grid.get_children()

	for i: int in range(nodes.size()):
		var ps_node: Node = nodes[i]
		var play_select: OptionButton = ps_node.find_child("PlaySelect")
		var color_picker: ColorPickerButton = ps_node.find_child("ColorPickerButton")
		var team_select: OptionButton = ps_node.find_child("TeamSelect")
		var spawn_select: OptionButton = ps_node.find_child("SpawnSelect")
		var faction_select: OptionButton = ps_node.find_child("FactionSelect")

		if play_select.selected != Constants.PlayerType.NONE:
			var ps: PlayerSettings = PlayerSettings.new()
			ps.controller = play_select.selected
			ps.color = color_picker.color
			ps.team = team_select.selected
			ps.faction = faction_select.selected
			ps.spawn_index = spawn_select.selected - 1
			ps.uuid = "%s-%s" % [randi(), Time.get_ticks_msec()]
			match_settings.players.append(ps)

	match_settings.visible_player = _get_local_slot()
	if match_settings.visible_player < 0:
		# Fallback: find first human
		for pid: int in range(match_settings.players.size()):
			if match_settings.players[pid].controller == Constants.PlayerType.HUMAN:
				match_settings.visible_player = pid
				break
	if match_settings.visible_player < 0:
		match_settings.visibility = MatchSettings.Visibility.ALL_PLAYERS

	return match_settings


func _get_selected_map_path() -> String:
	var selected: PackedInt32Array = _map_list.get_selected_items()
	if selected.is_empty() and not _map_paths.is_empty():
		return _map_paths[0]
	return _map_paths[selected[0]]


func _serialize_match_settings(settings: MatchSettings) -> Dictionary:
	var players_data: Array[Dictionary] = []
	for ps: PlayerSettings in settings.players:
		(
			players_data
			. append(
				{
					"controller": ps.controller,
					"color": ps.color.to_html(),
					"team": ps.team,
					"faction": ps.faction,
					"spawn_index": ps.spawn_index,
					"uuid": ps.uuid,
				}
			)
		)
	return {
		"players": players_data,
		"visibility": settings.visibility,
		"visible_player": settings.visible_player,
	}


func _deserialize_match_settings(data: Dictionary) -> MatchSettings:
	var ms: MatchSettings = MatchSettings.new()
	for pd: Dictionary in data.get("players", []):
		var ps: PlayerSettings = PlayerSettings.new()
		ps.controller = pd["controller"]
		ps.color = Color.html(pd["color"])
		ps.team = pd["team"]
		ps.faction = pd["faction"]
		ps.spawn_index = pd["spawn_index"]
		ps.uuid = pd.get("uuid", "")
		ms.players.append(ps)
	ms.visibility = data.get("visibility", MatchSettings.Visibility.PER_PLAYER)
	ms.visible_player = data.get("visible_player", 0)
	return ms


func _start_match(match_settings: MatchSettings, map_path: String, seed_val: int) -> void:
	NetworkCommandSync.stop_lan_broadcast()
	NetworkCommandSync.stop_lan_discovery()
	Match.rng.seed = seed_val

	hide()
	var loading: Node = LoadingScene.instantiate()
	loading.match_settings = match_settings
	loading.map_path = map_path
	get_parent().add_child(loading)
	get_tree().current_scene = loading
	queue_free()


# ──────────────────────────────────────────────────────────────────────
# NETWORK CALLBACKS
# ──────────────────────────────────────────────────────────────────────


func _on_peer_connected(peer_id: int) -> void:
	_append_room_chat("[color=yellow]Player %d connected[/color]" % peer_id)
	if not _is_host and not _pending_password.is_empty():
		# Send stored password to host for validation
		NetworkCommandSync.send_lobby_password(_pending_password)
		_pending_password = ""
	# If reconnecting, send our UUID to the host
	if not _is_host and NetworkCommandSync.had_involuntary_disconnect():
		var uuid := NetworkCommandSync._local_uuid
		if not uuid.is_empty():
			NetworkCommandSync.send_reconnect_uuid(uuid)
		return
	if _is_host:
		_refresh_player_slots()
		_update_start_button()
		# Send current room state to the new peer
		var selected: PackedInt32Array = _map_list.get_selected_items()
		if not selected.is_empty():
			var map_path: String = _map_paths[selected[0]]
			var map: Dictionary = _map_info[map_path]
			var state: Dictionary = {
				"map_path": map_path,
				"map_index": selected[0],
				"num_players": map["players"],
				"lobby_name": NetworkCommandSync.lobby_name,
				"player_slots": _serialize_player_slots(),
			}
			NetworkCommandSync.send_room_state(state, peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	_append_room_chat("[color=yellow]Player %d disconnected[/color]" % peer_id)
	if _is_host:
		_refresh_player_slots()
		_update_start_button()


func _on_connection_failed() -> void:
	_append_browse_chat("[color=red]Connection failed![/color]")
	NetworkCommandSync.disconnect_game()
	_show_browse()
	if _reconnect_button != null:
		_reconnect_button.disabled = false
		_reconnect_button.text = "Reconnect"
		var can_reconnect := (
			NetworkCommandSync.had_involuntary_disconnect()
			and not NetworkCommandSync.last_server_address.is_empty()
		)
		_reconnect_button.visible = can_reconnect
	NetworkCommandSync.start_lan_discovery()


func _on_server_disconnected() -> void:
	_append_room_chat("[color=red]Host disconnected![/color]")
	NetworkCommandSync.disconnect_game()
	_is_host = false
	_local_ready = false
	_show_browse()
	NetworkCommandSync.start_lan_discovery()


func _on_chat_received(sender_name: String, message: String) -> void:
	if _room_panel.visible:
		_append_room_chat("[b]%s:[/b] %s" % [sender_name, message])
	else:
		_append_browse_chat("[b]%s:[/b] %s" % [sender_name, message])


func _on_settings_received(settings_data: Dictionary, map_path: String) -> void:
	if _is_host:
		return
	# Client receives settings from host → start match
	var match_settings: MatchSettings = _deserialize_match_settings(settings_data)
	# Each client sets visible_player to their own slot
	match_settings.visible_player = _get_local_slot()
	var seed_val: int = NetworkCommandSync.match_seed
	_start_match(match_settings, map_path, seed_val)


func _on_map_changed(map_path: String, _map_index: int) -> void:
	if _is_host:
		return
	# Client receives map change from host — update UI
	_apply_map_selection(map_path)


func _refresh_player_slots() -> void:
	if _map_paths.is_empty():
		return
	var selected: PackedInt32Array = _map_list.get_selected_items()
	if selected.is_empty():
		return
	var map: Dictionary = _map_info[_map_paths[selected[0]]]
	_align_player_controls_to_map(map)


func _on_lobby_ready_changed(peer_id: int, is_ready: bool) -> void:
	if is_ready:
		_append_room_chat("[color=green]Player %d is ready[/color]" % peer_id)
	else:
		_append_room_chat("[color=yellow]Player %d is not ready[/color]" % peer_id)
	_update_player_ready_highlight()
	if _is_host:
		_update_start_button()


func _on_room_state_received(state: Dictionary) -> void:
	if _is_host:
		return
	var room_name: String = state.get("lobby_name", "Game")
	_room_title.text = room_name
	var map_path: String = state.get("map_path", "")
	_apply_map_selection(map_path)
	# Apply player slot settings after the map has built the slots
	var slots: Array = state.get("player_slots", [])
	_apply_player_slots(slots)


func _on_password_rejected() -> void:
	_append_room_chat("[color=red]Wrong password! Disconnecting...[/color]")
	NetworkCommandSync.disconnect_game()
	_is_host = false
	_local_ready = false
	_show_browse()
	NetworkCommandSync.start_lan_discovery()


func _on_player_setting_received(player_index: int, setting: String, value: Variant) -> void:
	var nodes: Array[Node] = _player_grid.get_children()
	if player_index < 0 or player_index >= nodes.size():
		return
	var ps_node: Node = nodes[player_index]
	match setting:
		"faction":
			ps_node.find_child("FactionSelect").selected = int(value)
		"team":
			ps_node.find_child("TeamSelect").selected = int(value)
		"spawn":
			ps_node.find_child("SpawnSelect").selected = int(value)
		"controller":
			ps_node.find_child("PlaySelect").selected = int(value)


func _apply_map_selection(map_path: String) -> void:
	if not _map_info.has(map_path):
		return
	var map: Dictionary = _map_info[map_path]
	_map_details.text = "[u]Players:[/u] {0}\n[u]Size:[/u] {1}x{2}".format(
		[map["players"], map["size"].x, map["size"].y]
	)
	_align_player_controls_to_map(map)
	if map_path.ends_with(".tres"):
		_map_preview.set_map_data_from_resource(map_path)
	else:
		_map_preview.set_map_data(map_path)
	# Select in list if host has it
	var idx: int = _map_paths.find(map_path)
	if idx >= 0:
		_map_list.select(idx)


func _update_start_button() -> void:
	if not _is_host:
		return
	_start_button.disabled = not NetworkCommandSync.are_all_lobby_peers_ready()


func _update_player_ready_highlight() -> void:
	var nodes: Array[Node] = _player_grid.get_children()
	var peer_ids: Array = NetworkCommandSync.get_peer_ids() if NetworkCommandSync.is_active else [1]
	peer_ids.sort()
	for player_index: int in range(nodes.size()):
		var number_label: Label = nodes[player_index].find_child("Number")
		if player_index < peer_ids.size():
			var pid: int = peer_ids[player_index]
			if pid == 1:  # host is always ready
				number_label.add_theme_color_override("font_color", Color.GREEN)
			elif NetworkCommandSync.is_lobby_peer_ready(pid):
				number_label.add_theme_color_override("font_color", Color.GREEN)
			else:
				number_label.remove_theme_color_override("font_color")
		else:
			number_label.remove_theme_color_override("font_color")


# ──────────────────────────────────────────────────────────────────────
# CHAT HELPERS
# ──────────────────────────────────────────────────────────────────────


func _on_browse_chat_received(sender_name: String, message: String) -> void:
	_append_browse_chat("[b]%s:[/b] %s" % [sender_name, message])


func _append_browse_chat(bbcode: String) -> void:
	_browse_chat_display.append_text(bbcode + "\n")


func _append_room_chat(bbcode: String) -> void:
	_room_chat_display.append_text(bbcode + "\n")


func _serialize_player_slots() -> Array:
	var result: Array = []
	var nodes: Array[Node] = _player_grid.get_children()
	for ps_node: Node in nodes:
		var slot: Dictionary = {
			"controller": ps_node.find_child("PlaySelect").selected,
			"faction": ps_node.find_child("FactionSelect").selected,
			"team": ps_node.find_child("TeamSelect").selected,
			"spawn": ps_node.find_child("SpawnSelect").selected,
		}
		result.append(slot)
	return result


func _apply_player_slots(slots: Array) -> void:
	var nodes: Array[Node] = _player_grid.get_children()
	for i: int in range(mini(slots.size(), nodes.size())):
		var slot: Dictionary = slots[i]
		var ps_node: Node = nodes[i]
		ps_node.find_child("PlaySelect").selected = slot.get("controller", 0)
		ps_node.find_child("FactionSelect").selected = slot.get("faction", 0)
		ps_node.find_child("TeamSelect").selected = slot.get("team", i)
		ps_node.find_child("SpawnSelect").selected = slot.get("spawn", 0)


# ──────────────────────────────────────────────────────────────────────
# RECONNECT
# ──────────────────────────────────────────────────────────────────────


func _build_reconnect_button() -> void:
	_reconnect_button = Button.new()
	_reconnect_button.text = "Reconnect"
	_reconnect_button.custom_minimum_size = Vector2(200, 50)
	_reconnect_button.pressed.connect(_on_reconnect_pressed)
	# Insert after the join button inside the browse panel
	var btn_container: Node = _join_button.get_parent()
	btn_container.add_child(_reconnect_button)
	var can_reconnect := (
		NetworkCommandSync.had_involuntary_disconnect()
		and not NetworkCommandSync.last_server_address.is_empty()
	)
	_reconnect_button.visible = can_reconnect


func _on_reconnect_pressed() -> void:
	_reconnect_button.disabled = true
	_reconnect_button.text = "Reconnecting..."
	NetworkCommandSync.stop_lan_discovery()
	var err := NetworkCommandSync.reconnect()
	if err != OK:
		_append_browse_chat("[color=red]Reconnect failed: %s[/color]" % error_string(err))
		_reconnect_button.disabled = false
		_reconnect_button.text = "Reconnect"
		NetworkCommandSync.start_lan_discovery()
		return
	# After connected_to_server fires, _on_peer_connected will be called.
	# We wait for a short moment then send our UUID so the host identifies us.
	_is_host = false
	_append_browse_chat("[color=yellow]Reconnecting to game...[/color]")


func _on_reconnect_state_received(state_data: Dictionary) -> void:
	# Received full game state snapshot from host after reconnect.
	NetworkCommandSync.clear_involuntary_disconnect()
	var ss = get_node("/root/SaveSystem")
	var save = ss.deserialize_match_from_dict(state_data)

	# Transition to Loading with the save data
	NetworkCommandSync.stop_lan_discovery()
	hide()
	var loading: Node = LoadingScene.instantiate()
	loading.match_settings = ss._deserialize_settings(save.match_settings_data)
	# Each client must see its own player slot, not the host's
	loading.match_settings.visible_player = _get_local_slot()
	loading.map_path = save.map_source_path
	loading.save_resource = save
	get_parent().add_child(loading)
	get_tree().current_scene = loading
	queue_free()
