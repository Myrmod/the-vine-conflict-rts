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
# Symmetry axis visual guide
var _symmetry_line_mesh: MeshInstance3D = null
# Entity collision debug overlay nodes
var _entity_collision_debug_nodes: Array[Node3D] = []

# Map name input
var _map_name_edit: LineEdit = null

# Material selector for decorations
var _material_option: OptionButton = null
var _material_paths: Array[String] = []

# Auto cliff placement
var auto_place_cliffs: bool = true
var cliff_y_offset: float = 0.0  # Y offset for cliff pieces (0.0 = ground level)
const AUTO_CLIFF_DIR := "res://source/decorations/high_ground_cliffs/"
const CLIFF_STRAIGHT_SCENES: Array[String] = [
	"res://source/decorations/high_ground_cliffs/CliffStraight1.tscn",
	"res://source/decorations/high_ground_cliffs/CliffStraight2.tscn",
	"res://source/decorations/high_ground_cliffs/CliffStraight3.tscn",
	"res://source/decorations/high_ground_cliffs/CliffStraight4.tscn",
]
const CLIFF_CORNER_SCENES: Array[String] = [
	"res://source/decorations/high_ground_cliffs/CliffCorner1.tscn",
	"res://source/decorations/high_ground_cliffs/CliffCorner2.tscn",
]
const CLIFF_STRAIGHT_HEIGHT := 21.82
const CLIFF_CORNER_HEIGHT := 9.69
const CLIFF_MIN_HEIGHT_DIFF := 0.5
const CLIFF_CARDINAL_DIRS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]
const CLIFF_DIR_ROT := {
	Vector2i(0, -1): 0.0,
	Vector2i(1, 0): -PI / 2.0,
	Vector2i(0, 1): PI,
	Vector2i(-1, 0): PI / 2.0,
}

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
	var palette_select = get_node_or_null(
		"VBoxContainer/MainArea/LeftPalette/ScrollContainer/ScrollContent/PaletteSelect"
	)
	var texture_select = get_node_or_null(
		"VBoxContainer/MainArea/LeftPalette/ScrollContainer/ScrollContent/PaletteSelect/Textures/TexturePalette"
	)
	status_label = get_node_or_null("VBoxContainer/StatusBar/StatusLabel")
	_map_name_edit = get_node_or_null("VBoxContainer/Toolbar/MapNameEdit")
	if _map_name_edit:
		_map_name_edit.text = current_map.map_name if current_map.map_name != "Untitled Map" else ""

	# Connect entity palette signals
	if palette_select:
		palette_select.entity_selected.connect(_on_palette_entity_selected)
		palette_select.spawn_selected.connect(_on_palette_spawn_selected)
		palette_select.erase_selected.connect(_on_palette_erase_selected)
		palette_select.height_level_selected.connect(_on_palette_height_selected)
		palette_select.slope_selected.connect(_on_palette_slope_selected)
		palette_select.water_slope_selected.connect(_on_palette_water_slope_selected)
		palette_select.collision_selected.connect(_on_palette_collision_selected)
		palette_select.auto_cliff_toggled.connect(_on_auto_cliff_toggled)
		palette_select.cliff_y_offset_changed.connect(_on_cliff_y_offset_changed)
		palette_select.mirror_toggled.connect(_on_mirror_toggled)

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
	var brush_settings = get_node_or_null(
		"VBoxContainer/MainArea/LeftPalette/ScrollContainer/ScrollContent/Brushsettings"
	)
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

		# Erase button and material selector
		var vbox = brush_settings.get_node_or_null("MarginContainer/VBoxContainer")
		if vbox:
			var erase_btn := Button.new()
			erase_btn.text = "✕ Erase"
			erase_btn.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
			erase_btn.pressed.connect(_on_palette_erase_selected)
			vbox.add_child(erase_btn)
			vbox.move_child(erase_btn, 0)

			var mat_label := Label.new()
			mat_label.name = "MaterialLabel"
			mat_label.text = "Material"
			vbox.add_child(mat_label)

			_material_option = OptionButton.new()
			_material_option.name = "MaterialOption"
			_material_paths = _scan_material_paths()
			_material_option.add_item("(Default)", 0)
			for i in range(_material_paths.size()):
				var label_text = _material_paths[i].get_file().get_basename()
				_material_option.add_item(label_text, i + 1)
			_material_option.item_selected.connect(_on_material_selected)
			vbox.add_child(_material_option)

			# Hidden by default, shown when entity brush is active
			mat_label.visible = false
			_material_option.visible = false


