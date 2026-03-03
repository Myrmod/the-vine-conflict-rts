extends Control

## Main Map Editor Controller
## Provides UI and tools for creating and editing RTS maps

enum ViewMode { GAME_VIEW, COLLISION_VIEW }

enum BrushType {
	PAINT_COLLISION, ERASE, PLACE_ENTITY, PAINT_TEXTURE, PLACE_SPAWN, PAINT_HEIGHT, PAINT_SLOPE
}

# Core systems
var current_map: MapResource
var symmetry_system: SymmetrySystem
var command_stack: CommandStack
var terrain_system: TerrainSystem
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
var editor_cursor: EditorCursor
# Entity preview nodes for editor visualization
var entity_preview_nodes := {}
# Spawn point preview nodes
var spawn_preview_nodes: Array[Node3D] = []

# Camera control – orthogonal isometric to match in-game camera
var camera: Camera3D
var camera_angle: float = -30.0  # fixed pitch matching IsometricCamera3D
var camera_yaw: float = 0.0
var camera_target: Vector3
var camera_pan_speed: float = 20.0
var camera_zoom_speed: float = 1.0  # orthogonal size step
var camera_size: float = 15.0  # orthogonal size (zoom level)
var camera_size_min: float = 3.0
var camera_size_max: float = 40.0
var camera_rotate_sensitivity: float = 0.3
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
	_setup_ui_connections()

	# Initialize camera target before setting up 3D scene
	camera_target = Vector3(current_map.size.x / 2.0, 0, current_map.size.y / 2.0)

	# Set up 3D scene
	_setup_3d_scene()


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
	var texture_select = get_node_or_null(
		"VBoxContainer/MainArea/LeftPalette/PaletteSelect/Textures/TexturePalette"
	)
	status_label = get_node_or_null("VBoxContainer/StatusBar/StatusLabel")

	# Connect entity palette signals
	if palette_select:
		palette_select.entity_selected.connect(_on_palette_entity_selected)
		palette_select.spawn_selected.connect(_on_palette_spawn_selected)
		palette_select.height_level_selected.connect(_on_palette_height_selected)
		palette_select.slope_selected.connect(_on_palette_slope_selected)
		palette_select.water_slope_selected.connect(_on_palette_water_slope_selected)
		palette_select.collision_selected.connect(_on_palette_collision_selected)
		palette_select.slope_angle_changed.connect(_on_palette_slope_angle_changed)
	# Connect texture palette signals
	if texture_select:
		texture_select.texture_selected.connect(_on_palette_texture_selected)
		texture_select.texture_selected_as_base_layer.connect(
			_on_palette_texture_selected_as_base_layer
		)

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

		var view_menu = toolbar.get_node_or_null("ViewMenu")
		if view_menu:
			var popup = view_menu.get_popup()
			popup.id_pressed.connect(_on_view_menu_item_selected.bind(popup))

	# Brush settings
	var brush_settings = get_node_or_null("VBoxContainer/MainArea/LeftPalette/Brushsettings")
	if brush_settings:
		var brush_form = brush_settings.get_node_or_null("MarginContainer/VBoxContainer/BrushForm")
		var brush_size_spin = brush_settings.get_node_or_null(
			"MarginContainer/VBoxContainer/BrushSize"
		)

		if brush_form:
			brush_form.item_selected.connect(_on_brush_form_changed)
		if brush_size_spin:
			brush_size_spin.min_value = 0
			brush_size_spin.max_value = 10
			brush_size_spin.step = 1
			brush_size_spin.value = 1
			brush_size_spin.value_changed.connect(_on_brush_size_changed)


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


# TODO: this needs some rework so that we dont have duplicate code with the keyboard shortcuts
func _on_view_menu_item_selected(id: int, _popup):
	"""Handle view menu item selection"""
	match id:
		0:
			_toggle_view_mode()


func _toggle_view_mode():
	# Toggle view mode
	if view_mode == ViewMode.GAME_VIEW:
		set_view_mode(ViewMode.COLLISION_VIEW)
	else:
		set_view_mode(ViewMode.GAME_VIEW)


