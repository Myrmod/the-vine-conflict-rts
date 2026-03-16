## NetworkCommandSync: Lockstep command synchronisation for multiplayer.
##
## In multiplayer, each peer sends its commands for tick N to all other peers.
## The tick loop only advances when ALL peers have submitted their command batch
## (even if empty) for that tick. This guarantees every client executes the same
## commands in the same order and reaches the same game state.
##
## INPUT DELAY: Commands target `Match.tick + INPUT_DELAY` so the network has
## time to deliver them before the target tick executes. At TICK_RATE 10 and
## INPUT_DELAY 3, that's 300 ms of look-ahead.
##
## USAGE:
##   Single-player: is_active == false, everything bypasses this system.
##   Multiplayer:    host calls host_game(), clients call join_game().
##                   CommandBus routes commands through broadcast_command().
##                   Match._on_tick() calls is_tick_ready() before advancing.

extends Node

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal all_peers_ready  ## all peers have loaded into match
signal connection_failed
signal server_disconnected

## ── Lobby signals ───────────────────────────────────────────────────
signal lobby_chat_received(sender_name: String, message: String)
signal lobby_settings_received(settings_data: Dictionary, map_path: String)
signal lobby_map_changed(map_path: String, map_index: int)
signal lobby_ready_changed(peer_id: int, is_ready: bool)
signal lobby_room_state_received(state: Dictionary)
signal lobby_player_setting_changed(player_index: int, setting: String, value: Variant)
signal browse_chat_received(sender_name: String, message: String)

## How many ticks ahead commands are scheduled. Higher = more lag tolerance,
## lower = more responsive. 2 ticks at 10 Hz = 200 ms.
const INPUT_DELAY: int = 2

## Port for ENet connections.
const DEFAULT_PORT: int = 7357
const MAX_PLAYERS: int = 8

## True when a multiplayer session is active.
var is_active: bool = false

## Peer ID → true for every connected peer (including self).
var _peers: Dictionary = {}

## Tick → { peer_id → Array[Dictionary] }  — received command batches per tick.
var _received: Dictionary = {}

## Tracks which peers have signalled they are ready (loaded into match).
var _peers_ready: Dictionary = {}

## The match seed to share with all clients.
var match_seed: int = 0

## The match settings resource shared by the host.
var shared_settings: Resource = null

## ── Lobby state ─────────────────────────────────────────────────────
var lobby_name: String = "Game"
var lobby_password: String = ""

signal lobby_password_rejected

## Peer ID → true for peers who clicked "Ready" in the lobby.
var _lobby_ready: Dictionary = {}

## ── LAN discovery ───────────────────────────────────────────────────
const DISCOVERY_PORT: int = 7358
const BROADCAST_INTERVAL: float = 2.0

var _discovery_listener: PacketPeerUDP = null
var _broadcast_sender: PacketPeerUDP = null
var _broadcast_timer: float = 0.0
var _broadcast_data: Dictionary = {}
var _discovered_games: Dictionary = {}  ## "addr:port" → info dict
var _discovery_active: bool = false
var _broadcast_active: bool = false
var _browse_chat_sender: PacketPeerUDP = null

## ── State checksum ──────────────────────────────────────────────────

## How often to compute and exchange checksums (every N ticks).
const CHECKSUM_INTERVAL: int = 10  # once per second at TICK_RATE 10

## Emitted when a desync is detected. Payload: { tick, local, remote, peer }.
signal desync_detected(info: Dictionary)

## Emitted when a remote peer pauses/unpauses.
signal match_paused_received(peer_name: String, paused: bool)

## Emitted when an in-match chat message arrives.
signal match_chat_received(sender_name: String, message: String, is_team: bool)

## Emitted when a remote peer's ready signal unblocks a stalled tick.
signal tick_unblocked

## Tick → { peer_id → int (checksum) }.
var _checksums: Dictionary = {}

## Last tick for which we detected a desync (avoid spamming).
var _last_desync_tick: int = -1

## ── Command logging ─────────────────────────────────────────────────
## Ring buffers per peer storing the last N commands sent/received.
const CMD_LOG_SIZE: int = 30