func _on_file_menu_item_selected(id: int):
	"""Handle file menu item selection"""
	match id:
		0:  # New Map
			var sx = _get_map_size_x_spinbox()
			var sy = _get_map_size_y_spinbox()
			var map_size = Vector2i(int(sx.value) if sx else 50, int(sy.value) if sy else 50)
			new_map(map_size)
			if status_label:
				status_label.text = "Created new %dx%d map" % [map_size.x, map_size.y]
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

	# Force ghost recreation for the new entity
	_hide_entity_ghost()

	# Show material selector and sync with brush
	_show_material_selector(true)
	if _material_option:
		_material_option.select(0)
	if current_brush is EntityBrush:
		current_brush.set_material_path("")

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


func _on_palette_erase_selected():
	"""Handle erase tool selection from palette"""
	_create_brush(BrushType.ERASE)

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


func _on_auto_cliff_toggled(enabled: bool) -> void:
	auto_place_cliffs = enabled
	# TODO: maybe the following should be removed?
	# if enabled:
	# 	_update_auto_cliffs()
	# else:
	# 	# Remove auto-placed cliffs when unchecked
	# 	current_map.placed_entities = current_map.placed_entities.filter(
	# 		func(e): return not _is_auto_cliff(e)
	# 	)
	# 	_refresh_entity_previews()


func _on_cliff_y_offset_changed(value: float) -> void:
	cliff_y_offset = value
	if auto_place_cliffs:
		_update_auto_cliffs()


func _on_mirror_toggled(mirrored: bool) -> void:
	"""Toggle X-axis mirroring on the current entity brush."""
	if current_brush is EntityBrush:
		var s = absf(current_brush.entity_scale)
		current_brush.set_entity_scale(-s if mirrored else s)
		_update_brush_info_label()
		_update_entity_ghost_transform()


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


func _on_material_selected(index: int):
	"""Handle material selection from the material OptionButton."""
	if current_brush is EntityBrush:
		if index == 0:
			current_brush.set_material_path("")
		else:
			current_brush.set_material_path(_material_paths[index - 1])
		_hide_entity_ghost()


func _scan_material_paths() -> Array[String]:
	"""Scan res://assets_overide/RockPack1/Materials/ for .tres material files.
	Returns relative paths (e.g. RockPack1/Materials/X.tres) for ModelHolder compatibility."""
	var paths: Array[String] = []
	var dir_path := "res://assets_overide/RockPack1/Materials/"
	var relative_prefix := "RockPack1/Materials/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Cannot open material directory: " + dir_path)
		return paths
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			paths.append(relative_prefix + file_name)
	dir.list_dir_end()
	paths.sort()
	return paths


func _show_material_selector(value: bool):
	"""Show or hide the material selector label and option button."""
	var brush_settings = get_node_or_null(
		"VBoxContainer/MainArea/LeftPalette/ScrollContainer/ScrollContent/Brushsettings"
	)
	if not brush_settings:
		return
	var mat_label = brush_settings.get_node_or_null("MarginContainer/VBoxContainer/MaterialLabel")
	if mat_label:
		mat_label.visible = value
	if _material_option:
		_material_option.visible = value


func _create_brush(brush_type: BrushType):
	"""Create and set the current brush"""
	# Preserve current size/shape settings across brush switches
	var prev_size := 1
	var prev_shape := EditorBrush.BrushShape.CIRCLE
	if current_brush:
		prev_size = current_brush.brush_size
		prev_shape = current_brush.brush_shape

	current_brush_type = brush_type

	# Clear entity ghost when switching brushes
	_hide_entity_ghost()

	# Hide material selector for non-entity brushes
	if brush_type != BrushType.PLACE_ENTITY:
		_show_material_selector(false)

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
		if auto_place_cliffs:
			_update_auto_cliffs()
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
		elif event.keycode == KEY_R:
			# Rotate entity brush by 90°
			_rotate_entity_brush(90.0)

	# Handle mouse scroll for zoom and middle mouse for orbit
	if event is InputEventMouseButton:
		# Only process viewport mouse events when the cursor is over the viewport
		var is_over_viewport: bool = _is_mouse_over_viewport(event.position)
		var is_scroll_up = (
			event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed and is_over_viewport
		)
		var is_scroll_down = (
			event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed and is_over_viewport
		)

		if (is_scroll_up or is_scroll_down) and event.ctrl_pressed:
			# Ctrl + Mouse Wheel → rotate entity brush (15° steps)
			var direction = -1.0 if is_scroll_up else 1.0
			_rotate_entity_brush(15.0 * direction)
		elif (is_scroll_up or is_scroll_down) and event.shift_pressed:
			# Shift + Mouse Wheel → scale entity brush (0.1 steps)
			var direction = 1.0 if is_scroll_up else -1.0
			_scale_entity_brush(0.1 * direction)
		elif is_scroll_up:
			camera_size = maxf(camera_size_min, camera_size - camera_zoom_speed)
			_update_camera_position()
		elif is_scroll_down:
			camera_size = minf(camera_size_max, camera_size + camera_zoom_speed)
			_update_camera_position()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed:
				# Always clear painting state on release
				is_painting = false
			elif is_over_viewport:
				if current_brush and current_brush.is_single_placement():
					# Single-placement brushes: click to place, no drag
					_try_paint_at_mouse(event.position)
				else:
					is_painting = true
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
	# Alt held = free placement for entity brushes
	if Input.is_key_pressed(KEY_ALT) and current_brush is EntityBrush:
		var world_pos = _raycast_mouse_to_world_2d(mouse_pos)
		if world_pos != null:
			current_brush.apply_free(world_pos)
		return
	var grid_pos: Variant = _raycast_mouse_to_grid(mouse_pos)
	if grid_pos == null:
		return
	current_brush.apply(grid_pos)


