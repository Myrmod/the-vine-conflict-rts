extends CanvasLayer

const LoadingScene = preload("res://source/main-menu/Loading.tscn")

## True when this player initiated the pause via the menu.
var _paused_by_self: bool = false

@onready var _main_panel = find_child("MainPanel")
@onready var _save_panel = find_child("SavePanel")
@onready var _load_panel = find_child("LoadPanel")
@onready var _save_name_edit: LineEdit = find_child("SaveNameEdit")
@onready var _save_list = find_child("SaveList")


func _ready():
	hide()
	_save_panel.hide()
	_load_panel.hide()
	# In multiplayer, hide save/load/restart (only available in singleplayer)
	if NetworkCommandSync.is_active:
		var save_btn = find_child("SaveButton")
		var load_btn = find_child("LoadButton")
		var restart_btn = find_child("RestartButton")
		if save_btn:
			save_btn.hide()
		if load_btn:
			load_btn.hide()
		if restart_btn:
			restart_btn.hide()


func _unhandled_input(event):
	if event.is_action_pressed("toggle_match_menu"):
		_toggle()


func _toggle():
	visible = not visible
	if visible:
		_paused_by_self = true
		get_tree().paused = true
		NetworkCommandSync.broadcast_pause(true)
		_show_main_panel()
	else:
		_paused_by_self = false
		get_tree().paused = false
		NetworkCommandSync.broadcast_pause(false)


func _show_main_panel():
	_main_panel.show()
	_save_panel.hide()
	_load_panel.hide()


func _on_resume_button_pressed():
	_toggle()


func _on_exit_button_pressed():
	MatchSignals.match_aborted.emit()
	await get_tree().create_timer(1.74).timeout
	get_tree().paused = false
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")


# ── SAVE ────────────────────────────────────────────────────────────


func _on_save_button_pressed():
	var match_node = find_parent("Match")
	var default_name := SaveSystem.get_default_save_name(match_node)
	_save_name_edit.text = default_name
	_save_name_edit.select_all()
	_main_panel.hide()
	_save_panel.show()
	_save_name_edit.grab_focus()


func _on_confirm_save_button_pressed():
	var save_name := _save_name_edit.text.strip_edges()
	if save_name.is_empty():
		return
	var err := SaveSystem.save_game(save_name)
	if err == OK:
		_toggle()


func _on_save_name_submitted(_text: String):
	_on_confirm_save_button_pressed()


func _on_save_back_button_pressed():
	_show_main_panel()


# ── LOAD ────────────────────────────────────────────────────────────


func _on_load_button_pressed():
	_save_list.refresh()
	_main_panel.hide()
	_load_panel.show()


func _on_save_selected(path: String):
	var save := SaveSystem.load_game(path)
	if save == null:
		return
	MatchSignals.match_aborted.emit()
	get_tree().paused = false
	var loading = LoadingScene.instantiate()
	loading.match_settings = (SaveSystem._deserialize_settings(save.match_settings_data))
	loading.map_path = save.map_source_path
	loading.save_resource = save
	var old_scene = get_tree().current_scene
	get_tree().root.add_child(loading)
	get_tree().current_scene = loading
	old_scene.queue_free()


func _on_load_back_button_pressed():
	_show_main_panel()


# ── RESTART ─────────────────────────────────────────────────────────


func _on_restart_button_pressed():
	var match_node = find_parent("Match")
	if match_node == null:
		return
	var ms = match_node.settings
	var mp = match_node.map_source_path
	MatchSignals.match_aborted.emit()
	get_tree().paused = false
	var loading = LoadingScene.instantiate()
	loading.match_settings = ms
	loading.map_path = mp
	var old_scene = get_tree().current_scene
	get_tree().root.add_child(loading)
	get_tree().current_scene = loading
	old_scene.queue_free()