func _on_palette_entity_selected(scene_path: String):
	"""Handle entity selection from palette"""
	_create_brush(BrushType.PLACE_ENTITY)
	if current_brush is EntityBrush:
		current_brush.set_entity(scene_path)

	# Update brush info
	var brush_info = get_node_or_null("VBoxContainer/Toolbar/BrushInfo")
	if brush_info and current_brush:
		brush_info.text = current_brush.get_brush_name()


func _on_palette_spawn_selected():
	"""Handle spawn point tool selection from palette"""
	_create_brush(BrushType.PLACE_SPAWN)

	var brush_info = get_node_or_null("VBoxContainer/Toolbar/BrushInfo")
	if brush_info and current_brush:
		brush_info.text = current_brush.get_brush_name()


func _on_palette_height_selected(level: int):
	"""Handle height level selection from palette (-1=water, 0=ground, 1=high)"""
	_create_brush(BrushType.PAINT_HEIGHT)
	if current_brush is HeightBrush:
		current_brush.set_level(level as Enums.HeightLevel)

	var brush_info = get_node_or_null("VBoxContainer/Toolbar/BrushInfo")
	if brush_info and current_brush:
		brush_info.text = current_brush.get_brush_name()


func _on_palette_slope_selected() -> void:
	"""Handle slope tool selection from palette"""
	_create_brush(BrushType.PAINT_SLOPE)

	var brush_info: Label = get_node_or_null("VBoxContainer/Toolbar/BrushInfo")
	if brush_info and current_brush:
		brush_info.text = current_brush.get_brush_name()


func _on_palette_water_slope_selected() -> void:
	"""Handle water slope tool selection from palette"""
	_create_brush(BrushType.PAINT_SLOPE)
	if current_brush is SlopeBrush:
		current_brush.is_water_slope = true

	var brush_info: Label = get_node_or_null("VBoxContainer/Toolbar/BrushInfo")
	if brush_info and current_brush:
		brush_info.text = current_brush.get_brush_name()


func _on_palette_collision_selected(value: int) -> void:
	"""Handle collision brush selection from Environment palette"""
	_create_brush(BrushType.PAINT_COLLISION)
	if current_brush is PaintCollisionBrush:
		current_brush.paint_value = value

	var brush_info: Label = get_node_or_null("VBoxContainer/Toolbar/BrushInfo")
	if brush_info and current_brush:
		brush_info.text = current_brush.get_brush_name()


func _on_palette_slope_angle_changed(angle: float) -> void:
	"""Handle slope angle change from palette"""
	if current_map:
		current_map.slope_angle = angle
		# Refresh collision view if visible
		if collision_renderer and view_mode == ViewMode.COLLISION_VIEW:
			collision_renderer.refresh()
	if status_label:
		status_label.text = "Slope angle: %d°" % int(angle)


func _on_palette_texture_selected_as_base_layer(terrain: TerrainType):
	terrain_system.apply_base_layer(terrain)


func _on_palette_texture_selected(terrain: TerrainType):
	"""Handle entity selection from palette"""
	_create_brush(BrushType.PAINT_TEXTURE)
	current_brush.set_texture(terrain)

	# Update brush info
	var brush_info = get_node_or_null("VBoxContainer/Toolbar/BrushInfo")

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

	editor_viewport = viewport_container.get_node("EditorViewport")
	viewport_3d = editor_viewport.get_node("Viewport3D")
	grid_layer = editor_viewport.get_node("GridLayer")
	visual_layer = editor_viewport.get_node("VisualLayer")
	terrain_system = visual_layer.get_node("TerrainSystem")
	collision_layer = editor_viewport.get_node("CollisionLayer")

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

	# Brush cursor
	editor_cursor = EditorCursor.new()
	viewport_3d.add_child(editor_cursor)

	# Add camera – orthogonal isometric like the in-game camera
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = camera_size
	viewport_3d.add_child(camera)
	_update_camera_position()

	# The scene already has a DirectionalLight3D ("Sun") and an
	# Environment configured in the .tscn — no need to create them here.

	# setup TerrainSystem
	terrain_system.set_map(current_map)
	# Example: initialize textures or heights
	# terrain_system.setup_textures(current_map.texture_data)
	# terrain_system.setup_heights(current_map.height_data)


