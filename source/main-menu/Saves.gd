extends Control


func _on_back_button_pressed():
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")


func _on_save_selected(path: String):
	var save := SaveSystem.load_game(path)
	if save == null:
		return
	var loading_scene = load("res://source/main-menu/Loading.tscn")
	var loading = loading_scene.instantiate()
	loading.match_settings = (SaveSystem._deserialize_settings(save.match_settings_data))
	loading.map_path = save.map_source_path
	loading.save_resource = save
	get_tree().root.add_child(loading)
	get_tree().current_scene = loading
	queue_free()
