extends VBoxContainer
class_name EntityPalette

## Automatically generates and manages the entity palette for the map editor
## Populated from UnitConstants for structures and units

signal entity_selected(entity_type: String, scene_path: String)
signal brush_selected(brush_name: String)

const UnitConstants = preload("res://source/match/MatchConstants/Units.gd")

# Palette categories
var _structures_container: VBoxContainer
var _units_container: VBoxContainer
var _brushes_container: VBoxContainer
var _current_selection: Button = null


func _ready():
	_build_palette()


func _build_palette():
	"""Build the palette UI from constants"""
	# Clear existing children
	for child in get_children():
		child.queue_free()
	
	# Add brushes section
	var brushes_label = Label.new()
	brushes_label.text = "Brushes"
	brushes_label.add_theme_font_size_override("font_size", 16)
	add_child(brushes_label)
	
	_brushes_container = VBoxContainer.new()
	add_child(_brushes_container)
	
	_add_brush_button("Paint Collision", "paint_collision")
	_add_brush_button("Erase", "erase")
	
	add_child(HSeparator.new())
	
	# Add structures section
	var structures_label = Label.new()
	structures_label.text = "Structures"
	structures_label.add_theme_font_size_override("font_size", 16)
	add_child(structures_label)
	
	_structures_container = VBoxContainer.new()
	add_child(_structures_container)
	
	_populate_structures()
	
	add_child(HSeparator.new())
	
	# Add units section
	var units_label = Label.new()
	units_label.text = "Units"
	units_label.add_theme_font_size_override("font_size", 16)
	add_child(units_label)
	
	_units_container = VBoxContainer.new()
	add_child(_units_container)
	
	_populate_units()


func _add_brush_button(label: String, brush_name: String):
	"""Add a brush button to the palette"""
	var button = Button.new()
	button.text = label
	button.toggle_mode = true
	button.pressed.connect(func(): _on_brush_button_pressed(button, brush_name))
	_brushes_container.add_child(button)


func _on_brush_button_pressed(button: Button, brush_name: String):
	"""Handle brush button press"""
	_set_current_selection(button)
	brush_selected.emit(brush_name)


func _populate_structures():
	"""Populate structure buttons from UnitConstants"""
	var structure_paths = UnitConstants.STRUCTURE_BLUEPRINTS.keys()
	
	for path in structure_paths:
		var structure_name = path.get_file().get_basename()
		_add_entity_button(_structures_container, structure_name, "structure", path)


func _populate_units():
	"""Populate unit buttons from UnitConstants"""
	var unit_paths = UnitConstants.DEFAULT_PROPERTIES.keys()
	
	for path in unit_paths:
		# Skip structures (they have blueprints)
		if path in UnitConstants.STRUCTURE_BLUEPRINTS:
			continue
		
		var unit_name = path.get_file().get_basename()
		_add_entity_button(_units_container, unit_name, "unit", path)


func _add_entity_button(container: VBoxContainer, label: String, entity_type: String, scene_path: String):
	"""Add an entity button to the specified container"""
	var button = Button.new()
	button.text = label
	button.toggle_mode = true
	button.pressed.connect(func(): _on_entity_button_pressed(button, entity_type, scene_path))
	container.add_child(button)


func _on_entity_button_pressed(button: Button, entity_type: String, scene_path: String):
	"""Handle entity button press"""
	_set_current_selection(button)
	entity_selected.emit(entity_type, scene_path)


func _set_current_selection(button: Button):
	"""Update the current selection highlighting"""
	if _current_selection and _current_selection != button:
		_current_selection.button_pressed = false
	_current_selection = button