func _update_camera_position():
	"""Update camera position based on current pitch, yaw and orthogonal size.
	Mimics the in-game IsometricCamera3D: fixed -30° pitch, orthogonal projection."""
	if not camera:
		return

	camera.size = camera_size

	# Place the camera far enough so geometry is not clipped.
	var arm_length: float = 80.0
	var pitch_rad = deg_to_rad(camera_angle)
	var yaw_rad = deg_to_rad(camera_yaw)
	var offset = Vector3(
		arm_length * cos(pitch_rad) * sin(yaw_rad),
		arm_length * sin(abs(pitch_rad)),
		arm_length * cos(pitch_rad) * cos(yaw_rad)
	)
	camera.position = camera_target + offset
	camera.look_at(camera_target, Vector3.UP)


func _reset_camera():
	"""Reset camera to default centered position"""
	camera_target = Vector3(current_map.size.x / 2.0, 0, current_map.size.y / 2.0)
	camera_size = 15.0
	camera_angle = -30.0
	camera_yaw = 0.0
	_update_camera_position()


func _on_symmetry_changed(index: int):
	"""Handle symmetry mode change"""
	var mode = index as SymmetrySystem.Mode
	set_symmetry_mode(mode)
	if status_label:
		status_label.text = "Symmetry: " + symmetry_system.get_mode_name(mode)


func _on_brush_form_changed(index: int):
	"""Handle brush shape toggle (0 = Circle, 1 = Square)"""
	if current_brush:
		current_brush.brush_shape = index as EditorBrush.BrushShape
	if status_label:
		status_label.text = "Brush shape: " + ("Circle" if index == 0 else "Square")


func _on_brush_size_changed(value: float):
	"""Handle brush size change"""
	if current_brush:
		current_brush.brush_size = int(value)
	if editor_cursor:
		editor_cursor.set_brush_radius(int(value))
	if status_label:
		status_label.text = "Brush size: " + str(int(value))


func _create_brush(brush_type: BrushType):
	"""Create and set the current brush"""
	# Preserve current size/shape settings across brush switches
	var prev_size := 1
	var prev_shape := EditorBrush.BrushShape.CIRCLE
	if current_brush:
		prev_size = current_brush.brush_size
		prev_shape = current_brush.brush_shape

	current_brush_type = brush_type

	match brush_type:
		BrushType.PAINT_COLLISION:
			current_brush = PaintCollisionBrush.new(current_map, symmetry_system, 1)
		BrushType.ERASE:
			current_brush = EraseBrush.new(current_map, symmetry_system)
		BrushType.PLACE_ENTITY:
			current_brush = EntityBrush.new(
				current_map, symmetry_system, command_stack, "", current_player
			)
		BrushType.PAINT_TEXTURE:
			current_brush = (
				TextureBrush
				. new(
					current_map,
					symmetry_system,
					command_stack,
					null,
				)
			)
		BrushType.PLACE_SPAWN:
			current_brush = SpawnBrush.new(current_map, symmetry_system, command_stack)
		BrushType.PAINT_HEIGHT:
			current_brush = HeightBrush.new(current_map, symmetry_system, command_stack)
		BrushType.PAINT_SLOPE:
			current_brush = SlopeBrush.new(current_map, symmetry_system, command_stack)

	# Restore size/shape
	if current_brush:
		current_brush.brush_size = prev_size
		current_brush.brush_shape = prev_shape

	# Sync cursor appearance to new brush
	if editor_cursor and current_brush:
		editor_cursor.set_cursor_color(current_brush.get_cursor_color())
		editor_cursor.set_brush_radius(current_brush.brush_size)

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
	if current_brush_type == BrushType.PLACE_ENTITY:
		_refresh_entity_previews()
	if current_brush_type == BrushType.PAINT_TEXTURE:
		if terrain_system:
			terrain_system.apply_texture_brush(positions)
	if current_brush_type == BrushType.PLACE_SPAWN:
		_refresh_spawn_previews()
		# Update brush name to reflect count
		var brush_info = get_node_or_null("VBoxContainer/Toolbar/BrushInfo")
		if brush_info and current_brush:
			brush_info.text = current_brush.get_brush_name()
	if current_brush_type == BrushType.PAINT_HEIGHT or current_brush_type == BrushType.PAINT_SLOPE:
		# Update terrain mesh heights and collision overlay
		if terrain_system:
			terrain_system.update_height_at(positions)
		if collision_renderer:
			collision_renderer.refresh()
	if current_brush_type == BrushType.ERASE:
		_refresh_entity_previews()
		_refresh_spawn_previews()


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
		pan_dir = pan_dir.normalized()

		var yaw_basis = Basis(Vector3.UP, deg_to_rad(camera_yaw))
		var move_dir = yaw_basis * Vector3(pan_dir.x, 0, pan_dir.z)

		camera_target += move_dir * camera_pan_speed * delta

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
			_toggle_view_mode()

	# Handle mouse scroll for zoom and middle mouse for orbit
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_size = maxf(camera_size_min, camera_size - camera_zoom_speed)
			_update_camera_position()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_size = minf(camera_size_max, camera_size + camera_zoom_speed)
			_update_camera_position()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			is_painting = event.pressed
			if event.pressed:
				_try_paint_at_mouse(event.position)

	elif event is InputEventMouseMotion:
		if is_orbiting:
			# Only allow yaw rotation; pitch stays fixed at -30° to match in-game view
			camera_yaw += event.relative.x * camera_rotate_sensitivity
			_update_camera_position()
		else:
			_update_cursor_at_mouse(event.position)
			if is_painting:
				_try_paint_at_mouse(event.position)


