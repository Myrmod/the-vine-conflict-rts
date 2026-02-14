extends Control

## Renders a top-down preview of a map using a SubViewport with an orthographic
## camera, then overlays numbered spawn position markers.

const SPAWN_CIRCLE_RADIUS := 12.0
const SPAWN_FONT_SIZE := 16
const SPAWN_CIRCLE_COLOR := Color(0.9, 0.9, 0.2, 0.9)
const SPAWN_BORDER_COLOR := Color(0.0, 0.0, 0.0, 0.8)
const SPAWN_LABEL_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const VIEWPORT_RESOLUTION := 512

var _map_size := Vector2.ZERO
var _spawn_positions: Array[Vector3] = []
var _viewport: SubViewport = null
var _map_instance: Node = null
var _camera: Camera3D = null
var _texture_rect: TextureRect = null


func _ready():
	# Create the TextureRect that displays the viewport render
	_texture_rect = TextureRect.new()
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture_rect.show_behind_parent = true
	add_child(_texture_rect)

	# Create the SubViewport for rendering the map
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(VIEWPORT_RESOLUTION, VIEWPORT_RESOLUTION)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.transparent_bg = false
	_viewport.own_world_3d = true
	add_child(_viewport)


func set_map_data(map_path: String) -> void:
	# Clean up previous viewport contents
	if _map_instance and is_instance_valid(_map_instance):
		_map_instance.queue_free()
		_map_instance = null
	if _camera and is_instance_valid(_camera):
		_camera.queue_free()
		_camera = null

	_spawn_positions = []
	_map_size = Vector2.ZERO

	var map_scene = load(map_path)
	if map_scene == null:
		queue_redraw()
		return

	_map_instance = map_scene.instantiate()

	# Read map size
	_map_size = _map_instance.size if "size" in _map_instance else Vector2(50, 50)

	# Read spawn positions
	var spawn_points_node = _map_instance.find_child("SpawnPoints")
	if spawn_points_node:
		for child in spawn_points_node.get_children():
			if child is Marker3D:
				_spawn_positions.append(child.position)

	# Remove gameplay nodes that require Match context (navigation, etc.)
	_strip_gameplay_nodes(_map_instance)

	# Add map to the viewport
	_viewport.add_child(_map_instance)

	# Set viewport aspect ratio to match map
	var aspect = _map_size.x / _map_size.y
	if aspect >= 1.0:
		_viewport.size = Vector2i(VIEWPORT_RESOLUTION, int(VIEWPORT_RESOLUTION / aspect))
	else:
		_viewport.size = Vector2i(int(VIEWPORT_RESOLUTION * aspect), VIEWPORT_RESOLUTION)

	# Create orthographic camera looking straight down
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Position camera above the center of the map
	var center = Vector3(_map_size.x * 0.5, 50.0, _map_size.y * 0.5)
	_camera.global_transform = Transform3D(Basis(), center)
	_camera.rotate_x(-PI / 2.0)  # Look straight down
	# Set ortho size to cover the map (size is half-height in Godot)
	_camera.size = max(_map_size.x, _map_size.y)
	_camera.near = 0.1
	_camera.far = 200.0

	_viewport.add_child(_camera)

	# Render several frames so the sky radiance map is computed before capture.
	# Metallic surfaces need environment reflections which aren't ready on frame 1.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Set the texture on the TextureRect (updates live while UPDATE_ALWAYS)
	_texture_rect.texture = _viewport.get_texture()
	# After 3 frames, freeze the viewport to save performance
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	queue_redraw()


func _draw() -> void:
	if _map_size == Vector2.ZERO:
		return

	# Calculate the actual rendered area within the TextureRect (accounting for aspect fit)
	var tex_size = Vector2(_viewport.size)
	var control_size = size
	var scale_factor: float
	var offset: Vector2

	var tex_aspect = tex_size.x / tex_size.y
	var ctrl_aspect = control_size.x / control_size.y

	if tex_aspect > ctrl_aspect:
		# Width-limited
		scale_factor = control_size.x / tex_size.x
		var rendered_height = tex_size.y * scale_factor
		offset = Vector2(0, (control_size.y - rendered_height) * 0.5)
	else:
		# Height-limited
		scale_factor = control_size.y / tex_size.y
		var rendered_width = tex_size.x * scale_factor
		offset = Vector2((control_size.x - rendered_width) * 0.5, 0)

	var pixels_per_unit_x = (tex_size.x / _map_size.x) * scale_factor
	var pixels_per_unit_y = (tex_size.y / _map_size.y) * scale_factor

	# Draw spawn points on top of the rendered map
	var font = ThemeDB.fallback_font
	for i in range(_spawn_positions.size()):
		var spawn = _spawn_positions[i]
		var preview_pos = Vector2(spawn.x * pixels_per_unit_x, spawn.z * pixels_per_unit_y) + offset
		# Border circle
		draw_circle(preview_pos, SPAWN_CIRCLE_RADIUS + 2.0, SPAWN_BORDER_COLOR)
		# Fill circle
		draw_circle(preview_pos, SPAWN_CIRCLE_RADIUS, SPAWN_CIRCLE_COLOR)
		# Number
		var label_text = str(i + 1)
		var text_size_v = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, SPAWN_FONT_SIZE)
		var text_pos = preview_pos - text_size_v * 0.5 + Vector2(0, text_size_v.y * 0.75)
		draw_string(font, text_pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, SPAWN_FONT_SIZE, SPAWN_LABEL_COLOR)


func _strip_gameplay_nodes(node: Node) -> void:
	## Recursively remove all scripts from the scene tree so no gameplay
	## _ready() code runs (e.g. MovementObstacle accessing Match.navigation).
	## The visual geometry still renders fine without scripts.
	for i in range(node.get_child_count()):
		var child = node.get_child(i)
		_strip_gameplay_nodes(child)
	node.set_script(null)
