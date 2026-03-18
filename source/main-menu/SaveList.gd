extends VBoxContainer

const SaveItemScene = preload("res://source/main-menu/SaveItem.tscn")

signal save_selected(path: String)


func _ready():
	refresh()


func refresh():
	for child in get_children():
		child.queue_free()

	var saves := SaveSystem.list_saves()
	for path in saves:
		var item = SaveItemScene.instantiate()
		add_child(item)
		item.setup(path)
		item.load_requested.connect(_on_load_requested)


func _on_load_requested(path: String):
	save_selected.emit(path)
