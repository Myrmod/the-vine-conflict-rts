extends Node
## Headless dedicated server entry point.
##
## Hosts a single game on a given port, waits for players to connect,
## then starts the match. Run multiple instances on different ports
## to host multiple games simultaneously.
##
## CLI usage:
##   godot --headless -- --server --port 7357 --map "res://maps/symmetric.tres" --players 2 --password secret
##
## All arguments are optional and fall back to sensible defaults.

const LoadingScene = preload("res://source/main-menu/Loading.tscn")

var _port: int = NetworkCommandSync.DEFAULT_PORT
var _map_path: String = ""
var _expected_players: int = 2
var _password: String = ""
var _started: bool = false


func _ready() -> void:
	_parse_args()
	_resolve_default_map()

	print(
		(
			"[DedicatedServer] Hosting on port %d, map: %s, expecting %d players"
			% [_port, _map_path, _expected_players]
		)
	)

	var err := NetworkCommandSync.host_game(_port)
	if err != OK:
		push_error("[DedicatedServer] Failed to host: %s" % error_string(err))
		get_tree().quit(1)
		return

	if not _password.is_empty():
		NetworkCommandSync.lobby_password = _password

	NetworkCommandSync.lobby_name = "Dedicated Server (port %d)" % _port
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	print("[DedicatedServer] Waiting for %d players..." % _expected_players)


func _on_peer_connected(peer_id: int) -> void:
	var peer_count := multiplayer.get_peers().size()
	print(
		"[DedicatedServer] Player %d connected (%d/%d)" % [peer_id, peer_count, _expected_players]
	)
	if peer_count >= _expected_players and not _started:
		# Small delay to let clients finish handshake
		get_tree().create_timer(1.0).timeout.connect(_start_match)


func _on_peer_disconnected(peer_id: int) -> void:
	var peer_count := multiplayer.get_peers().size()
	print("[DedicatedServer] Player %d disconnected (%d remaining)" % [peer_id, peer_count])
	if _started and peer_count == 0:
		print("[DedicatedServer] All players left. Shutting down.")
		get_tree().quit(0)


func _start_match() -> void:
	if _started:
		return
	_started = true

	var match_settings := _build_match_settings()
	var seed_val := randi()

	print("[DedicatedServer] Starting match with seed %d" % seed_val)

	NetworkCommandSync.share_match_seed(seed_val)
	NetworkCommandSync.sync_lobby_settings(_serialize_match_settings(match_settings), _map_path)

	Match.rng.seed = seed_val
	CommandBus.clear()
	EntityRegistry.reset()
	PlayerManager.reset()

	var loading := LoadingScene.instantiate()
	loading.match_settings = match_settings
	loading.map_path = _map_path
	get_parent().add_child(loading)
	get_tree().current_scene = loading
	queue_free()


func _build_match_settings() -> MatchSettings:
	var settings := MatchSettings.new()
	var peers := multiplayer.get_peers()

	var colors := [
		Color.RED,
		Color.BLUE,
		Color.GREEN,
		Color.YELLOW,
		Color.PURPLE,
		Color.ORANGE,
		Color.CYAN,
		Color.MAGENTA,
	]

	# Peer 1 (server) is not a player in dedicated mode.
	# Each connected peer is a human player.
	for i in range(peers.size()):
		var ps := PlayerSettings.new()
		ps.controller = Constants.PlayerType.HUMAN
		ps.color = colors[i % colors.size()]
		ps.team = i
		ps.faction = Enums.Faction.AMUNS
		ps.spawn_index = i
		ps.uuid = "%d-%d" % [peers[i], Time.get_ticks_msec()]
		settings.players.append(ps)

	settings.visibility = MatchSettings.Visibility.PER_PLAYER
	settings.visible_player = 0
	return settings


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


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--port":
				i += 1
				if i < args.size():
					_port = int(args[i])
			"--map":
				i += 1
				if i < args.size():
					_map_path = args[i]
			"--players":
				i += 1
				if i < args.size():
					_expected_players = clampi(int(args[i]), 2, NetworkCommandSync.MAX_PLAYERS)
			"--password":
				i += 1
				if i < args.size():
					_password = args[i]
		i += 1


func _resolve_default_map() -> void:
	if _map_path.is_empty():
		# Pick the first available map
		var map_keys := MatchConstants.MAPS.keys()
		if not map_keys.is_empty():
			_map_path = map_keys[0]
		else:
			push_error("[DedicatedServer] No maps available")
			get_tree().quit(1)
