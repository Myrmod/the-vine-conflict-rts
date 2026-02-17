extends Control

## Main Map Editor Controller
## Provides UI and tools for creating and editing RTS maps

const MapResource = preload("res://tools/map_editor/MapResource.gd")
const MapRuntimeResource = preload("res://tools/map_editor/MapRuntimeResource.gd")
const SymmetrySystem = preload("res://tools/map_editor/SymmetrySystem.gd")
const CommandStack = preload("res://tools/map_editor/commands/CommandStack.gd")
const PaintCollisionBrush = preload("res://tools/map_editor/brushes/PaintCollisionBrush.gd")
const EraseBrush = preload("res://tools/map_editor/brushes/EraseBrush.gd")
const EntityBrush = preload("res://tools/map_editor/brushes/EntityBrush.gd")

const PaintCollisionCommand = preload("res://tools/map_editor/commands/PaintCollisionCommand.gd")
const GridRenderer = preload("res://tools/map_editor/GridRenderer.gd")
const CollisionRenderer = preload("res://tools/map_editor/CollisionRenderer.gd")
const MapEditorDialogs = preload("res://tools/map_editor/ui/MapEditorDialogs.gd")

enum ViewMode { GAME_VIEW, COLLISION_VIEW }

enum BrushType { PAINT_COLLISION, ERASE, PLACE_ENTITY }

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
var camera_yaw: float = 0.0
var camera_target: Vector3
var camera_pan_speed: float = 20.0
var camera_zoom_speed: float = 2.0
var camera_min_distance: float = 5.0
var camera_max_distance: float = 80.0
var camera_rotate_sensitivity: float = 0.3
var camera_min_pitch: float = -85.0
var camera_max_pitch: float = -10.0
var is_orbiting: bool = false

# Dialogs
var dialogs: MapEditorDialogs


func _ready():
	# Initialize core systems
	current_map = MapResource.new()
	symmetry_system = SymmetrySystem.new(current_map.size)
	command_stack = CommandStack.new()

	# Set up initial brush
	_create_brush(BrushType.PAINT_COLLISION)

	# Set up dialogs
	_setup_dialogs()

	# Set up UI connections
	print("Setting up UI connections...")
	_setup_ui_connections()

	# Initialize camera target before setting up 3D scene
	camera_target = Vector3(current_map.size.x / 2.0, 0, current_map.size.y / 2.0)

	# Set up 3D scene
	_setup_3d_scene()

	print("Map Editor initialized - Map size: ", current_map.size)


func _setup_dialogs():
	"""Set up file dialogs"""
	dialogs = MapEditorDialogs.new()
	add_child(dialogs)
	dialogs.map_saved.connect(_on_map_saved)
	dialogs.map_loaded.connect(_on_map_loaded)
	dialogs.map_exported.connect(_on_map_exported)


func _on_map_saved(path: String):
	save_map(path)


func _on_map_loaded(path: String):
	load_map(path)


func _on_map_exported(path: String):
	export_map(path)


func _setup_ui_connections():
	"""Set up UI button connections"""
	# Get UI elements from scene
	var toolbar = get_node_or_null("VBoxContainer/Toolbar")
	var palette_select = get_node_or_null("VBoxContainer/MainArea/LeftPalette/PaletteSelect")
	status_label = get_node_or_null("VBoxContainer/StatusBar/StatusLabel")

	print("Setting up UI connections - Toolbar: ", toolbar, " PaletteSelect: ", palette_select)
	# Connect entity palette signals
	if palette_select:
		palette_select.entity_selected.connect(_on_palette_entity_selected)

	if toolbar:
		# Setup file menu
		var file_menu = toolbar.get_node_or_null("FileMenu")
		if file_menu:
			var popup = file_menu.get_popup()
			popup.clear()
			popup.add_item("New Map", 0)
			popup.add_item("Load Map", 1)
			popup.add_item("Save Map", 2)
			popup.add_separator()
			popup.add_item("Export for Runtime", 3)
			popup.id_pressed.connect(_on_file_menu_item_selected)

		var symmetry_option = toolbar.get_node_or_null("SymmetryOption")
		if symmetry_option:
			symmetry_option.clear()
			symmetry_option.add_item("None", SymmetrySystem.Mode.NONE)
			symmetry_option.add_item("Mirror X", SymmetrySystem.Mode.MIRROR_X)
			symmetry_option.add_item("Mirror Y", SymmetrySystem.Mode.MIRROR_Y)
			symmetry_option.add_item("Diagonal", SymmetrySystem.Mode.DIAGONAL)
			symmetry_option.add_item("Quad", SymmetrySystem.Mode.QUAD)
			symmetry_option.item_selected.connect(_on_symmetry_changed)


