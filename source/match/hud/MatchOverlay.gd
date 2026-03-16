extends CanvasLayer

## Overlay for multiplayer notifications (pause, desync) and in-game chat.
## Process mode is ALWAYS so it works while the tree is paused.

const MAX_CHAT_LINES: int = 50
const CHAT_FADE_DELAY: float = 8.0

var _chat_mode: int = 0  # 0 = all, 1 = team
var _chat_visible: bool = false
var _chat_fade_timer: float = 0.0
var _local_team: int = -1

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


func _process(delta: float) -> void:
	if _chat_fade_timer > 0.0:
		_chat_fade_timer -= delta
		if _chat_fade_timer <= 0.0 and not _chat_visible:
			_chat_log.modulate.a = 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
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
