class_name AssetLoader extends Node


static func load_asset(path: String):
	var override_path = "res://assets_overide/" + path
	var default_path = "res://assets/" + path

	if ResourceLoader.exists(override_path):
		return load(override_path)

	return load(default_path)