func _on_file_menu_item_selected(id: int):
	"""Handle file menu item selection"""
	match id:
		0:  # New Map
			new_map(Vector2i(50, 50))
			if status_label:
				status_label.text = "Created new map"
		1:  # Load Map
			dialogs.show_load_dialog()
		2:  # Save Map
			dialogs.show_save_dialog()
		3:  # Export
			dialogs.show_export_dialog()


func _on_palette_brush_selected(brush_name: String):
	"""Handle brush selection from palette"""
	match brush_name:
		"paint_collision":
			_create_brush(BrushType.PAINT_COLLISION)
		"erase":
			_create_brush(BrushType.ERASE)


func _on_palette_entity_selected(scene_path: String):
	print("Entity selected from palette: ", scene_path)
	"""Handle entity selection from palette"""
	_create_brush(BrushType.PLACE_ENTITY)
	if current_brush is EntityBrush:
		current_brush.set_entity(scene_path)

	# Update brush info
	var brush_info = get_node_or_null("VBoxContainer/Toolbar/BrushInfo")
	print("Updating brush info label: ", brush_info)
	if brush_info and current_brush:
		brush_info.text = current_brush.get_brush_name()


func _setup_3d_scene():
	"""Set up the 3D viewport and visual layers"""
	# Get viewport container from scene or create it
	var viewport_area = get_node_or_null("VBoxContainer/MainArea/ViewportArea")

	if not viewport_area:
		return

	# Create viewport entity
	viewport_container = $VBoxContainer/MainArea/ViewportArea/MarginContainer/ViewportContainer

	editor_viewport = $VBoxContainer/MainArea/ViewportArea/MarginContainer/ViewportContainer/EditorViewport
	viewport_3d = $VBoxContainer/MainArea/ViewportArea/MarginContainer/ViewportContainer/EditorViewport/Viewport3D
	grid_layer = $VBoxContainer/MainArea/ViewportArea/MarginContainer/ViewportContainer/EditorViewport/GridLayer
	visual_layer = $VBoxContainer/MainArea/ViewportArea/MarginContainer/ViewportContainer/EditorViewport/VisualLayer
	collision_layer = $VBoxContainer/MainArea/ViewportArea/MarginContainer/ViewportContainer/EditorViewport/CollisionLayer

	# hitbox for raycasting (invisible)
	var ground_body := StaticBody3D.new()
	ground_body.name = "PaintGround"

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()

	# Cover full map area
	box.size = Vector3(current_map.size.x, 1.0, current_map.size.y)

	shape.shape = box
	shape.position = Vector3(current_map.size.x * 0.5, -0.5, current_map.size.y * 0.5)

	ground_body.add_child(shape)
	viewport_3d.add_child(ground_body)

	# Create renderers
	grid_renderer = GridRenderer.new()
	grid_renderer.grid_size = current_map.size
	grid_layer.add_child(grid_renderer)

	collision_renderer = CollisionRenderer.new(current_map)
	collision_layer.add_child(collision_renderer)

	# Add camera
	camera = Camera3D.new()
	camera.name = "Camera"
	viewport_3d.add_child(camera)
	_update_camera_position()

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
	"""Update camera position based on current pitch, yaw and distance"""
	if not camera:
		return

	var pitch_rad = deg_to_rad(camera_angle)
	var yaw_rad = deg_to_rad(camera_yaw)
	var offset = Vector3(
		camera_distance * cos(pitch_rad) * sin(yaw_rad),
		camera_distance * sin(abs(pitch_rad)),
		camera_distance * cos(pitch_rad) * cos(yaw_rad)
	)
	camera.position = camera_target + offset
	camera.look_at(camera_target, Vector3.UP)


func _reset_camera():
	"""Reset camera to default centered position"""
	camera_target = Vector3(current_map.size.x / 2.0, 0, current_map.size.y / 2.0)
	camera_distance = 30.0
	camera_angle = -45.0
	camera_yaw = 0.0
	_update_camera_position()


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
		BrushType.PLACE_ENTITY:
			current_brush = EntityBrush.new(current_map, symmetry_system, "", current_player)

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
	print("Brush applied at positions: ", positions)
	"""Handle brush application - update visuals"""
	if collision_renderer and current_brush_type == BrushType.PAINT_COLLISION:
		collision_renderer.update_cells(positions)


