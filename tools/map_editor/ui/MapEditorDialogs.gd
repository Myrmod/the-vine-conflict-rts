class_name MapEditorDialogs

extends Control

## Helper class for managing file dialogs in the map editor

signal map_saved(path: String)
signal map_loaded(path: String)
signal map_exported(path: String)

var _save_dialog: FileDialog
var _load_dialog: FileDialog
var _export_dialog: FileDialog


func _ready():
	_setup_dialogs()


func _setup_dialogs():
	"""Create and configure file dialogs"""
	# Save dialog
	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_RESOURCES
	_save_dialog.add_filter("*.tres", "Map Resource")
	_save_dialog.title = "Save Map"
	_save_dialog.file_selected.connect(_on_save_file_selected)
	add_child(_save_dialog)

	# Load dialog
	_load_dialog = FileDialog.new()
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.access = FileDialog.ACCESS_RESOURCES
	_load_dialog.add_filter("*.tres", "Map Resource")
	_load_dialog.title = "Load Map"
	_load_dialog.file_selected.connect(_on_load_file_selected)
	add_child(_load_dialog)

	# Export dialog
	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_RESOURCES
	_export_dialog.add_filter("*.tres", "Runtime Map Resource")
	_export_dialog.title = "Export Map"
	_export_dialog.file_selected.connect(_on_export_file_selected)
	add_child(_export_dialog)


func show_save_dialog():
	"""Show the save dialog"""
	_save_dialog.popup_centered(Vector2i(800, 600))


func show_load_dialog():
	"""Show the load dialog"""
	_load_dialog.popup_centered(Vector2i(800, 600))


func show_export_dialog():
	"""Show the export dialog"""
	_export_dialog.popup_centered(Vector2i(800, 600))


func _on_save_file_selected(path: String):
	map_saved.emit(path)


func _on_load_file_selected(path: String):
	map_loaded.emit(path)


func _on_export_file_selected(path: String):
	map_exported.emit(path)
