extends Node3D

## Test scene that auto-fires projectiles for every combat unit defined in UnitConstants.
## Each unit gets its own lane, firing at attack_range distance on its attack_interval.
## WASD/arrows to pan, scroll to zoom, middle mouse to rotate.

const VineArcScript = preload("res://source/factions/neutral/structures/ResourceNode/VineArc.gd")

const LANE_SPACING: float = 5.0
const FIRE_Y: float = 0.15
const CAM_SPEED: float = 15.0
const ZOOM_STEP: float = 1.0
const ZOOM_MIN: float = 3.0
const ZOOM_MAX: float = 60.0

const PRODUCTION_TYPE_FALLBACK_MODELS: Dictionary = {
	Enums.ProductionTabType.INFANTRY: "models/FallbackInfantry/soldier_final_animations_fbx.glb",
}
const MOUSE_ROTATION_SPEED: float = 0.005

var _lanes: Array[Dictionary] = []
var _rotating: bool = false
var _rotate_start_mouse: Vector2 = Vector2.ZERO
var _rotate_start_cam_pos: Vector3 = Vector3.ZERO

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	var lane_index: int = 0
	for scene_path: String in UnitConstants.DEFAULT_PROPERTIES:
		var props: Dictionary = UnitConstants.DEFAULT_PROPERTIES[scene_path]
		if not props.has("attack_damage") or not props.has("projectile_type"):
			continue

		var unit_name: String = props.get("unit_name", scene_path.get_file().get_basename())
		var attack_range: float = props.get("attack_range", 5.0)
		var attack_interval: float = props.get("attack_interval", 1.0)
		var projectile_type: int = props.get("projectile_type", -1)
		var projectile_config: Dictionary = props.get("projectile_config", {}).duplicate()
		var projectile_origin: Vector3 = props.get("projectile_origin", Vector3.ZERO)
		var damage: float = props.get("attack_damage", 1.0)

		var from_pos: Vector3 = Vector3(lane_index * LANE_SPACING, FIRE_Y, 3.0)
		var to_pos: Vector3 = Vector3(lane_index * LANE_SPACING, FIRE_Y, 3.0 - attack_range)

		# Label
		var label: Label3D = Label3D.new()
		label.text = unit_name
		label.position = Vector3(lane_index * LANE_SPACING, 2.0, 4.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 36
		label.modulate = Color.WHITE
		add_child(label)

		# Unit model — instantiate the real scene, strip scripts to avoid Match dependencies
		var wrapper: Node3D = Node3D.new()
		wrapper.position = from_pos
		add_child(wrapper)
		var unit_scene: PackedScene = load(scene_path)
		if unit_scene:
			var unit_instance: Node3D = unit_scene.instantiate()
			_strip_scripts(unit_instance)
			_apply_fallback_models(unit_instance, props)
			wrapper.add_child(unit_instance)
		wrapper.look_at(to_pos, Vector3.UP)
		# Rotate projectile_origin by the unit's facing so it matches in-game behavior
		projectile_origin = wrapper.basis * projectile_origin

		# Target marker
		var target_mesh: MeshInstance3D = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.15
		sphere.height = 0.3
		target_mesh.mesh = sphere
		target_mesh.position = to_pos + Vector3(0, 0.15, 0)
		var target_mat: StandardMaterial3D = StandardMaterial3D.new()
		target_mat.albedo_color = Color(1.0, 0.2, 0.2)
		target_mesh.material_override = target_mat
		add_child(target_mesh)

		# Timer for auto-firing
		var timer: Timer = Timer.new()
		timer.wait_time = attack_interval
		timer.autostart = true
		add_child(timer)

		var lane: Dictionary = {
			"from": from_pos + projectile_origin,
			"to": to_pos,
			"type": projectile_type,
			"config": projectile_config,
			"damage": damage,
			"timer": timer,
		}
		timer.timeout.connect(_fire_lane.bind(lane))
		_lanes.append(lane)

		lane_index += 1

	# --- Electric discharge (VineArc) demo ---
	_add_arc_demo(lane_index)


func _fire_lane(lane: Dictionary) -> void:
	var config: Dictionary = lane.config.duplicate()
	config["damage"] = 0.0  # no actual damage in test
	Projectile.fire(lane.type, lane.from, lane.to, config)


func _add_arc_demo(lane_index: int) -> void:
	var x_offset: float = lane_index * LANE_SPACING
	var from_pos := Vector3(x_offset, FIRE_Y + 0.5, 3.0)
	var to_pos := Vector3(x_offset, FIRE_Y + 0.5, -4.0)

	# Label
	var label := Label3D.new()
	label.text = "VineArc (fBm)"
	label.position = Vector3(x_offset, 2.0, 4.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.modulate = Color.WHITE
	add_child(label)

	# Endpoint markers
	for pos: Vector3 in [from_pos, to_pos]:
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.15
		sphere.height = 0.3
		marker.mesh = sphere
		marker.position = pos
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.9, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.9, 1.0)
		marker.material_override = mat
		add_child(marker)

	# Arc — spawn on a repeating timer since arcs self-destruct
	var arc_timer := Timer.new()
	arc_timer.wait_time = 0.5
	arc_timer.autostart = true
	add_child(arc_timer)
	arc_timer.timeout.connect(_spawn_arc.bind(from_pos, to_pos))
	_spawn_arc(from_pos, to_pos)


func _spawn_arc(from: Vector3, to: Vector3) -> void:
	var arc := MeshInstance3D.new()
	arc.set_script(VineArcScript)
	add_child(arc)
	arc.setup(from, to)


func _process(delta: float) -> void:
	_handle_camera_movement(delta)


func _handle_camera_movement(delta: float) -> void:
	var move: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if not move.is_zero_approx():
		move = move.normalized()
		var cam_move: Vector3 = (
			Vector3(move.x, 0, move.y).rotated(Vector3.UP, _camera.rotation.y) * CAM_SPEED * delta
		)
		_camera.global_translate(cam_move)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_rotating = true
				_rotate_start_mouse = event.position
				_rotate_start_cam_pos = _camera.global_position
			else:
				_rotating = false
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_camera.size = clampf(_camera.size - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_camera.size = clampf(_camera.size + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	if event is InputEventMouseMotion and _rotating:
		var pivot: Vector3 = _get_camera_pivot()
		var angle: float = (event.position.x - _rotate_start_mouse.x) * MOUSE_ROTATION_SPEED
		var diff: Vector3 = _rotate_start_cam_pos - pivot
		var rotated_diff: Vector3 = diff.rotated(-Vector3.UP, angle)
		_camera.global_position = pivot + rotated_diff
		_camera.global_transform = _camera.global_transform.looking_at(pivot, Vector3.UP)


func _get_camera_pivot() -> Vector3:
	var screen_center: Vector2 = _camera.get_viewport().get_visible_rect().size / 2.0
	var ground_plane: Plane = Plane(Vector3.UP, 0.0)
	var origin: Vector3 = _camera.project_ray_origin(screen_center)
	var dir: Vector3 = _camera.project_ray_normal(screen_center)
	var hit: Variant = ground_plane.intersects_ray(origin, dir)
	if hit:
		return hit
	return _camera.global_position + _camera.global_transform.basis.z * -10.0


func _strip_scripts(node: Node) -> void:
	var s: Script = node.get_script()
	if s != null and not s.resource_path.ends_with("ModelHolder.gd"):
		node.set_script(null)
	for child in node.get_children():
		_strip_scripts(child)


func _apply_fallback_models(node: Node, props: Dictionary) -> void:
	var tab_type = props.get("production_tab_type", -1)
	if not PRODUCTION_TYPE_FALLBACK_MODELS.has(tab_type):
		return
	var fallback_path: String = PRODUCTION_TYPE_FALLBACK_MODELS[tab_type]
	for child in node.get_children():
		if child is ModelHolder and child.model_path.is_empty():
			child.model_path = fallback_path
