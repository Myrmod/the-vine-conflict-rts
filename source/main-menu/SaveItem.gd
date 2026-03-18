extends HBoxContainer

signal load_requested(file_path: String)

@onready var label = $Label
@onready var button = $Button

var save_path: String


func setup(path: String):
	save_path = path
	label.text = path.get_file().get_basename()
	button.pressed.connect(_on_button_pressed)


func _on_button_pressed():
	load_requested.emit(save_path)
