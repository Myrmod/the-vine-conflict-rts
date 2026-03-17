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
	if not SaveSystem.has_save():
		return
	var save := SaveSystem.load_game()
	if save == null:
		return
	MatchSignals.match_aborted.emit()
	get_tree().paused = false
	# Transition to Loading with the save resource
	var loading_scene = load("res://source/main-menu/Loading.tscn")
	var loading = loading_scene.instantiate()
	loading.match_settings = SaveSystem._deserialize_settings(save.match_settings_data)
	loading.map_path = save.map_source_path
	loading.save_resource = save
	var old_scene = get_tree().current_scene
	get_tree().root.add_child(loading)
	get_tree().current_scene = loading
	old_scene.queue_free()


func _on_save_button_pressed():
	var err := SaveSystem.save_game()
	if err == OK:
		_toggle()


func _on_restart_button_pressed():
	print("TODO")