func _process(delta):
	# Camera panning with WASD / arrow keys
	var pan_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan_dir.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan_dir.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan_dir.x += 1

	if pan_dir != Vector3.ZERO:
		camera_target += pan_dir.normalized() * camera_pan_speed * delta
		# Clamp to map bounds with some margin
		camera_target.x = clampf(camera_target.x, -5.0, current_map.size.x + 5.0)
		camera_target.z = clampf(camera_target.z, -5.0, current_map.size.y + 5.0)
		_update_camera_position()


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
		elif event.keycode == KEY_HOME:
			# Reset camera to default
			_reset_camera()
		elif event.keycode == KEY_V:
			# Toggle view mode
			if view_mode == ViewMode.GAME_VIEW:
				set_view_mode(ViewMode.COLLISION_VIEW)
			else:
				set_view_mode(ViewMode.GAME_VIEW)

	# Handle mouse scroll for zoom and middle mouse for orbit
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = maxf(camera_min_distance, camera_distance - camera_zoom_speed)
			_update_camera_position()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = minf(camera_max_distance, camera_distance + camera_zoom_speed)
			_update_camera_position()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			is_painting = event.pressed
			if event.pressed:
				_try_paint_at_mouse(event.position)

	elif event is InputEventMouseMotion:
		if is_orbiting:
			camera_yaw += event.relative.x * camera_rotate_sensitivity
			camera_angle -= event.relative.y * camera_rotate_sensitivity
			camera_angle = clampf(camera_angle, camera_min_pitch, camera_max_pitch)
			_update_camera_position()
		elif is_painting:
			_try_paint_at_mouse(event.position)


func _try_paint_at_mouse(mouse_pos: Vector2):
	if not current_brush:
		return
	if not editor_viewport or not camera:
		return

	# Convert global mouse → SubViewport local
	print("Mouse position: ", mouse_pos)
	var rect = viewport_container.get_global_rect()
	if not rect.has_point(mouse_pos):
		return  # mouse not over viewport

	var local_pos = mouse_pos - rect.position

	# Build ray from editor camera
	var ray_origin = camera.project_ray_origin(local_pos)
	var ray_dir = camera.project_ray_normal(local_pos)
	var ray_end = ray_origin + ray_dir * 1000.0

	var space_state = editor_viewport.world_3d.direct_space_state

	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_bodies = true
	query.collide_with_areas = true

	print("Casting ray from ", ray_origin, " in direction ", ray_dir)
	var hit = space_state.intersect_ray(query)
	if hit.is_empty():
		print("No hit detected for raycast")
		return

	var hit_pos: Vector3 = hit.position

	var grid_pos = _world_to_grid(hit_pos)

	current_brush.apply(grid_pos)


func _world_to_grid(p: Vector3) -> Vector2i:
	var s = FeatureFlags.grid_cell_size
	return Vector2i(floor(p.x / s), floor(p.z / s))


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
	else:
		print("Warning: Visual or collision layer not found for view mode toggle")


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
		if status_label:
			status_label.text = "Validation errors: " + str(errors[0])

	var result = ResourceSaver.save(current_map, path)
	if result == OK:
		print("Map saved to: " + path)
		if status_label:
			status_label.text = "Map saved successfully"
	else:
		push_error("Failed to save map: " + str(result))
		if status_label:
			status_label.text = "Failed to save map"


func load_map(path: String):
	"""Load a map from a file"""
	var loaded_map = ResourceLoader.load(path)
	if loaded_map is MapResource:
		current_map = loaded_map
		symmetry_system.set_map_size(current_map.size)
		command_stack.clear()
		_refresh_view()
		print("Map loaded from: " + path)
		if status_label:
			status_label.text = "Map loaded: " + path.get_file()
	else:
		push_error("Failed to load map or invalid format")
		if status_label:
			status_label.text = "Failed to load map"


func export_map(path: String):
	"""Export map to runtime format"""
	var runtime_map = MapRuntimeResource.from_editor_map(current_map)
	var errors = runtime_map.validate()

	if not errors.is_empty():
		push_warning("Runtime map has validation errors: " + str(errors))
		if status_label:
			status_label.text = "Validation errors: " + str(errors[0])

	var result = ResourceSaver.save(runtime_map, path)
	if result == OK:
		print("Map exported to: " + path)
		if status_label:
			status_label.text = "Map exported successfully"
	else:
		push_error("Failed to export map: " + str(result))
		if status_label:
			status_label.text = "Failed to export map"


func _exit_tree():
	# Clean up
	pass


func _on_back_button_pressed():
	"""Return to main menu"""
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")