func _try_paint_at_mouse(mouse_pos: Vector2):
	if not current_brush:
		return
	var grid_pos: Variant = _raycast_mouse_to_grid(mouse_pos)
	if grid_pos == null:
		return
	current_brush.apply(grid_pos)


func _update_cursor_at_mouse(mouse_pos: Vector2):
	"""Move the editor cursor to the hovered grid cell."""
	if not editor_cursor:
		return
	var grid_pos: Variant = _raycast_mouse_to_grid(mouse_pos)
	if grid_pos == null:
		editor_cursor.set_visible_cursor(false)
		return
	editor_cursor.set_visible_cursor(true)
	editor_cursor.set_cursor_position(grid_pos)
	if current_brush:
		editor_cursor.set_affected_cells(current_brush.get_affected_positions(grid_pos))


func _raycast_mouse_to_grid(mouse_pos: Vector2) -> Variant:
	"""Raycast from mouse position to the ground plane. Returns Vector2i or null."""
	if not editor_viewport or not camera:
		return null

	# Convert global mouse → SubViewport local
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

	var hit = space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var hit_pos: Vector3 = hit.position
	return _world_to_grid(hit_pos)


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
	_refresh_entity_previews()
	_refresh_spawn_previews()
	terrain_system._ensure_splat_textures()
	if terrain_system:
		terrain_system._upload_height_grid()


# --- Entity preview rendering ---
func _refresh_entity_previews():
	# Remove old previews
	if entity_preview_nodes:
		for node in entity_preview_nodes.values():
			if is_instance_valid(node):
				node.queue_free()
		entity_preview_nodes.clear()
	if not visual_layer:
		return
	# Add new previews for all placed entities
	for entity in current_map.placed_entities:
		if not entity.has("scene_path") or entity.scene_path == "":
			continue
		var scene = load(entity.scene_path)
		if not scene:
			continue
		var inst = scene.instantiate()
		inst.name = "EntityPreview_%s_%s" % [entity.scene_path.get_file(), str(entity.pos)]
		var height_y: float = current_map.get_height_at(entity.pos)
		inst.position = Vector3(entity.pos.x, height_y, entity.pos.y)
		if entity.has("rotation"):
			inst.rotation.y = entity.rotation
		visual_layer.add_child(inst)
		entity_preview_nodes[entity.pos] = inst


