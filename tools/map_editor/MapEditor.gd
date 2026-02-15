extends Control

## Main Map Editor Controller
## Provides UI and tools for creating and editing RTS maps

const MapResource = preload("res://tools/map_editor/MapResource.gd")
const MapRuntimeResource = preload("res://tools/map_editor/MapRuntimeResource.gd")
const SymmetrySystem = preload("res://tools/map_editor/SymmetrySystem.gd")
const CommandStack = preload("res://tools/map_editor/commands/CommandStack.gd")
const PaintCollisionBrush = preload("res://tools/map_editor/brushes/PaintCollisionBrush.gd")
const EraseBrush = preload("res://tools/map_editor/brushes/EraseBrush.gd")
const StructureBrush = preload("res://tools/map_editor/brushes/StructureBrush.gd")
const UnitBrush = preload("res://tools/map_editor/brushes/UnitBrush.gd")
const PaintCollisionCommand = preload("res://tools/map_editor/commands/PaintCollisionCommand.gd")

enum ViewMode {
	GAME_VIEW,
	COLLISION_VIEW
}

enum BrushType {
	PAINT_COLLISION,
	ERASE,
	PLACE_STRUCTURE,
	PLACE_UNIT
}

# Core systems
var current_map: MapResource
var symmetry_system: SymmetrySystem
var command_stack: CommandStack
var current_brush
var current_brush_type: BrushType = BrushType.PAINT_COLLISION

# Editor state
var view_mode: ViewMode = ViewMode.GAME_VIEW
var current_player: int = 0
var is_painting: bool = false
var grid_visible: bool = true

# UI references (will be set up in scene)
var viewport_container: SubViewportContainer
var editor_viewport: SubViewport
var viewport_3d: Node3D
var toolbar_container: HBoxContainer
var palette_container: VBoxContainer
var status_label: Label

# Visual layers
var visual_layer: Node3D
var collision_layer: Node3D
var grid_layer: Node3D


func _ready():
	# Initialize core systems
	current_map = MapResource.new()
	symmetry_system = SymmetrySystem.new(current_map.size)
	command_stack = CommandStack.new()
	
	# Set up initial brush
	_create_brush(BrushType.PAINT_COLLISION)
	
	# Set up UI
	_setup_ui()
	
	# Set up 3D scene
	_setup_3d_scene()
	
	print("Map Editor initialized")


func _setup_ui():
	"""Set up the editor UI elements"""
	# This will be expanded when we create the actual scene
	# For now, just create minimal structure
	pass


func _setup_3d_scene():
	"""Set up the 3D viewport and visual layers"""
	# Create viewport structure
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "ViewportContainer"
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(viewport_container)
	
	editor_viewport = SubViewport.new()
	editor_viewport.name = "EditorViewport"
	editor_viewport.size = Vector2i(1024, 768)
	viewport_container.add_child(editor_viewport)
	
	viewport_3d = Node3D.new()
	viewport_3d.name = "Viewport3D"
	editor_viewport.add_child(viewport_3d)
	
	# Create visual layers
	visual_layer = Node3D.new()
	visual_layer.name = "VisualLayer"
	viewport_3d.add_child(visual_layer)
	
	collision_layer = Node3D.new()
	collision_layer.name = "CollisionLayer"
	collision_layer.visible = false
	viewport_3d.add_child(collision_layer)
	
	grid_layer = Node3D.new()
	grid_layer.name = "GridLayer"
	viewport_3d.add_child(grid_layer)
	
	# Add camera
	var camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(25, 30, 25)
	camera.rotation_degrees = Vector3(-45, 0, 0)
	viewport_3d.add_child(camera)
	
	# Add directional light
	var light = DirectionalLight3D.new()
	light.name = "Light"
	light.rotation_degrees = Vector3(-45, 30, 0)
	viewport_3d.add_child(light)


func _create_brush(brush_type: BrushType):
	"""Create and set the current brush"""
	current_brush_type = brush_type
	
	match brush_type:
		BrushType.PAINT_COLLISION:
			current_brush = PaintCollisionBrush.new(current_map, symmetry_system, 1)
		BrushType.ERASE:
			current_brush = EraseBrush.new(current_map, symmetry_system)
		BrushType.PLACE_STRUCTURE:
			current_brush = StructureBrush.new(current_map, symmetry_system, "", current_player)
		BrushType.PLACE_UNIT:
			current_brush = UnitBrush.new(current_map, symmetry_system, "", current_player)


func _input(event):
	# Handle keyboard shortcuts
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Z and event.ctrl_pressed:
			if event.shift_pressed:
				redo()
			else:
				undo()
		elif event.keycode == KEY_Y and event.ctrl_pressed:
			redo()


func undo():
	"""Undo the last command"""
	command_stack.undo()
	_refresh_view()


func redo():
	"""Redo the last undone command"""
	command_stack.redo()
	_refresh_view()


func _refresh_view():
	"""Refresh the 3D view to reflect map changes"""
	# This will be implemented to update visual representation
	pass


func set_view_mode(mode: ViewMode):
	"""Toggle between game view and collision view"""
	view_mode = mode
	
	if visual_layer and collision_layer:
		visual_layer.visible = (mode == ViewMode.GAME_VIEW)
		collision_layer.visible = (mode == ViewMode.COLLISION_VIEW)


func set_symmetry_mode(mode: SymmetrySystem.Mode):
	"""Set the symmetry mode for brush operations"""
	symmetry_system.set_mode(mode)


func new_map(size: Vector2i):
	"""Create a new map"""
	current_map = MapResource.new()
	current_map.size = size
	current_map._initialize_collision_grid()
	symmetry_system.set_map_size(size)
	command_stack.clear()
	_refresh_view()


func save_map(path: String):
	"""Save the current map to a file"""
	var errors = current_map.validate()
	if not errors.is_empty():
		push_warning("Map has validation errors: " + str(errors))
	
	var result = ResourceSaver.save(current_map, path)
	if result == OK:
		print("Map saved to: " + path)
	else:
		push_error("Failed to save map: " + str(result))


func load_map(path: String):
	"""Load a map from a file"""
	var loaded_map = ResourceLoader.load(path)
	if loaded_map is MapResource:
		current_map = loaded_map
		symmetry_system.set_map_size(current_map.size)
		command_stack.clear()
		_refresh_view()
		print("Map loaded from: " + path)
	else:
		push_error("Failed to load map or invalid format")


func export_map(path: String):
	"""Export map to runtime format"""
	var runtime_map = MapRuntimeResource.from_editor_map(current_map)
	var errors = runtime_map.validate()
	
	if not errors.is_empty():
		push_warning("Runtime map has validation errors: " + str(errors))
	
	var result = ResourceSaver.save(runtime_map, path)
	if result == OK:
		print("Map exported to: " + path)
	else:
		push_error("Failed to export map: " + str(result))


func _exit_tree():
	# Clean up
	pass
