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
const GridRenderer = preload("res://tools/map_editor/GridRenderer.gd")
const CollisionRenderer = preload("res://tools/map_editor/CollisionRenderer.gd")

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

# Renderers
var grid_renderer: GridRenderer
var collision_renderer: CollisionRenderer

# Camera control
var camera: Camera3D
var camera_distance: float = 30.0
var camera_angle: float = -45.0
var camera_target: Vector3


func _ready():
	# Initialize core systems
	current_map = MapResource.new()
	symmetry_system = SymmetrySystem.new(current_map.size)
	command_stack = CommandStack.new()
	
	# Set up initial brush
	_create_brush(BrushType.PAINT_COLLISION)
	
	# Set up UI connections
	_setup_ui_connections()
	
	# Set up 3D scene
	_setup_3d_scene()
	
	# Initialize camera target
	camera_target = Vector3(current_map.size.x / 2.0, 0, current_map.size.y / 2.0)
	
	print("Map Editor initialized - Map size: ", current_map.size)


func _setup_ui_connections():
	"""Set up UI button connections"""
	# Get UI elements from scene
	var toolbar = get_node_or_null("VBoxContainer/Toolbar")
	var entity_palette = get_node_or_null("VBoxContainer/MainArea/LeftPalette/PaletteScroll/EntityPalette")
	status_label = get_node_or_null("VBoxContainer/StatusBar/StatusLabel")
	
	# Connect entity palette signals
	if entity_palette:
		entity_palette.brush_selected.connect(_on_palette_brush_selected)
		entity_palette.entity_selected.connect(_on_palette_entity_selected)
	
	if toolbar:
		var symmetry_option = toolbar.get_node_or_null("SymmetryOption")
		if symmetry_option:
			symmetry_option.clear()
			symmetry_option.add_item("None", SymmetrySystem.Mode.NONE)
			symmetry_option.add_item("Mirror X", SymmetrySystem.Mode.MIRROR_X)
			symmetry_option.add_item("Mirror Y", SymmetrySystem.Mode.MIRROR_Y)
			symmetry_option.add_item("Diagonal", SymmetrySystem.Mode.DIAGONAL)
			symmetry_option.add_item("Quad", SymmetrySystem.Mode.QUAD)
			symmetry_option.item_selected.connect(_on_symmetry_changed)


func _on_palette_brush_selected(brush_name: String):
	"""Handle brush selection from palette"""
	match brush_name:
		"paint_collision":
			_create_brush(BrushType.PAINT_COLLISION)
		"erase":
			_create_brush(BrushType.ERASE)


func _on_palette_entity_selected(entity_type: String, scene_path: String):
	"""Handle entity selection from palette"""
	match entity_type:
		"structure":
			_create_brush(BrushType.PLACE_STRUCTURE)
			if current_brush is StructureBrush:
				current_brush.set_structure(scene_path)
		"unit":
			_create_brush(BrushType.PLACE_UNIT)
			if current_brush is UnitBrush:
				current_brush.set_unit(scene_path)
	
	# Update brush info
	var brush_info = get_node_or_null("VBoxContainer/Toolbar/BrushInfo")
	if brush_info and current_brush:
		brush_info.text = current_brush.get_brush_name()


func _setup_3d_scene():
	"""Set up the 3D viewport and visual layers"""
	# Get viewport container from scene or create it
	var main_area = get_node_or_null("VBoxContainer/MainArea")
	var viewport_area = get_node_or_null("VBoxContainer/MainArea/ViewportArea")
	
	if not viewport_area:
		return
	
	# Create viewport structure
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "ViewportContainer"
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var margin = viewport_area.get_node_or_null("MarginContainer")
	if margin:
		margin.add_child(viewport_container)
	else:
		viewport_area.add_child(viewport_container)
	
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
	
	# Create renderers
	grid_renderer = GridRenderer.new()
	grid_renderer.grid_size = current_map.size
	grid_layer.add_child(grid_renderer)
	
	collision_renderer = CollisionRenderer.new(current_map)
	collision_layer.add_child(collision_renderer)
	
	# Add camera
	camera = Camera3D.new()
	camera.name = "Camera"
	_update_camera_position()
	viewport_3d.add_child(camera)
	
	# Add directional light
	var light = DirectionalLight3D.new()
	light.name = "Light"
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.light_energy = 0.8
	viewport_3d.add_child(light)
	
	# Add ambient light
	var env = Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.5)
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	viewport_3d.add_child(world_env)


func _update_camera_position():
	"""Update camera position based on current angle and distance"""
	if not camera:
		return
	
	var angle_rad = deg_to_rad(camera_angle)
	var offset = Vector3(0, camera_distance * sin(abs(angle_rad)), camera_distance * cos(angle_rad))
	camera.position = camera_target + offset
	camera.look_at(camera_target, Vector3.UP)


func _on_symmetry_changed(index: int):
	"""Handle symmetry mode change"""
	var mode = index as SymmetrySystem.Mode
	set_symmetry_mode(mode)
	if status_label:
		status_label.text = "Symmetry: " + symmetry_system.get_mode_name(mode)


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
	
	# Connect brush signals
	if current_brush and current_brush.brush_applied.is_connected(_on_brush_applied):
		current_brush.brush_applied.disconnect(_on_brush_applied)
	if current_brush:
		current_brush.brush_applied.connect(_on_brush_applied)
	
	# Update UI
	var brush_info = get_node_or_null("VBoxContainer/Toolbar/BrushInfo")
	if brush_info and current_brush:
		brush_info.text = current_brush.get_brush_name()


func _on_brush_applied(positions: Array[Vector2i]):
	"""Handle brush application - update visuals"""
	if collision_renderer and current_brush_type == BrushType.PAINT_COLLISION:
		collision_renderer.update_cells(positions)


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
		elif event.keycode == KEY_V:
			# Toggle view mode
			if view_mode == ViewMode.GAME_VIEW:
				set_view_mode(ViewMode.COLLISION_VIEW)
			else:
				set_view_mode(ViewMode.GAME_VIEW)
	
	# Handle mouse input in viewport
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_painting = event.pressed
			if event.pressed:
				_try_paint_at_mouse(event.position)
	
	elif event is InputEventMouseMotion and is_painting:
		_try_paint_at_mouse(event.position)


func _try_paint_at_mouse(mouse_pos: Vector2):
	"""Try to paint at the given mouse position"""
	if not current_brush or not viewport_container:
		return
	
	# Convert screen position to viewport position
	var viewport_rect = viewport_container.get_global_rect()
	var local_pos = mouse_pos - viewport_rect.position
	
	# For now, we need proper raycasting from viewport
	# This is a placeholder - proper implementation would use camera raycasting
	# to convert 2D mouse position to 3D grid position
	pass


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
	if collision_renderer:
		collision_renderer.refresh()


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


func _on_back_button_pressed():
	"""Return to main menu"""
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")