# --- Spawn point preview rendering ---
func _refresh_spawn_previews():
	"""Rebuild the numbered spawn point markers in the 3D viewport."""
	for node in spawn_preview_nodes:
		if is_instance_valid(node):
			node.queue_free()
	spawn_preview_nodes.clear()

	if not visual_layer or not current_map:
		return

	for i in range(current_map.spawn_points.size()):
		var pos = current_map.spawn_points[i]
		var marker_root = Node3D.new()
		marker_root.name = "SpawnPreview_%d" % i
		marker_root.position = Vector3(pos.x + 0.5, 0, pos.y + 0.5)

		# Coloured cylinder
		var mesh_inst = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.4
		cyl.bottom_radius = 0.4
		cyl.height = 1.5
		mesh_inst.mesh = cyl
		mesh_inst.position.y = cyl.height * 0.5
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.YELLOW
		mat.emission_enabled = true
		mat.emission = Color.YELLOW
		mat.emission_energy_multiplier = 0.3
		mesh_inst.material_override = mat
		marker_root.add_child(mesh_inst)

		# Number label
		var label = Label3D.new()
		label.text = str(i + 1)
		label.font_size = 48
		label.pixel_size = 0.01
		label.position.y = cyl.height + 0.3
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color.WHITE
		label.outline_modulate = Color.BLACK
		label.outline_size = 12
		marker_root.add_child(label)

		visual_layer.add_child(marker_root)
		spawn_preview_nodes.append(marker_root)


func set_view_mode(mode: ViewMode):
	"""Toggle between game view and collision view"""
	view_mode = mode

	if visual_layer and collision_layer:
		visual_layer.visible = (mode == ViewMode.GAME_VIEW)
		collision_layer.visible = (mode == ViewMode.COLLISION_VIEW)
	else:
		push_warning("Warning: Visual or collision layer not found for view mode toggle")


func set_symmetry_mode(mode: SymmetrySystem.Mode):
	"""Set the symmetry mode for brush operations"""
	symmetry_system.set_mode(mode)


func new_map(_size: Vector2i):
	"""Create a new map"""
	current_map = MapResource.new()
	current_map.size = _size
	current_map._initialize_collision_grid()
	symmetry_system.set_map_size(_size)
	command_stack.clear()
	_refresh_view()


func save_map(path: String):
	"""Save the current map to a file"""
	var errors = current_map.validate()
	if not errors.is_empty():
		push_warning("Map has validation errors: " + str(errors))
		if status_label:
			status_label.text = "Validation errors: " + str(errors[0])

	# Generate merged collision shapes before saving
	current_map.collision_shapes = CollisionShapeBuilder.build_all(current_map)

	# Capture lighting & environment from the editor viewport
	_capture_lighting_to_map_resource()

	var result = ResourceSaver.save(current_map, path)
	if result == OK:
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
		# Reinitialize terrain system with loaded map
		if terrain_system:
			terrain_system.set_map(current_map)
		# Update collision renderer to reference the new map
		if collision_renderer:
			collision_renderer.set_map_resource(current_map)
		# Recreate current brush so it references the new map
		_create_brush(current_brush_type)
		_refresh_view()
		if status_label:
			status_label.text = "Map loaded: " + path.get_file()
	else:
		push_error("Failed to load map or invalid format")
		if status_label:
			status_label.text = "Failed to load map"


func export_map(path: String):
	"""Export map to runtime format"""
	# Generate merged collision shapes before export
	current_map.collision_shapes = CollisionShapeBuilder.build_all(current_map)

	var runtime_map = MapRuntimeResource.from_editor_map(current_map)
	var errors = runtime_map.validate()

	if not errors.is_empty():
		push_warning("Runtime map has validation errors: " + str(errors))
		if status_label:
			status_label.text = "Validation errors: " + str(errors[0])

	var result = ResourceSaver.save(runtime_map, path)
	if result == OK:
		if status_label:
			status_label.text = "Map exported successfully"
	else:
		push_error("Failed to export map: " + str(result))
		if status_label:
			status_label.text = "Failed to export map"


func _exit_tree():
	# Clean up
	pass


func _capture_lighting_to_map_resource():
	"""Snapshot the editor's Sun light and Environment into the MapResource
	so the game can reproduce the exact same lighting."""
	var sun = visual_layer.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		current_map.sun_transform = sun.transform
		current_map.sun_color = sun.light_color
		current_map.sun_energy = sun.light_energy
		current_map.sun_specular = sun.light_specular
		current_map.sun_shadow_enabled = sun.shadow_enabled
		current_map.sun_shadow_bias = sun.shadow_bias
		current_map.sun_shadow_blur = sun.shadow_blur

	var env: Environment = (
		editor_viewport.world_3d.environment if editor_viewport.world_3d else null
	)
	if env:
		current_map.environment = env.duplicate()


func _on_back_button_pressed():
	"""Return to main menu"""
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")
