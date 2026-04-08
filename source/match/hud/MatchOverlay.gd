extends CanvasLayer

## Overlay for multiplayer notifications (pause, desync, disconnect) and in-game chat.
## Process mode is ALWAYS so it works while the tree is paused.

const MAX_CHAT_LINES: int = 50
const CHAT_FADE_DELAY: float = 8.0

var _chat_mode: int = 0  # 0 = all, 1 = team
var _chat_visible: bool = false
var _chat_fade_timer: float = 0.0
var _local_team: int = -1
var _disconnect_active: bool = false
var _match_finished: bool = false
var _disconnect_panel: VBoxContainer = null
var _disconnect_label: Label = null
var _disconnect_timer_label: Label = null
var _disconnect_leave_button: Button = null
var _disconnect_resume_button: Button = null

@onready var _overlay_label: Label = $OverlayLabel
@onready var _chat_log: RichTextLabel = $ChatContainer/ChatLog
@onready var _chat_input: LineEdit = $ChatContainer/ChatInput
@onready var _chat_container: VBoxContainer = $ChatContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay_label.hide()
	_chat_input.hide()
	_chat_log.text = ""
	_chat_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_chat_input.text_submitted.connect(_on_chat_input_submitted)

	NetworkCommandSync.desync_detected.connect(_on_desync_detected)
	NetworkCommandSync.match_paused_received.connect(_on_match_paused)
	NetworkCommandSync.match_chat_received.connect(_on_chat_received)
	NetworkCommandSync.player_disconnected_in_match.connect(_on_player_disconnected_in_match)
	NetworkCommandSync.player_reconnected_in_match.connect(_on_player_reconnected_in_match)
	NetworkCommandSync.reconnect_timer_expired.connect(_on_reconnect_timer_expired)
	NetworkCommandSync.reconnect_client_ready.connect(_on_reconnect_client_ready)

	_build_disconnect_panel()


func _process(delta: float) -> void:
	if _chat_fade_timer > 0.0:
		_chat_fade_timer -= delta
		if _chat_fade_timer <= 0.0 and not _chat_visible:
			_chat_log.modulate.a = 0.0

	# Tick the reconnect countdown
	if _disconnect_active:
		NetworkCommandSync.tick_reconnect_timer(delta)
		var remaining := NetworkCommandSync.get_reconnect_time_remaining()
		if remaining > 0.0 and _disconnect_timer_label != null:
			_disconnect_timer_label.text = "Time remaining: %ds" % ceili(remaining)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	# Debug: force disconnect (Ctrl+F12)
	if (
		event.is_action_pressed("debug_force_disconnect")
		and FeatureFlags.debug_disconnect
		and NetworkCommandSync.is_active
	):
		push_warning("DEBUG: forcing disconnect")
		NetworkCommandSync.disconnect_game(false)
		get_tree().paused = false
		get_tree().call_deferred("change_scene_to_file", "res://source/main-menu/Main.tscn")
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if not _chat_visible:
			_open_chat()
			get_viewport().set_input_as_handled()
		return
	if _chat_visible and event.keycode == KEY_TAB:
		_toggle_chat_mode()
		get_viewport().set_input_as_handled()
		return
	if _chat_visible and event.keycode == KEY_ESCAPE:
		_close_chat()
		get_viewport().set_input_as_handled()
		return


func set_local_team(team: int) -> void:
	_local_team = team


func set_match_finished() -> void:
	_match_finished = true
	_disconnect_active = false
	_disconnect_panel.hide()


func show_overlay(text: String) -> void:
	_overlay_label.text = text
	_overlay_label.show()


func hide_overlay() -> void:
	_overlay_label.hide()


func _open_chat() -> void:
	_chat_visible = true
	_chat_input.show()
	_chat_input.grab_focus()
	_chat_log.modulate.a = 1.0
	_update_chat_prefix()


func _close_chat() -> void:
	_chat_visible = false
	_chat_input.hide()
	_chat_input.text = ""
	_chat_input.release_focus()
	_chat_fade_timer = CHAT_FADE_DELAY


func _toggle_chat_mode() -> void:
	_chat_mode = 1 - _chat_mode
	_update_chat_prefix()


func _update_chat_prefix() -> void:
	var prefix = "/all " if _chat_mode == 0 else "/team "
	var old = _chat_input.text
	if old.begins_with("/all "):
		old = old.substr(5)
	elif old.begins_with("/team "):
		old = old.substr(6)
	_chat_input.text = prefix + old
	_chat_input.caret_column = _chat_input.text.length()


func _on_chat_input_submitted(_text: String) -> void:
	_send_chat()


func _send_chat() -> void:
	var raw = _chat_input.text
	var is_team := false
	var body: String = raw
	if raw.begins_with("/team "):
		is_team = true
		body = raw.substr(6).strip_edges()
	elif raw.begins_with("/all "):
		is_team = false
		body = raw.substr(5).strip_edges()
	else:
		body = raw.strip_edges()
	_close_chat()
	if body.is_empty():
		return
	NetworkCommandSync.send_match_chat(body, is_team)


