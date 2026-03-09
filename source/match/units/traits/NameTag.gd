extends Node3D

@onready var _unit = get_parent()
@onready var _label: Label3D = find_child("Label3D")


func _ready():
	hide()
	_unit.mouse_entered.connect(_on_mouse_entered)
	_unit.mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered():
	if _unit.unit_name != "":
		_label.text = _unit.unit_name
		show()


func _on_mouse_exited():
	hide()