func _update_cursor_at_mouse(mouse_pos: Vector2):
	"""Move the editor cursor to the hovered grid cell."""
	if not editor_cursor:
		return
	# Alt held = free placement for entity brushes
	if Input.is_key_pressed(KEY_ALT) and current_brush is EntityBrush:
		var world_pos = _raycast_mouse_to_world_2d(mouse_pos)
		if world_pos == null:
			editor_cursor.set_visible_cursor(false)
			_hide_entity_ghost()
			return
		editor_cursor.set_visible_cursor(false)
		_update_entity_ghost(world_pos)
		return
	var grid_pos: Variant = _raycast_mouse_to_grid(mouse_pos)
	if grid_pos == null:
		editor_cursor.set_visible_cursor(false)
		_hide_entity_ghost()
		return
	editor_cursor.set_visible_cursor(true)
	editor_cursor.set_cursor_position(grid_pos)
	if current_brush:
		editor_cursor.set_affected_cells(current_brush.get_affected_positions(grid_pos))
	_update_entity_ghost(grid_pos)


# ── Entity rotation ─────────────────────────────────────────────────


func _rotate_entity_brush(degrees: float):
	"""Rotate the current entity brush by the given degrees."""
	if current_brush is EntityBrush:
		current_brush.set_rotation(current_brush.rotation + deg_to_rad(degrees))
		_update_brush_info_label()
		_update_entity_ghost_transform()


func _scale_entity_brush(delta: float):
	"""Change the current entity brush scale by delta (clamped to 0.1 .. 10.0)."""
	if current_brush is EntityBrush:
		var new_scale = clampf(current_brush.entity_scale + delta, 0.1, 10.0)
		current_brush.set_entity_scale(new_scale)
		_update_brush_info_label()
		_update_entity_ghost_transform()


func _update_brush_info_label():
	var brush_info = get_node_or_null("VBoxContainer/Toolbar/BrushInfo")
	if brush_info and current_brush:
		brush_info.text = current_brush.get_brush_name()


# ── Entity ghost preview ────────────────────────────────────────────

var _entity_ghost: Node3D = null
var _entity_ghost_path: String = ""
var _entity_ghost_material: String = ""


func _update_entity_ghost(pos):
	"""Show a transparent ghost of the entity being placed at the cursor.
	pos can be Vector2i (grid-snapped) or Vector2 (free placement)."""
	if not current_brush is EntityBrush:
		_hide_entity_ghost()
		return

	var brush: EntityBrush = current_brush
	if brush.scene_path.is_empty():
		_hide_entity_ghost()
		return

	# Recreate ghost if entity or material changed
	if _entity_ghost_path != brush.scene_path or _entity_ghost_material != brush.material_path:
		_hide_entity_ghost()
		var packed = load(brush.scene_path)
		if not packed:
			return
		_entity_ghost = packed.instantiate()
		_entity_ghost.name = "EntityGhost"

		if not brush.material_path.is_empty():
			_apply_material_to_model_holders(_entity_ghost, brush.material_path)
			# Add the ghost to the tree first so ModelHolder._ready() runs and loads the material
			viewport_3d.add_child(_entity_ghost)
			# Then apply transparency on top of the real material
			_apply_ghost_transparency(_entity_ghost)
		else:
			_apply_ghost_material(_entity_ghost)
			viewport_3d.add_child(_entity_ghost)

		_entity_ghost_path = brush.scene_path
		_entity_ghost_material = brush.material_path

	if _entity_ghost and is_instance_valid(_entity_ghost):
		var grid_cell: Vector2 = Vector2i(floor(pos.x), floor(pos.y)) if pos is Vector2 else pos
		var height_y: float = current_map.get_height_at(grid_cell) if current_map else 0.0
		_entity_ghost.position = Vector3(pos.x, height_y, pos.y)
		_entity_ghost.rotation.y = brush.rotation
		var s = brush.entity_scale
		_entity_ghost.scale = Vector3(s, absf(s), absf(s))
		_entity_ghost.visible = true