func _on_desync_detected(_info: Dictionary) -> void:
	show_overlay("DESYNC DETECTED")


func _on_match_paused(peer_name: String, paused: bool) -> void:
	if paused:
		show_overlay("GAME PAUSED by %s" % peer_name)
		get_tree().paused = true
	else:
		hide_overlay()
		get_tree().paused = false


func _on_chat_received(sender_name: String, message: String, is_team: bool) -> void:
	var tag := "[TEAM] " if is_team else "[ALL] "
	var color := "#aaccff" if is_team else "#ffffff"
	_chat_log.append_text("[color=%s]%s%s:[/color] %s\n" % [color, tag, sender_name, message])
	_chat_log.modulate.a = 1.0
	_chat_fade_timer = CHAT_FADE_DELAY


# ──────────────────────────────────────────────────────────────────────
# DISCONNECT HANDLING
# ──────────────────────────────────────────────────────────────────────


func _build_disconnect_panel() -> void:
	_disconnect_panel = VBoxContainer.new()
	_disconnect_panel.name = "DisconnectPanel"
	_disconnect_panel.anchors_preset = Control.PRESET_CENTER
	_disconnect_panel.anchor_left = 0.5
	_disconnect_panel.anchor_top = 0.4
	_disconnect_panel.anchor_right = 0.5
	_disconnect_panel.anchor_bottom = 0.4
	_disconnect_panel.offset_left = -200.0
	_disconnect_panel.offset_top = -60.0
	_disconnect_panel.offset_right = 200.0
	_disconnect_panel.offset_bottom = 60.0
	_disconnect_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_disconnect_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_disconnect_panel.alignment = BoxContainer.ALIGNMENT_CENTER

	_disconnect_label = Label.new()
	_disconnect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_disconnect_label.add_theme_font_size_override("font_size", 24)
	_disconnect_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_disconnect_panel.add_child(_disconnect_label)

	_disconnect_timer_label = Label.new()
	_disconnect_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_disconnect_timer_label.add_theme_font_size_override("font_size", 20)
	_disconnect_timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_disconnect_panel.add_child(_disconnect_timer_label)

	_disconnect_resume_button = Button.new()
	_disconnect_resume_button.text = "Resume Game"
	_disconnect_resume_button.custom_minimum_size = Vector2(160, 40)
	_disconnect_resume_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_disconnect_resume_button.pressed.connect(_on_disconnect_resume_pressed)
	_disconnect_resume_button.hide()
	_disconnect_panel.add_child(_disconnect_resume_button)

	_disconnect_leave_button = Button.new()
	_disconnect_leave_button.text = "Leave Game"
	_disconnect_leave_button.custom_minimum_size = Vector2(160, 40)
	_disconnect_leave_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_disconnect_leave_button.pressed.connect(_on_disconnect_leave_pressed)
	_disconnect_panel.add_child(_disconnect_leave_button)

	_disconnect_panel.hide()
	add_child(_disconnect_panel)


func _on_player_disconnected_in_match(peer_id: int) -> void:
	if _match_finished:
		return
	_disconnect_active = true
	_disconnect_label.text = "Player disconnected (peer %d)" % peer_id
	_disconnect_timer_label.text = "Waiting for reconnect... 60s"
	_disconnect_panel.show()

	# Pause the game
	get_tree().paused = true

	# Start the countdown (only host starts it, but all show it)
	if not NetworkCommandSync.has_disconnected_peers():
		return
	if NetworkCommandSync.get_reconnect_time_remaining() <= 0.0:
		NetworkCommandSync.start_reconnect_timer()


func _on_player_reconnected_in_match(_peer_id: int, _uuid: String) -> void:
	if _match_finished:
		return
	# Don't unpause yet — wait for the client to finish loading.
	# The host will unpause when it receives reconnect_client_ready.
	if _disconnect_label != null:
		_disconnect_label.text = "Player reconnected — syncing state..."


func _on_reconnect_client_ready(_peer_id: int) -> void:
	if _match_finished:
		return
	if not NetworkCommandSync.has_disconnected_peers():
		_disconnect_label.text = "All players ready"
		_disconnect_timer_label.hide()
		if multiplayer.is_server():
			_disconnect_resume_button.show()
			_disconnect_resume_button.grab_focus()


func _on_reconnect_timer_expired(_peer_id: int) -> void:
	if _match_finished:
		return
	_disconnect_active = false
	_disconnect_panel.hide()
	# Match.gd handles the unit reassignment via the same signal


func _on_disconnect_resume_pressed() -> void:
	_disconnect_active = false
	_disconnect_panel.hide()
	_disconnect_resume_button.hide()
	_disconnect_timer_label.show()
	hide_overlay()
	get_tree().paused = false


func _on_disconnect_leave_pressed() -> void:
	MatchSignals.match_aborted.emit()
	NetworkCommandSync.disconnect_game(true)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")
