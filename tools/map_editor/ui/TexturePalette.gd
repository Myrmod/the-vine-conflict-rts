class_name TexturePalette

extends VBoxContainer

## Automatically generates and manages the texture palette for the map editor

signal texture_selected(texture: TerrainType)
signal texture_selected_as_base_layer(texture: TerrainType)

@export var terrain_library: TerrainLibrary

var base_layer_button: TextureButton = null

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

	for t in terrain_library.terrain_types:
		create_scene_button(t, texture_container)


func create_scene_button(texture: TerrainType, container: Node):
	var btn := TextureButton.new()

	btn.texture_normal = texture.preview
	btn.ignore_texture_size = true
	btn.stretch_mode = btn.StretchMode.STRETCH_SCALE
	btn.custom_minimum_size = Vector2(138, 138)
	btn.gui_input.connect(_on_TextureButton_gui_input.bind(texture, btn))

	btn.pressed.connect(_on_scene_button_pressed.bind(texture))

	container.add_child(btn)


func _on_scene_button_pressed(texture: TerrainType):
	texture_selected.emit(texture)


## sets terrain base layer on right click
func _on_TextureButton_gui_input(event, texture: TerrainType, btn: TextureButton):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# Remove highlight from previous
			if base_layer_button:
				base_layer_button.modulate = Color.WHITE
				if base_layer_button.has_node("BaseLabel"):
					base_layer_button.get_node("BaseLabel").queue_free()

			base_layer_button = btn

			# Add visual feedback
			btn.modulate = Color(1.2, 1.2, 0.7)  # slight yellow tint

			var label := Label.new()
			label.name = "BaseLabel"
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

			texture_selected_as_base_layer.emit(texture)