func _update_entity_ghost_transform():
	"""Update the ghost rotation and scale to match the brush without repositioning."""
	if _entity_ghost and is_instance_valid(_entity_ghost) and current_brush is EntityBrush:
		_entity_ghost.rotation.y = current_brush.rotation
		var s = current_brush.entity_scale
		_entity_ghost.scale = Vector3(s, absf(s), absf(s))


func _hide_entity_ghost():
	"""Hide (and optionally free) the entity ghost."""
	if _entity_ghost and is_instance_valid(_entity_ghost):
		_entity_ghost.queue_free()
		_entity_ghost = null
		_entity_ghost_path = ""
		_entity_ghost_material = ""


func _apply_ghost_material(node: Node):
	"""Apply a translucent material override to all mesh children."""
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.4)
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.no_depth_test = true
	for child in node.find_children("*"):
		if child is MeshInstance3D:
			child.material_override = ghost_mat


func _apply_ghost_transparency(node: Node):
	"""Make existing materials semi-transparent for ghost preview."""
	for child in node.find_children("*"):
		if child is MeshInstance3D:
			var base_mat: Material = child.material_override
			if base_mat == null:
				base_mat = (
					child.mesh.surface_get_material(0)
					if child.mesh and child.mesh.get_surface_count() > 0
					else null
				)
			if base_mat and base_mat is StandardMaterial3D:
				var mat: StandardMaterial3D = base_mat.duplicate()
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.6
				mat.no_depth_test = true
				child.material_override = mat
			else:
				# Fallback to generic ghost material
				var ghost_mat := StandardMaterial3D.new()
				ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				ghost_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.4)
				ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				ghost_mat.no_depth_test = true
				child.material_override = ghost_mat


func _is_mouse_over_viewport(mouse_pos: Vector2) -> bool:
	"""Return true if the mouse position is inside the viewport container rect."""
	if not viewport_container:
		return false
	return viewport_container.get_global_rect().has_point(mouse_pos)


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


func _raycast_mouse_to_world_2d(mouse_pos: Vector2) -> Variant:
	"""Raycast from mouse position to the ground plane. Returns Vector2 (float) or null."""
	if not editor_viewport or not camera:
		return null

	var rect = viewport_container.get_global_rect()
	if not rect.has_point(mouse_pos):
		return null

	var local_pos = mouse_pos - rect.position

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
	return Vector2(hit_pos.x, hit_pos.z)


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
	# Always strip stale auto-cliff entities (undo may restore old placed_entities)
	current_map.placed_entities = current_map.placed_entities.filter(
		func(e): return not _is_auto_cliff(e)
	)
	if collision_renderer:
		collision_renderer.refresh()
	_refresh_entity_previews()
	_refresh_spawn_previews()
	terrain_system._ensure_splat_textures()
	if terrain_system:
		terrain_system._upload_height_grid()
		terrain_system._build_slope_meshes()
		terrain_system._upload_water_mask()
	if auto_place_cliffs:
		_update_auto_cliffs()


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
		var height_y: float = entity.get("y_offset", current_map.get_height_at(entity.pos))
		inst.position = Vector3(entity.pos.x, height_y, entity.pos.y)
		if entity.has("rotation"):
			inst.rotation.y = entity.rotation
		if entity.has("entity_scale"):
			var s = entity.entity_scale
			# Negative scale mirrors on X axis (used by cliff mirroring)
			inst.scale = Vector3(s, absf(s), absf(s))
		if entity.has("material_path"):
			_apply_material_to_model_holders(inst, entity.material_path)
		visual_layer.add_child(inst)
		entity_preview_nodes[entity.pos] = inst

	# Refresh collision debug overlays if currently in collision view
	if view_mode == ViewMode.COLLISION_VIEW:
		_update_entity_collision_debug(true)


func _apply_material_to_model_holders(node: Node, mat_path: String) -> void:
	"""Set material_path on all ModelHolder children before they enter the tree."""
	if node is ModelHolder:
		node.material_path = mat_path
	for child in node.get_children():
		_apply_material_to_model_holders(child, mat_path)


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
		# Keep visual_layer always visible so entity/spawn previews remain on screen.
		# Keep terrain system visible in collision view as reference behind the overlay.
		collision_layer.visible = (mode == ViewMode.COLLISION_VIEW)
	else:
		push_warning("Warning: Visual or collision layer not found for view mode toggle")

	# Show / hide entity collision debug overlays
	_update_entity_collision_debug(mode == ViewMode.COLLISION_VIEW)


