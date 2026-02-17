class_name EntityPalette

extends TabContainer

## Automatically generates and manages the entity palette for the map editor

signal entity_selected(scene_path: String)

# Environment Container
@onready var objects_container = $Environment/EnvironmentPalette/ObjectsContainer/VBoxContainer

# Faction container
@onready var neutral_container = $Factions/EntityPalette/NeutralContainer/VBoxContainer
@onready var the_amuns_container = $Factions/EntityPalette/TheAmunsContainer/VBoxContainer


func _ready():
	populate_objects()
	populate_neutral()
	populate_the_amuns()


func populate_objects():
	if not objects_container:
		push_error("The objects_container not found in the scene tree.")
		return

	# Clear existing buttons if reloading
	for c in objects_container.get_children():
		c.queue_free()

	populate_container_with_scenes("res://source/decorations/", objects_container)


func populate_neutral():
	if not neutral_container:
		push_error("The neutral_container not found in the scene tree.")
		return

	# Clear existing buttons if reloading
	for c in neutral_container.get_children():
		c.queue_free()

	populate_container_with_scenes("res://source/factions/neutral/structures/", neutral_container)


func populate_the_amuns():
	if not the_amuns_container:
		push_error("The the_amuns_container not found in the scene tree.")
		return

	# Clear existing buttons if reloading
	for c in the_amuns_container.get_children():
		c.queue_free()

	populate_container_with_scenes(
		"res://source/factions/the_amuns/structures/", the_amuns_container
	)
	populate_container_with_scenes("res://source/factions/the_amuns/units/", the_amuns_container)


func populate_container_with_scenes(scenes_path: String, container: Node):
	var dir := DirAccess.open(scenes_path)
	if dir == null:
		push_error("Cannot open path: " + scenes_path)
		return

	dir.list_dir_begin()

	while true:
		var file_name = dir.get_next()
		if file_name == "":
			break

		if dir.current_is_dir():
			continue

		if file_name.ends_with(".tscn"):
			create_scene_button(file_name, scenes_path, container)

	dir.list_dir_end()


func create_scene_button(file_name: String, scenes_path: String, container: Node):
	var btn := Button.new()

	var scene_path = scenes_path + file_name
	btn.text = file_name.get_basename()
	btn.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)

	btn.pressed.connect(_on_scene_button_pressed.bind(scene_path))

	container.add_child(btn)


func _on_scene_button_pressed(scene_path: String):
	print("Scene button pressed: ", scene_path)
	entity_selected.emit(scene_path)
