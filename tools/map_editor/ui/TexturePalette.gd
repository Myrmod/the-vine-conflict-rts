class_name TexturePalette

extends VBoxContainer

## Automatically generates and manages the texture palette for the map editor

signal texture_selected(texture: TerrainType)
signal texture_selected_as_base_layer(texture: TerrainType)

# Faction container
@onready var texture_container = $GridContainer


func _ready():
	populate_textures()


func populate_textures():
	if not texture_container:
		push_error("The texture_container not found in the scene tree.")
		return

	# Clear existing buttons if reloading
	for c in texture_container.get_children():
		c.queue_free()

	var i = 0
	for t in Globals.terrain_types:
		t.id = i
		if i == 0:
			create_scene_button(t, texture_container, true)
		else:
			create_scene_button(t, texture_container)
		i += 1


func create_scene_button(texture: TerrainType, container: Node, _is_first = false):
	var btn := TextureButton.new()

	btn.texture_normal = texture.preview
	btn.ignore_texture_size = true
	btn.stretch_mode = btn.StretchMode.STRETCH_SCALE
	btn.custom_minimum_size = Vector2(138, 138)
	btn.gui_input.connect(_on_TextureButton_gui_input.bind(texture, btn))

	btn.pressed.connect(_on_scene_button_pressed.bind(texture, btn))

	if _is_first:
		_add_base_label_to_button(btn)
		# we have to wait a little since this is a child of MapEditor
		call_deferred("_emit_base_layer", texture)

	container.add_child(btn)


func _on_scene_button_pressed(texture: TerrainType, btn: TextureButton):
	for button in texture_container.get_children():
		button.modulate = Color.WHITE
	btn.modulate = Color(1.2, 1.2, 0.7)  # slight yellow tint
	texture_selected.emit(texture)


## sets terrain base layer on right click
func _on_TextureButton_gui_input(event, texture: TerrainType, btn: TextureButton):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# Remove highlight from all buttons
			for button in texture_container.get_children():
				if button.get_children().size():
					for button_child in button.get_children():
						button.remove_child(button_child)

			_add_base_label_to_button(btn)

			texture_selected_as_base_layer.emit(texture)


func _add_base_label_to_button(btn: TextureButton):
	# Add visual feedback

	var label := Label.new()
	label.text = "BASE"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH

	# shadow settings
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)

	btn.add_child(label)


func _emit_base_layer(texture):
	texture_selected_as_base_layer.emit(texture)