func _update_entity_collision_debug(visible_flag: bool) -> void:
	"""Add or remove translucent debug meshes for every CollisionShape3D inside entity previews."""
	# Always clear previous debug visuals
	for n in _entity_collision_debug_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_entity_collision_debug_nodes.clear()

	if not visible_flag:
		return

	var debug_mat := StandardMaterial3D.new()
	debug_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.45)
	debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for node in entity_preview_nodes.values():
		if not is_instance_valid(node):
			continue
		for col_shape in node.find_children("*", "CollisionShape3D"):
			var shape = col_shape.shape
			if not shape:
				continue
			var mesh: Mesh = null
			if shape is BoxShape3D:
				var b := BoxMesh.new()
				b.size = shape.size
				mesh = b
			elif shape is SphereShape3D:
				var s := SphereMesh.new()
				s.radius = shape.radius
				s.height = shape.radius * 2.0
				mesh = s
			elif shape is CylinderShape3D:
				var c := CylinderMesh.new()
				c.top_radius = shape.radius
				c.bottom_radius = shape.radius
				c.height = shape.height
				mesh = c
			elif shape is CapsuleShape3D:
				var cap := CapsuleMesh.new()
				cap.radius = shape.radius
				cap.height = shape.height
				mesh = cap
			if mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = debug_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Position relative to the viewport_3d so global transform is correct
			mi.global_transform = col_shape.global_transform
			viewport_3d.add_child(mi)
			_entity_collision_debug_nodes.append(mi)


func set_symmetry_mode(mode: SymmetrySystem.Mode):
	"""Set the symmetry mode for brush operations"""
	symmetry_system.set_mode(mode)
	_update_symmetry_line()


func _update_symmetry_line():
	"""Draw / remove a visual guide line for the current symmetry axis."""
	if _symmetry_line_mesh and is_instance_valid(_symmetry_line_mesh):
		_symmetry_line_mesh.queue_free()
		_symmetry_line_mesh = null

	if not viewport_3d or not symmetry_system:
		return
	if symmetry_system.current_mode == SymmetrySystem.Mode.NONE:
		return

	var sx: float = current_map.size.x
	var sy: float = current_map.size.y
	var im := ImmediateMesh.new()

	var line_y: float = 0.3  # slightly above ground

	match symmetry_system.current_mode:
		SymmetrySystem.Mode.MIRROR_X:
			# Vertical line through center X
			var cx := sx * 0.5
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			im.surface_add_vertex(Vector3(cx, line_y, 0))
			im.surface_add_vertex(Vector3(cx, line_y, sy))
			im.surface_end()

		SymmetrySystem.Mode.MIRROR_Y:
			# Horizontal line through center Y
			var cz := sy * 0.5
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			im.surface_add_vertex(Vector3(0, line_y, cz))
			im.surface_add_vertex(Vector3(sx, line_y, cz))
			im.surface_end()

		SymmetrySystem.Mode.DIAGONAL:
			# Diagonal line from (0,0) to (sx,sy)
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			im.surface_add_vertex(Vector3(0, line_y, 0))
			im.surface_add_vertex(Vector3(sx, line_y, sy))
			im.surface_end()

		SymmetrySystem.Mode.QUAD:
			# Both center lines
			var cx := sx * 0.5
			var cz := sy * 0.5
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			im.surface_add_vertex(Vector3(cx, line_y, 0))
			im.surface_add_vertex(Vector3(cx, line_y, sy))
			im.surface_add_vertex(Vector3(0, line_y, cz))
			im.surface_add_vertex(Vector3(sx, line_y, cz))
			im.surface_end()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true

	_symmetry_line_mesh = MeshInstance3D.new()
	_symmetry_line_mesh.name = "SymmetryLine"
	_symmetry_line_mesh.mesh = im
	_symmetry_line_mesh.material_override = mat
	_symmetry_line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport_3d.add_child(_symmetry_line_mesh)


func new_map(_size: Vector2i):
	"""Create a new map"""
	current_map = MapResource.new()
	current_map.size = _size
	if _map_name_edit:
		_map_name_edit.text = ""
	current_map._initialize_collision_grid()
	current_map._initialize_height_grid()
	current_map._initialize_water_grid()
	current_map._initialize_cell_type_grid()
	symmetry_system.set_map_size(_size)
	command_stack.clear()
	_sync_size_spinboxes()
	_rebuild_3d_scene()
	_create_brush(current_brush_type)
	_refresh_view()
	_update_symmetry_line()