## Last commands broadcast by the local peer.
var _sent_log: Array = []  # Array[Dictionary]

## Peer ID → Array[Dictionary] of last received commands from that peer.
var _recv_log: Dictionary = {}  # int → Array[Dictionary]

# ──────────────────────────────────────────────────────────────────────
# CONNECTION SETUP
# ──────────────────────────────────────────────────────────────────────


func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("NetworkCommandSync: failed to create server: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	_setup_signals()
	_peers[1] = true  # server is always peer 1
	is_active = true
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("NetworkCommandSync: failed to connect: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	_setup_signals()
	is_active = true
	return OK


func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_peers.clear()
	_received.clear()
	_peers_ready.clear()
	_lobby_ready.clear()
	_sent_log.clear()
	_recv_log.clear()
	is_active = false


func _setup_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)


func _on_peer_connected(id: int) -> void:
	_peers[id] = true
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	_peers.erase(id)
	_received.erase(id)
	_peers_ready.erase(id)
	_lobby_ready.erase(id)
	peer_disconnected.emit(id)


func _on_connected_to_server() -> void:
	_peers[multiplayer.get_unique_id()] = true


func _on_connection_failed() -> void:
	is_active = false
	connection_failed.emit()


func _on_server_disconnected() -> void:
	is_active = false
	server_disconnected.emit()


# ──────────────────────────────────────────────────────────────────────
# MATCH SEED / SETTINGS SHARING
# ──────────────────────────────────────────────────────────────────────


## Host calls this before starting the match to share the RNG seed.
func share_match_seed(seed_value: int) -> void:
	match_seed = seed_value
	if multiplayer.is_server():
		_receive_match_seed.rpc(seed_value)


@rpc("authority", "call_remote", "reliable")
func _receive_match_seed(seed_value: int) -> void:
	match_seed = seed_value


## Signal that this peer has loaded into the match and is ready.
func signal_ready() -> void:
	_mark_peer_ready.rpc(multiplayer.get_unique_id())
	_mark_peer_ready(multiplayer.get_unique_id())


@rpc("any_peer", "call_remote", "reliable")
func _mark_peer_ready(id: int) -> void:
	_peers_ready[id] = true
	if _peers_ready.size() >= _peers.size():
		all_peers_ready.emit()


func are_all_peers_ready() -> bool:
	return _peers_ready.size() >= _peers.size()


# ──────────────────────────────────────────────────────────────────────
# COMMAND SYNCHRONISATION
# ──────────────────────────────────────────────────────────────────────


## Called by CommandBus.push_command() instead of local storage in multiplayer.
## Broadcasts this command to all peers (including self via local call).
func broadcast_command(cmd: Dictionary) -> void:
	var serialized: Dictionary = cmd.duplicate(true)
	_log_sent(serialized)
	_receive_command.rpc(serialized)
	# Also apply locally (rpc doesn't call on self)
	_receive_command(serialized)


@rpc("any_peer", "call_remote", "reliable")
func _receive_command(cmd: Dictionary) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	_log_received(sender, cmd)
	var t: int = cmd.get("tick", 0)
	if not _received.has(t):
		_received[t] = {}
	if not _received[t].has(sender):
		_received[t][sender] = []
	_received[t][sender].append(cmd)
	# Also store in CommandBus for execution
	if not CommandBus.commands.has(t):
		CommandBus.commands[t] = []
	CommandBus.commands[t].append(cmd)
	ReplayRecorder.record_command(cmd)


## Each peer must send an empty batch for ticks where it has no commands,
## so other peers know it's ready to advance.
func send_tick_ready(t: int) -> void:
	_receive_tick_ready.rpc(t)
	_receive_tick_ready_local(t)


func _receive_tick_ready_local(t: int) -> void:
	var self_id: int = multiplayer.get_unique_id()
	if not _received.has(t):
		_received[t] = {}
	if not _received[t].has(self_id):
		_received[t][self_id] = []


@rpc("any_peer", "call_remote", "reliable")
func _receive_tick_ready(t: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not _received.has(t):
		_received[t] = {}
	if not _received[t].has(sender):
		_received[t][sender] = []
		if is_tick_ready(t):
			tick_unblocked.emit()


## Returns true if all peers have submitted their commands for the given tick.
func is_tick_ready(t: int) -> bool:
	if not _received.has(t):
		return false
	for peer_id in _peers:
		if not _received[t].has(peer_id):
			return false
	return true


## Clean up old tick data to prevent memory growth.
func cleanup_tick(t: int) -> void:
	_received.erase(t)


## Get the tick that commands should target (current tick + input delay).
func get_command_tick() -> int:
	return Match.tick + INPUT_DELAY


## Number of connected peers (including self).
func get_peer_count() -> int:
	return _peers.size()


func get_peer_ids() -> Array:
	return _peers.keys()


## Returns a dictionary of { peer_id: rtt_ms } for all remote peers.
func get_peer_rtts() -> Dictionary:
	var rtts := {}
	var enet = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return rtts
	var self_id := multiplayer.get_unique_id()
	for pid in _peers:
		if pid == self_id:
			continue
		var pkt_peer := enet.get_peer(pid)
		if pkt_peer != null:
			rtts[pid] = pkt_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	return rtts


# ──────────────────────────────────────────────────────────────────────
# STATE CHECKSUMS — DESYNC DETECTION
# ──────────────────────────────────────────────────────────────────────


## Call this from Match._on_tick() after commands execute.
## Computes a checksum of deterministic game state and exchanges it
## with all peers. Mismatches indicate a desync.
func maybe_check_state(current_tick: int) -> void:
	if not is_active:
		return
	if current_tick <= 0 or current_tick % CHECKSUM_INTERVAL != 0:
		return
	var checksum: int = _compute_state_checksum()
	_submit_checksum(current_tick, checksum)
	_receive_checksum.rpc(current_tick, checksum)


## Compute a deterministic hash of the game state that matters for
## simulation correctness. Uses only data that ALL peers must agree on.
func _compute_state_checksum() -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)

	# 1. Hash all living entities in ID order (deterministic)
	var ids: Array = EntityRegistry.entities.keys()
	ids.sort()
	for eid: int in ids:
		var unit = EntityRegistry.entities[eid]
		if unit == null or not is_instance_valid(unit):
			continue
		# Entity ID
		var id_buf := PackedByteArray()
		id_buf.resize(4)
		id_buf.encode_s32(0, eid)
		ctx.update(id_buf)
		# HP (int or null → 0) — skip entities that lack hp (e.g. resource nodes)
		var hp_val: int = unit.get("hp") if "hp" in unit else 0
		if hp_val == null:
			hp_val = 0
		var hp_buf := PackedByteArray()
		hp_buf.resize(4)
		hp_buf.encode_s32(0, hp_val)
		ctx.update(hp_buf)
		# Position — quantize to millimetres to avoid float drift
		var pos: Vector3 = unit.global_position
		var pos_buf := PackedByteArray()
		pos_buf.resize(12)
		pos_buf.encode_s32(0, int(pos.x * 1000.0))
		pos_buf.encode_s32(4, int(pos.y * 1000.0))
		pos_buf.encode_s32(8, int(pos.z * 1000.0))
		ctx.update(pos_buf)

	# 2. Hash player resources in player-ID order
	var players: Array = []
	for p in EntityRegistry.entities.values():
		if p != null and is_instance_valid(p) and p.has_method("get"):
			continue
	# Use the scene tree group instead
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for p in tree.get_nodes_in_group("players"):
			players.append(p)
	players.sort_custom(func(a, b): return a.id < b.id)
	for p in players:
		var p_buf := PackedByteArray()
		p_buf.resize(12)
		p_buf.encode_s32(0, p.id)
		p_buf.encode_s32(4, p.credits)
		p_buf.encode_s32(8, p.energy)
		ctx.update(p_buf)

	var digest: PackedByteArray = ctx.finish()
	# Collapse 16-byte MD5 into a single int (first 8 bytes as int64)
	return digest.decode_s64(0)


func _submit_checksum(t: int, checksum: int) -> void:
	var self_id: int = multiplayer.get_unique_id()
	if not _checksums.has(t):
		_checksums[t] = {}
	_checksums[t][self_id] = checksum
	_try_compare_checksums(t)


@rpc("any_peer", "call_remote", "reliable")
func _receive_checksum(t: int, checksum: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not _checksums.has(t):
		_checksums[t] = {}
	_checksums[t][sender] = checksum
	_try_compare_checksums(t)


func _try_compare_checksums(t: int) -> void:
	if not _checksums.has(t):
		return
	# Need checksums from all peers before comparing
	for peer_id in _peers:
		if not _checksums[t].has(peer_id):
			return
	# All checksums received — compare
	var self_id: int = multiplayer.get_unique_id()
	var local_cs: int = _checksums[t].get(self_id, 0)
	for peer_id in _checksums[t]:
		if peer_id == self_id:
			continue
		var remote_cs: int = _checksums[t][peer_id]
		if remote_cs != local_cs and t != _last_desync_tick:
			_last_desync_tick = t
			var info := {
				"tick": t,
				"local": local_cs,
				"remote": remote_cs,
				"peer": peer_id,
			}
			push_warning(
				(
					"DESYNC at tick %d! local=%d remote=%d (peer %d)"
					% [t, local_cs, remote_cs, peer_id]
				)
			)
			_dump_desync_state(t)
			desync_detected.emit(info)
	# Clean up old checksum data
	var old_ticks: Array = []
	for stored_t in _checksums:
		if stored_t < t:
			old_ticks.append(stored_t)
	for old_t in old_ticks:
		_checksums.erase(old_t)


func _dump_desync_state(t: int) -> void:
	var ids: Array = EntityRegistry.entities.keys()
	ids.sort()
	push_warning("=== DESYNC STATE DUMP (tick %d, peer %d) ===" % [t, multiplayer.get_unique_id()])
	push_warning("Entity count: %d" % ids.size())
	for eid: int in ids:
		var unit = EntityRegistry.entities[eid]
		if unit == null or not is_instance_valid(unit):
			push_warning("  [%d] null/invalid" % eid)
			continue
		var hp_val = unit.get("hp") if "hp" in unit else -1
		var pos: Vector3 = unit.global_position
		var owner_id: int = unit.player.id if "player" in unit and unit.player != null else -1
		var type_name: String = (
			unit.get_script().resource_path.get_file() if unit.get_script() else unit.get_class()
		)
		push_warning(
			(
				"  [%d] %s owner=%d hp=%s pos=(%.3f,%.3f,%.3f)"
				% [eid, type_name, owner_id, str(hp_val), pos.x, pos.y, pos.z]
			)
		)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for p in tree.get_nodes_in_group("players"):
			push_warning("  Player %d: credits=%d energy=%d" % [p.id, p.credits, p.energy])
	push_warning("=== END DESYNC STATE DUMP ===")
	_dump_command_log(t)


# ──────────────────────────────────────────────────────────────────────
# COMMAND LOGGING
# ──────────────────────────────────────────────────────────────────────


func _log_sent(cmd: Dictionary) -> void:
	_sent_log.append(cmd.duplicate(true))
	if _sent_log.size() > CMD_LOG_SIZE:
		_sent_log.pop_front()


func _log_received(peer_id: int, cmd: Dictionary) -> void:
	if not _recv_log.has(peer_id):
		_recv_log[peer_id] = []
	_recv_log[peer_id].append(cmd.duplicate(true))
	if _recv_log[peer_id].size() > CMD_LOG_SIZE:
		_recv_log[peer_id].pop_front()


func _cmd_to_string(cmd: Dictionary) -> String:
	var type_name: String = _command_type_name(cmd.get("type", -1))
	var tick_val: int = cmd.get("tick", -1)
	var pid: int = cmd.get("player_id", -1)
	var data: Dictionary = cmd.get("data", {})
	var extras: String = ""
	if data.has("targets"):
		var ids: Array = []
		for t in data.targets:
			if t is Dictionary and t.has("unit"):
				ids.append(t.unit)
		extras += " units=%s" % str(ids)
	if data.has("entity_id"):
		extras += " entity=%d" % data.entity_id
	if data.has("unit_type"):
		extras += " unit_type=%s" % data.unit_type.get_file()
	if data.has("structure_prototype"):
		extras += " proto=%s" % data.structure_prototype.get_file()
	if data.has("producer_id"):
		extras += " producer=%d" % data.producer_id
	return "tick=%d type=%s player=%d%s" % [tick_val, type_name, pid, extras]


func _command_type_name(type_val: int) -> String:
	for key in Enums.CommandType.keys():
		if Enums.CommandType[key] == type_val:
			return key
	return "UNKNOWN(%d)" % type_val


func _dump_command_log(t: int) -> void:
	push_warning(
		"=== COMMAND LOG (desync at tick %d, local peer %d) ===" % [t, multiplayer.get_unique_id()]
	)
	push_warning("-- Last %d SENT commands --" % _sent_log.size())
	for cmd in _sent_log:
		push_warning("  S: %s" % _cmd_to_string(cmd))
	for peer_id in _recv_log:
		var log: Array = _recv_log[peer_id]
		push_warning("-- Last %d RECEIVED from peer %d --" % [log.size(), peer_id])
		for cmd in log:
			push_warning("  R[%d]: %s" % [peer_id, _cmd_to_string(cmd)])
	push_warning("=== END COMMAND LOG ===")


# ──────────────────────────────────────────────────────────────────────
# LAN DISCOVERY
# ──────────────────────────────────────────────────────────────────────


func _process(delta: float) -> void:
	if _broadcast_active and _broadcast_sender != null:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = BROADCAST_INTERVAL
			_send_broadcast()

	if _discovery_active and _discovery_listener != null:
		_poll_discovery()


func start_lan_broadcast() -> void:
	_broadcast_sender = PacketPeerUDP.new()
	_broadcast_sender.set_broadcast_enabled(true)
	_broadcast_sender.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_broadcast_timer = 0.0  # send immediately
	_broadcast_active = true


func stop_lan_broadcast() -> void:
	_broadcast_active = false
	if _broadcast_sender != null:
		_broadcast_sender.close()
		_broadcast_sender = null


func update_broadcast_info(map_name: String = "", max_players: int = 8) -> void:
	var pname: String = Globals.options.player_name.strip_edges()
	if pname.is_empty():
		pname = "Host"
	_broadcast_data = {
		"name": lobby_name,
		"host_id": "%s|%s" % [pname, lobby_name],
		"port": DEFAULT_PORT,
		"map": map_name,
		"current": _peers.size(),
		"max": max_players,
		"password_protected": not lobby_password.is_empty(),
	}


func _send_broadcast() -> void:
	if _broadcast_sender == null:
		return
	_broadcast_data["current"] = _peers.size()
	_broadcast_data["type"] = "game"
	var json := JSON.stringify(_broadcast_data)
	var buf := json.to_utf8_buffer()
	# Broadcast to LAN
	_broadcast_sender.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_broadcast_sender.put_packet(buf)
	# Also send to localhost so same-machine discovery always works (Windows
	# often does not route 255.255.255.255 to the loopback interface).
	_broadcast_sender.set_dest_address("127.0.0.1", DISCOVERY_PORT)
	_broadcast_sender.put_packet(buf)


func start_lan_discovery() -> void:
	stop_lan_discovery()
	_discovery_listener = PacketPeerUDP.new()
	var err := _discovery_listener.bind(DISCOVERY_PORT)
	if err != OK:
		push_warning(
			(
				"NetworkCommandSync: could not bind discovery port %d: %s"
				% [DISCOVERY_PORT, error_string(err)]
			)
		)
		_discovery_listener = null
		return
	_discovery_active = true
	_discovered_games.clear()
	# Set up a UDP sender for browse chat
	_browse_chat_sender = PacketPeerUDP.new()
	_browse_chat_sender.set_broadcast_enabled(true)


func stop_lan_discovery() -> void:
	_discovery_active = false
	if _discovery_listener != null:
		_discovery_listener.close()
		_discovery_listener = null
	if _browse_chat_sender != null:
		_browse_chat_sender.close()
		_browse_chat_sender = null


func _poll_discovery() -> void:
	while _discovery_listener.get_available_packet_count() > 0:
		var packet := _discovery_listener.get_packet()
		var addr := _discovery_listener.get_packet_ip()
		var json := JSON.new()
		if json.parse(packet.get_string_from_utf8()) != OK:
			continue
		var data = json.data
		if not data is Dictionary:
			continue
		var pkt_type: String = data.get("type", "game")
		if pkt_type == "chat":
			browse_chat_received.emit(data.get("sender", "?"), data.get("message", ""))
			continue
		# Game discovery packet
		var port: int = data.get("port", DEFAULT_PORT)
		var key: String = data.get("host_id", "%s:%d" % [addr, port])
		data["address"] = addr
		_discovered_games[key] = data


func get_discovered_games() -> Dictionary:
	return _discovered_games


## Send a chat message via UDP broadcast (for the browse/global lobby).
func send_browse_chat(message: String) -> void:
	if _browse_chat_sender == null:
		return
	var pname: String = Globals.options.player_name.strip_edges()
	if pname.is_empty():
		pname = "Player"
	var data := {"type": "chat", "sender": pname, "message": message}
	var buf := JSON.stringify(data).to_utf8_buffer()
	_browse_chat_sender.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_browse_chat_sender.put_packet(buf)
	_browse_chat_sender.set_dest_address("127.0.0.1", DISCOVERY_PORT)
	_browse_chat_sender.put_packet(buf)


# ──────────────────────────────────────────────────────────────────────
# LOBBY CHAT
# ──────────────────────────────────────────────────────────────────────


func send_chat_message(message: String) -> void:
	var pname: String = Globals.options.player_name.strip_edges()
	if pname.is_empty():
		var my_id: int = multiplayer.get_unique_id() if is_active else 0
		pname = "Player %d" % my_id
	if is_active:
		_receive_chat.rpc(pname, message)
	lobby_chat_received.emit(pname, message)


@rpc("any_peer", "call_remote", "reliable")
func _receive_chat(sender_name: String, message: String) -> void:
	lobby_chat_received.emit(sender_name, message)


# ──────────────────────────────────────────────────────────────────────
# MATCH PAUSE BROADCAST
# ──────────────────────────────────────────────────────────────────────


## Broadcast pause/unpause to all peers.
func broadcast_pause(paused: bool) -> void:
	if not is_active:
		return
	var pname: String = Globals.options.player_name.strip_edges()
	if pname.is_empty():
		pname = "Player %d" % multiplayer.get_unique_id()
	_receive_pause.rpc(pname, paused)


@rpc("any_peer", "call_remote", "reliable")
func _receive_pause(peer_name: String, paused: bool) -> void:
	match_paused_received.emit(peer_name, paused)


# ──────────────────────────────────────────────────────────────────────
# MATCH CHAT
# ──────────────────────────────────────────────────────────────────────


func send_match_chat(message: String, is_team: bool) -> void:
	var pname: String = Globals.options.player_name.strip_edges()
	if pname.is_empty():
		pname = "Player %d" % (multiplayer.get_unique_id() if is_active else 0)
	if is_active:
		if is_team:
			var my_team: int = _get_local_team()
			_receive_match_chat_team.rpc(pname, message, my_team)
		else:
			_receive_match_chat.rpc(pname, message)
	# Show locally
	match_chat_received.emit(pname, message, is_team)


@rpc("any_peer", "call_remote", "reliable")
func _receive_match_chat(sender_name: String, message: String) -> void:
	match_chat_received.emit(sender_name, message, false)


@rpc("any_peer", "call_remote", "reliable")
func _receive_match_chat_team(
	sender_name: String,
	message: String,
	sender_team: int,
) -> void:
	var my_team: int = _get_local_team()
	if sender_team == my_team:
		match_chat_received.emit(sender_name, message, true)


func _get_local_team() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return -1
	var units = tree.get_nodes_in_group("controlled_units")
	if not units.is_empty() and "player" in units[0]:
		return units[0].player.team
	# Fallback: use unique ID as team
	return multiplayer.get_unique_id()


# ──────────────────────────────────────────────────────────────────────
# LOBBY SETTINGS SYNC
# ──────────────────────────────────────────────────────────────────────


## Host sends match settings + map path to all clients to start the game.
func sync_lobby_settings(settings_data: Dictionary, map_path: String) -> void:
	if multiplayer.is_server():
		_receive_lobby_settings.rpc(settings_data, map_path)


@rpc("authority", "call_remote", "reliable")
func _receive_lobby_settings(settings_data: Dictionary, map_path: String) -> void:
	lobby_settings_received.emit(settings_data, map_path)


## Host broadcasts current map selection to clients.
func sync_map_selection(map_path: String, index: int) -> void:
	if multiplayer.is_server():
		_receive_map_selection.rpc(map_path, index)


@rpc("authority", "call_remote", "reliable")
func _receive_map_selection(map_path: String, index: int) -> void:
	lobby_map_changed.emit(map_path, index)


## Sync a single player-slot setting change to all peers.
## Any peer can call this (host changes any slot, client changes own faction).
func sync_player_setting(player_index: int, setting: String, value: Variant) -> void:
	if not is_active:
		return
	# Convert Color to html string for RPC serialisation
	var rpc_value: Variant = value
	if value is Color:
		rpc_value = value.to_html()
	if multiplayer.is_server():
		_receive_player_setting.rpc(player_index, setting, rpc_value)
	else:
		_receive_player_setting.rpc_id(1, player_index, setting, rpc_value)


@rpc("any_peer", "call_remote", "reliable")
func _receive_player_setting(player_index: int, setting: String, value: Variant) -> void:
	lobby_player_setting_changed.emit(player_index, setting, value)
	# If host received from a client, relay to all other clients
	if multiplayer.is_server():
		var sender: int = multiplayer.get_remote_sender_id()
		for peer_id: int in _peers:
			if peer_id == 1 or peer_id == sender:
				continue
			_receive_player_setting.rpc_id(peer_id, player_index, setting, value)


# ──────────────────────────────────────────────────────────────────────
# LOBBY READY STATE
# ──────────────────────────────────────────────────────────────────────


## Client toggles their ready state.
func set_lobby_ready(ready: bool) -> void:
	var my_id: int = multiplayer.get_unique_id()
	_lobby_ready[my_id] = ready
	lobby_ready_changed.emit(my_id, ready)
	if is_active:
		_receive_lobby_ready.rpc(my_id, ready)


@rpc("any_peer", "call_remote", "reliable")
func _receive_lobby_ready(peer_id: int, ready: bool) -> void:
	_lobby_ready[peer_id] = ready
	lobby_ready_changed.emit(peer_id, ready)


func is_lobby_peer_ready(peer_id: int) -> bool:
	return _lobby_ready.get(peer_id, false)


func are_all_lobby_peers_ready() -> bool:
	for peer_id: int in _peers:
		if peer_id == 1:  # host doesn't need to ready-up
			continue
		if not _lobby_ready.get(peer_id, false):
			return false
	# Need at least one non-host peer
	return _peers.size() > 1


## Host sends the full room state to a specific peer (or all).
func send_room_state(state: Dictionary, target_peer: int = 0) -> void:
	if not multiplayer.is_server():
		return
	if target_peer > 0:
		_receive_room_state.rpc_id(target_peer, state)
	else:
		_receive_room_state.rpc(state)


@rpc("authority", "call_remote", "reliable")
func _receive_room_state(state: Dictionary) -> void:
	lobby_room_state_received.emit(state)


# ──────────────────────────────────────────────────────────────────────
# LOBBY PASSWORD VALIDATION
# ──────────────────────────────────────────────────────────────────────


## Client sends password to host after connecting.
func send_lobby_password(password: String) -> void:
	if multiplayer.is_server():
		return
	_receive_lobby_password.rpc_id(1, password)


@rpc("any_peer", "call_remote", "reliable")
func _receive_lobby_password(password: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if lobby_password.is_empty():
		return  # no password required
	if password != lobby_password:
		_notify_password_rejected.rpc_id(sender)
		# Kick after a short delay so the rejection message arrives
		get_tree().create_timer(0.5).timeout.connect(
			func() -> void:
				var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
				if peer != null:
					peer.disconnect_peer(sender)
		)


@rpc("authority", "call_remote", "reliable")
func _notify_password_rejected() -> void:
	lobby_password_rejected.emit()
