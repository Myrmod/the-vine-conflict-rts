extends CanvasLayer

## True when this player initiated the pause via the menu.
var _paused_by_self: bool = false


func _ready():
	hide()


func _unhandled_input(event):
	if event.is_action_pressed("toggle_match_menu"):
		_toggle()


func _toggle():
	visible = not visible
	if visible:
		_paused_by_self = true
		get_tree().paused = true
		NetworkCommandSync.broadcast_pause(true)
	else:
		_paused_by_self = false
		get_tree().paused = false
		NetworkCommandSync.broadcast_pause(false)


func _on_resume_button_pressed():
	_toggle()


func _on_exit_button_pressed():
	MatchSignals.match_aborted.emit()
	await get_tree().create_timer(1.74).timeout  # Give voice narrator some time to finish.
	get_tree().paused = false
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")


func _on_load_button_pressed():
	print("TODO")


func _on_save_button_pressed():
	print("TODO")


func _on_restart_button_pressed():
	print("TODO")