func save_map(path: String):
	"""Save the current map to a file"""
	if _map_name_edit:
		var entered_name := _map_name_edit.text.strip_edges()
		current_map.map_name = (
			entered_name if not entered_name.is_empty() else path.get_file().get_basename()
		)
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
		_sync_size_spinboxes()
		# Reinitialize terrain system with loaded map
		if terrain_system:
			terrain_system.set_map(current_map)
		# Update collision renderer to reference the new map
		if collision_renderer:
			collision_renderer.set_map_resource(current_map)
		# Recreate current brush so it references the new map
		_create_brush(current_brush_type)
		_rebuild_3d_scene()
		_refresh_view()
		_update_symmetry_line()
		if _map_name_edit:
			_map_name_edit.text = (
				current_map.map_name if current_map.map_name != "Untitled Map" else ""
			)
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


# ============================================================
# Map Size
# ============================================================


func _get_map_size_x_spinbox() -> SpinBox:
	return get_node_or_null("VBoxContainer/Toolbar/MapSizeX")


func _get_map_size_y_spinbox() -> SpinBox:
	return get_node_or_null("VBoxContainer/Toolbar/MapSizeY")


func _sync_size_spinboxes():
	"""Update the map size spinboxes to reflect the current map size."""
	var sx = _get_map_size_x_spinbox()
	var sy = _get_map_size_y_spinbox()
	if sx:
		sx.value = current_map.size.x
	if sy:
		sy.value = current_map.size.y


func _on_apply_size_pressed():
	"""Resize the current map to the dimensions set in the spinboxes."""
	var sx = _get_map_size_x_spinbox()
	var sy = _get_map_size_y_spinbox()
	if not sx or not sy:
		return
	var new_size := Vector2i(int(sx.value), int(sy.value))
	if new_size == current_map.size:
		return
	resize_current_map(new_size)


func resize_current_map(new_size: Vector2i):
	"""Resize the current map and rebuild all 3D scene elements."""
	var terrain_count: int = Globals.terrain_types.size() if Globals.terrain_types else 4
	current_map.resize_map(new_size, terrain_count)
	symmetry_system.set_map_size(new_size)
	_rebuild_3d_scene()
	_create_brush(current_brush_type)
	_refresh_view()
	_update_symmetry_line()
	if status_label:
		status_label.text = "Map resized to %dx%d" % [new_size.x, new_size.y]


func _rebuild_3d_scene():
	"""Rebuild 3D scene elements after a map resize (ground body, grid, terrain, etc.)."""
	# Recreate ground collision body for raycasting so the physics server
	# picks up the new extents on the very next query.
	if viewport_3d:
		var old_ground = viewport_3d.get_node_or_null("PaintGround")
		if old_ground:
			# Use free() (not queue_free) so the old physics body is removed
			# from the server immediately — otherwise the smaller shape lingers
			# until end-of-frame and raycasts to the expanded area return null.
			old_ground.free()

		var ground_body := StaticBody3D.new()
		ground_body.name = "PaintGround"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(current_map.size.x, 1.0, current_map.size.y)
		shape.shape = box
		shape.position = Vector3(current_map.size.x * 0.5, -0.5, current_map.size.y * 0.5)
		ground_body.add_child(shape)
		viewport_3d.add_child(ground_body)

	# Rebuild grid renderer
	if grid_renderer:
		grid_renderer.set_grid_size(current_map.size)

	# Rebuild collision renderer
	if collision_renderer:
		collision_renderer.set_map_resource(current_map)
		collision_renderer.refresh()

	# Rebuild terrain system
	if terrain_system:
		terrain_system.resize_mesh(Vector2(current_map.size))
		terrain_system.set_map(current_map)

	# Re-center camera
	camera_target = Vector3(current_map.size.x / 2.0, 0, current_map.size.y / 2.0)
	_update_camera_position()


# ── Auto-cliff placement ────────────────────────────────────────────────


func _is_auto_cliff(entity: Dictionary) -> bool:
	return entity.has("scene_path") and entity.scene_path.begins_with(AUTO_CLIFF_DIR)


func _update_auto_cliffs() -> void:
	if not current_map:
		return

	# 1. Remove existing auto-placed cliff entities
	current_map.placed_entities = current_map.placed_entities.filter(
		func(e): return not _is_auto_cliff(e)
	)

	# 2. Collect height edges and slope directions
	var sz := current_map.size
	var slope_dirs := _compute_cliff_slope_directions(sz)
	var edges := _collect_cliff_edges(sz, slope_dirs)
	# Append slope-side edges: straight cliffs stepped along each slope face,
	# using the interpolated ramp height so each piece sits at the correct Y.
	edges.append_array(_collect_slope_side_edges(sz, slope_dirs))

	# 3. Place straight pieces for every edge
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var prev_straight_idx: int = -1
	var prev_prev_straight_idx: int = -1
	for edge in edges:
		var pos: Vector2i = edge["pos"]
		var dir: Vector2i = edge["dir"]

		# Slope-side edges use 0.51 instead of 0.5 so floor(entity_pos) is biased
		# into the accessible (lower) cell, letting the erase brush find them reliably.
		var dir_offset: float = 0.51 if edge.get("slope_side", false) else 0.5
		var wx: float = float(pos.x) + 0.5 + float(dir.x) * dir_offset
		var wz: float = float(pos.y) + 0.5 + float(dir.y) * dir_offset
		var rot: float = CLIFF_DIR_ROT.get(dir, 0.0)

		# Pick a scene index different from the previous two straight pieces
		var scene_idx := rng.randi_range(0, CLIFF_STRAIGHT_SCENES.size() - 1)
		var attempts := 0
		while (
			(scene_idx == prev_straight_idx or scene_idx == prev_prev_straight_idx)
			and attempts < 10
		):
			scene_idx = rng.randi_range(0, CLIFF_STRAIGHT_SCENES.size() - 1)
			attempts += 1
		prev_prev_straight_idx = prev_straight_idx
		prev_straight_idx = scene_idx

		# Randomly mirror: flip 180° and/or mirror scale
		var flip := PI if rng.randi_range(0, 1) == 1 else 0.0
		var mirror_scale := -1.0 if rng.randi_range(0, 1) == 1 else 1.0
		var entity_data := {
			"scene_path": CLIFF_STRAIGHT_SCENES[scene_idx],
			"pos": Vector2(wx, wz),
			"player": 0,
			"rotation": rot + flip,
			"y_offset": float(edge["h_high"]) + cliff_y_offset,
			"entity_scale": mirror_scale,
		}
		current_map.placed_entities.append(entity_data)

	# 4. Refresh previews
	_refresh_entity_previews()


func _collect_cliff_edges(sz: Vector2i, slope_dirs: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for y in range(sz.y):
		for x in range(sz.x):
			var pos := Vector2i(x, y)
			var h := current_map.get_height_at(pos)
			var ct := current_map.get_cell_type_at(pos)

			for dir: Vector2i in CLIFF_CARDINAL_DIRS:
				var n := pos + dir
				if n.x < 0 or n.x >= sz.x or n.y < 0 or n.y >= sz.y:
					continue
				var nh := current_map.get_height_at(n)
				var diff := h - nh
				if diff < CLIFF_MIN_HEIGHT_DIFF:
					continue

				# Skip edges along slope ramp direction
				if ct == MapResource.CELL_SLOPE or ct == MapResource.CELL_WATER_SLOPE:
					if slope_dirs.has(pos):
						var axis: Vector2i = slope_dirs[pos]["dir"]
						if absi(dir.x) == absi(axis.x) and absi(dir.y) == absi(axis.y):
							continue

				var nct := current_map.get_cell_type_at(n)
				if nct == MapResource.CELL_SLOPE or nct == MapResource.CELL_WATER_SLOPE:
					if slope_dirs.has(n):
						var axis: Vector2i = slope_dirs[n]["dir"]
						if absi(dir.x) == absi(axis.x) and absi(dir.y) == absi(axis.y):
							continue

				(
					result
					. append(
						{
							"pos": pos,
							"dir": dir,
							"h_high": h,
							"h_low": nh,
						}
					)
				)
	return result


func _collect_slope_side_edges(sz: Vector2i, slope_dirs: Dictionary) -> Array[Dictionary]:
	## For each slope cell, check the two faces perpendicular to the ramp axis.
	## Two cases are handled:
	##   Forward  – slope cell is HIGHER than the flat neighbour (slope wall faces out)
	##   Reverse  – flat neighbour is HIGHER than the slope cell  (high-plateau wall beside the ramp)
	## "slope_side": true is tagged so the placement loop can use a 0.51 dir-offset
	## instead of 0.5, ensuring floor(entity_pos) lands in the accessible low cell
	## and the erase brush can reliably find the entity.
	var result: Array[Dictionary] = []
	var seen := {}
	for y in range(sz.y):
		for x in range(sz.x):
			var pos := Vector2i(x, y)
			if not slope_dirs.has(pos):
				continue
			var sd: Dictionary = slope_dirs[pos]
			var ramp_dir: Vector2i = sd["dir"]
			var low_h: float = sd["low_h"]
			var high_h: float = sd["high_h"]
			var rmin: int = sd["rmin"]
			var rmax: int = sd["rmax"]

			# Interpolated terrain height at this cell along the ramp
			var sc: int = pos.x * ramp_dir.x + pos.y * ramp_dir.y
			var t: float = 0.5 if rmax == rmin else float(sc - rmin) / float(rmax - rmin)
			var interp_h: float = lerpf(low_h, high_h, t)

			# Side directions are perpendicular to the ramp axis
			var side_dirs: Array[Vector2i]
			if ramp_dir.x != 0:
				side_dirs = [Vector2i(0, -1), Vector2i(0, 1)]
			else:
				side_dirs = [Vector2i(-1, 0), Vector2i(1, 0)]

			for side in side_dirs:
				var n := pos + side
				if n.x < 0 or n.x >= sz.x or n.y < 0 or n.y >= sz.y:
					continue
				# Only face non-slope cells
				var nct := current_map.get_cell_type_at(n)
				if nct == MapResource.CELL_SLOPE or nct == MapResource.CELL_WATER_SLOPE:
					continue
				var nh: float = current_map.get_height_at(n)
				# Deduplicate using the slope-cell + side direction as the physical edge key
				var key := Vector3i(pos.x, pos.y, (side.x + 2) * 10 + (side.y + 2))
				if seen.has(key):
					continue
				if interp_h - nh >= CLIFF_MIN_HEIGHT_DIFF:
					# Forward: slope side is higher → cliff faces outward from slope cell
					seen[key] = true
					(
						result
						. append(
							{
								"pos": pos,
								"dir": side,
								"h_high": interp_h,
								"h_low": nh,
								"slope_side": true,
							}
						)
					)
				elif nh - interp_h >= CLIFF_MIN_HEIGHT_DIFF:
					# Reverse: flat neighbour is higher (e.g. high plateau alongside the ramp)
					# Emit from the neighbour's perspective so rotation faces toward the slope.
					seen[key] = true
					(
						result
						. append(
							{
								"pos": n,
								"dir": Vector2i(-side.x, -side.y),
								"h_high": nh,
								"h_low": interp_h,
								"slope_side": true,
							}
						)
					)
	return result


func _compute_cliff_slope_directions(sz: Vector2i) -> Dictionary:
	## Flood-fill slope regions and compute each region's dominant ramp direction.
	## Returns per-cell dict: { dir:Vector2i, low_h:float, high_h:float, rmin:int, rmax:int }
	## rmin/rmax are signed coordinates along the ramp axis, used to interpolate height.
	var result := {}
	var visited := {}

	for y in range(sz.y):
		for x in range(sz.x):
			var pos := Vector2i(x, y)
			if visited.has(pos):
				continue
			var ct := current_map.get_cell_type_at(pos)
			if ct != MapResource.CELL_SLOPE and ct != MapResource.CELL_WATER_SLOPE:
				continue

			# Flood-fill the slope region
			var region: Array[Vector2i] = []
			var queue: Array[Vector2i] = [pos]
			visited[pos] = true
			while not queue.is_empty():
				var p: Vector2i = queue.pop_front()
				region.append(p)
				for d in CLIFF_CARDINAL_DIRS:
					var n := p + d
					if n.x < 0 or n.x >= sz.x or n.y < 0 or n.y >= sz.y:
						continue
					if visited.has(n):
						continue
					if current_map.get_cell_type_at(n) == ct:
						visited[n] = true
						queue.append(n)

			# Compute dominant direction and boundary height range for this region
			var total_diff := Vector2.ZERO
			var low_h := INF
			var high_h := -INF
			for p in region:
				var my_h: float = current_map.get_height_at(p)
				for d in CLIFF_CARDINAL_DIRS:
					var n := p + d
					if n.x < 0 or n.x >= sz.x or n.y < 0 or n.y >= sz.y:
						continue
					if current_map.get_cell_type_at(n) == ct:
						continue
					var nh: float = current_map.get_height_at(n)
					low_h = minf(low_h, nh)
					high_h = maxf(high_h, nh)
					var diff: float = nh - my_h
					total_diff += Vector2(d.x, d.y) * diff

			var direction: Vector2i
			if total_diff.length_squared() < 0.001:
				direction = Vector2i(1, 0)
			elif absf(total_diff.x) >= absf(total_diff.y):
				direction = Vector2i(1, 0) if total_diff.x > 0 else Vector2i(-1, 0)
			else:
				direction = Vector2i(0, 1) if total_diff.y > 0 else Vector2i(0, -1)

			if low_h == INF:
				low_h = 0.0
			if high_h == -INF:
				high_h = 0.0

			# Compute signed-coord range along ramp axis for height interpolation
			var rmin_coord := 999999
			var rmax_coord := -999999
			for p in region:
				var sc: int = p.x * direction.x + p.y * direction.y
				rmin_coord = mini(rmin_coord, sc)
				rmax_coord = maxi(rmax_coord, sc)

			for p in region:
				result[p] = {
					"dir": direction,
					"low_h": low_h,
					"high_h": high_h,
					"rmin": rmin_coord,
					"rmax": rmax_coord,
				}

	return result
