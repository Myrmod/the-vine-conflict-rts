extends Node3D

@export var player_color: Color = Color(0.2, 0.8, 1.0)
@export var teleporter_rotation_speed: float = 1.0  # radians per second
@export var teleporter_scale_speed: float = 4.0

const TELEPORTER_SHADER = preload("res://tests/manual/TriangleAssemblyTest.gdshader")
const REVEAL_SHADER = preload("res://tests/manual/teleporter_reveal.gdshader")

var _teleporter: Node3D = null
var _teleporter_start_scale: float = 0.1
var _teleporter_full_scale: float = 1.0
var _teleporter_target_scale: float = 1.0
var _teleporter_y_scale: float = 1.0

var _model_mats: Array[ShaderMaterial] = []
var _model_mat_refs: Array = []  # [{mesh, surface_id}]
var _model_reveal_progress: float = 0.0
var _model_revealing: bool = false
var _model_dissolving: bool = false
var _model_y_min: float = 0.0
var _model_y_max: float = 1.0
@export var model_reveal_speed: float = 0.6

# Reverse sequence phases: expand_triangle → dissolve → collapse_triangle
enum ReversePhase { NONE, EXPAND_TRIANGLE, DISSOLVE, COLLAPSE_TRIANGLE }
var _reverse_phase: int = ReversePhase.NONE

var _camera: Camera3D = null
const CAM_PAN_SPEED := 10.0
const CAM_ZOOM_STEP := 1.5
const CAM_ZOOM_MIN := 3.0
const CAM_ZOOM_MAX := 40.0


func _ready() -> void:
	_camera = find_child("Camera3D", true, false) as Camera3D

	var model := find_child("Amuns_Wall_Pillar", true, false)
	if model == null:
		return

	var meshes := _collect_meshes(model)
	if meshes.is_empty():
		return

	var xz_radius := _compute_xz_radius(meshes) * 0.5
	var model_center := _compute_xz_center(meshes)
	_compute_y_bounds(_collect_model_meshes(model))

	var teleporter := find_child("Teleporter", true, false)
	if teleporter != null:
		_teleporter = teleporter as Node3D
		_apply_teleporter_materials(teleporter)
		_setup_teleporter(_teleporter, model_center, xz_radius)
		_compute_teleporter_y_scale()


func _unhandled_input(event: InputEvent) -> void:
	if _camera != null and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.size = clampf(_camera.size - CAM_ZOOM_STEP, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = clampf(_camera.size + CAM_ZOOM_STEP, CAM_ZOOM_MIN, CAM_ZOOM_MAX)

	if _teleporter == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_reverse_phase = ReversePhase.NONE
			_model_dissolving = false
			_teleporter.visible = true
			_teleporter.scale = Vector3(
				_teleporter_start_scale, _teleporter_y_scale, _teleporter_start_scale
			)
			_teleporter_target_scale = _teleporter_full_scale
			_model_revealing = false
			_model_reveal_progress = 0.0
			_remove_reveal_shaders()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Start reverse sequence: expand triangle first
			_model_revealing = false
			_model_dissolving = false
			_reverse_phase = ReversePhase.EXPAND_TRIANGLE
			_teleporter_target_scale = _teleporter_full_scale


func _process(delta: float) -> void:
	if _camera != null:
		var move := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1.0
		if not move.is_zero_approx():
			var speed := CAM_PAN_SPEED * (_camera.size / 15.0)
			var cam_move := Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, _camera.rotation.y)
			_camera.global_translate(cam_move * speed * delta)

	if _teleporter != null:
		_teleporter.rotate_y(teleporter_rotation_speed * delta)
		var current_xz := _teleporter.scale.x
		var new_xz := move_toward(
			current_xz, _teleporter_target_scale, teleporter_scale_speed * delta
		)
		_teleporter.scale = Vector3(new_xz, _teleporter_y_scale, new_xz)

		# --- Forward: start revealing model once teleporter reaches full scale ---
		if (
			_reverse_phase == ReversePhase.NONE
			and not _model_revealing
			and _model_mats.is_empty()
			and new_xz >= _teleporter_full_scale - 0.001
			and _teleporter_target_scale > 0.0
		):
			var m := find_child("Amuns_Wall_Pillar", true, false)
			if m != null:
				_apply_model_reveal_shader(_collect_model_meshes(m), false)
			_model_revealing = true

		# --- Reverse phase machine ---
		if _reverse_phase == ReversePhase.EXPAND_TRIANGLE:
			if new_xz >= _teleporter_full_scale - 0.001:
				# Triangle fully expanded → start dissolving model
				_reverse_phase = ReversePhase.DISSOLVE
				_model_dissolving = true
				_model_reveal_progress = 0.0
				var m := find_child("Amuns_Wall_Pillar", true, false)
				if m != null:
					_remove_reveal_shaders()
					_apply_model_reveal_shader(_collect_model_meshes(m), true)
		elif _reverse_phase == ReversePhase.DISSOLVE:
			pass  # handled below in dissolve block
		elif _reverse_phase == ReversePhase.COLLAPSE_TRIANGLE:
			if new_xz <= 0.001:
				_reverse_phase = ReversePhase.NONE
				_teleporter.visible = false

	if _model_revealing:
		_model_reveal_progress = move_toward(
			_model_reveal_progress, 1.0, model_reveal_speed * delta
		)
		_set_reveal_progress(_model_reveal_progress)
		if _model_reveal_progress >= 1.0:
			_model_revealing = false
			_remove_reveal_shaders()

	if _model_dissolving:
		_model_reveal_progress = move_toward(
			_model_reveal_progress, 1.0, model_reveal_speed * delta
		)
		_set_reveal_progress(_model_reveal_progress)
		if _model_reveal_progress >= 1.0:
			_model_dissolving = false
			_remove_reveal_shaders()
			# Dissolve done → collapse triangle
			_reverse_phase = ReversePhase.COLLAPSE_TRIANGLE
			_teleporter_target_scale = 0.0


func _collect_meshes(target: Node3D) -> Array:
	var meshes: Array = []
	if target is MeshInstance3D:
		meshes.append(target)
	meshes.append_array(target.find_children("*", "MeshInstance3D", true, false))
	return meshes


func _collect_model_meshes(model: Node3D) -> Array:
	# Collect meshes from model excluding the Teleporter subtree.
	var teleporter_node := find_child("Teleporter", true, false)
	var all := _collect_meshes(model)
	if teleporter_node == null:
		return all
	var result: Array = []
	for mesh in all:
		if (
			not (mesh as Node).is_ancestor_of(teleporter_node)
			and mesh != teleporter_node
			and not teleporter_node.is_ancestor_of(mesh)
		):
			result.append(mesh)
	return result


func _compute_xz_radius(meshes: Array) -> float:
	var max_r := 0.0
	for m: MeshInstance3D in meshes:
		var aabb := m.get_aabb()
		for xi in range(2):
			for zi in range(2):
				var corner := aabb.position + Vector3(aabb.size.x * xi, 0.0, aabb.size.z * zi)
				var wp: Vector3 = m.global_transform * corner
				var r := Vector2(wp.x, wp.z).length()
				max_r = maxf(max_r, r)
	return max_r


func _compute_xz_center(meshes: Array) -> Vector2:
	var xz_min := Vector2(INF, INF)
	var xz_max := Vector2(-INF, -INF)
	for m: MeshInstance3D in meshes:
		var aabb := m.get_aabb()
		for xi in range(2):
			for zi in range(2):
				var corner := aabb.position + Vector3(aabb.size.x * xi, 0.0, aabb.size.z * zi)
				var wp: Vector3 = m.global_transform * corner
				xz_min.x = minf(xz_min.x, wp.x)
				xz_min.y = minf(xz_min.y, wp.z)
				xz_max.x = maxf(xz_max.x, wp.x)
				xz_max.y = maxf(xz_max.y, wp.z)
	return (xz_min + xz_max) * 0.5


func _setup_teleporter(teleporter: Node3D, model_center: Vector2, xz_radius: float) -> void:
	# Convert world-space radius to the teleporter's local scale space,
	# accounting for any scale on the parent node.
	var parent_world_scale := 1.0
	if teleporter.get_parent() is Node3D:
		parent_world_scale = maxf(
			(teleporter.get_parent() as Node3D).global_transform.basis.get_scale().x, 0.0001
		)
	var full_local_scale := xz_radius / parent_world_scale
	_teleporter_start_scale = full_local_scale * 0.1
	_teleporter_full_scale = full_local_scale
	_teleporter_target_scale = full_local_scale
	teleporter.scale = Vector3(
		_teleporter_start_scale, _teleporter_start_scale, _teleporter_start_scale
	)
	teleporter.global_position = Vector3(
		model_center.x, teleporter.global_position.y, model_center.y
	)


func _compute_teleporter_y_scale() -> void:
	var model_height := _model_y_max - _model_y_min
	if model_height <= 0.001 or _teleporter == null:
		return
	var native_h := 0.0
	for mesh: MeshInstance3D in _collect_meshes(_teleporter):
		var aabb := mesh.get_aabb()
		native_h = maxf(native_h, aabb.size.y)
	if native_h <= 0.001:
		return
	var parent_world_scale := 1.0
	if _teleporter.get_parent() is Node3D:
		parent_world_scale = maxf(
			(_teleporter.get_parent() as Node3D).global_transform.basis.get_scale().y, 0.0001
		)
	_teleporter_y_scale = (model_height * 1.05) / (native_h * parent_world_scale)
	_teleporter.scale.y = _teleporter_y_scale


func _compute_y_bounds(meshes: Array) -> void:
	_model_y_min = INF
	_model_y_max = -INF
	for m: MeshInstance3D in meshes:
		var aabb := m.get_aabb()
		for xi in range(2):
			for yi in range(2):
				for zi in range(2):
					var corner := (
						aabb.position
						+ Vector3(aabb.size.x * xi, aabb.size.y * yi, aabb.size.z * zi)
					)
					var world_y := (m.global_transform * corner).y
					_model_y_min = minf(_model_y_min, world_y)
					_model_y_max = maxf(_model_y_max, world_y)
	# Extend the range slightly so the reveal animation overshoots the model top.
	var height := _model_y_max - _model_y_min
	_model_y_max += height * 0.1


func _apply_model_reveal_shader(meshes: Array, dissolve: bool = false) -> void:
	for mesh: MeshInstance3D in meshes:
		for surface_id in range(mesh.mesh.get_surface_count()):
			var smat := ShaderMaterial.new()
			smat.shader = REVEAL_SHADER
			smat.set_shader_parameter("reveal_progress", 0.0)
			smat.set_shader_parameter("dissolve_mode", dissolve)
			smat.set_shader_parameter("y_min", _model_y_min)
			smat.set_shader_parameter("y_max", _model_y_max)
			smat.set_shader_parameter("player_color", player_color)
			_copy_material_to_shader(smat, mesh.get_active_material(surface_id))
			mesh.set_surface_override_material(surface_id, smat)
			_model_mats.append(smat)
			_model_mat_refs.append({"mesh": mesh, "surface_id": surface_id})


func _remove_reveal_shaders() -> void:
	for ref in _model_mat_refs:
		var mesh := ref["mesh"] as MeshInstance3D
		if is_instance_valid(mesh):
			mesh.set_surface_override_material(ref["surface_id"], null)
	_model_mats.clear()
	_model_mat_refs.clear()


func _set_reveal_progress(p: float) -> void:
	for smat in _model_mats:
		smat.set_shader_parameter("reveal_progress", p)


static func _copy_material_to_shader(smat: ShaderMaterial, source: Material) -> void:
	if not source is StandardMaterial3D:
		return
	var std := source as StandardMaterial3D
	smat.set_shader_parameter("albedo", std.albedo_color)
	if std.albedo_texture != null:
		smat.set_shader_parameter("albedo_texture", std.albedo_texture)
		smat.set_shader_parameter("use_albedo_texture", true)
	smat.set_shader_parameter("metallic", std.metallic)
	smat.set_shader_parameter("roughness", std.roughness)
	smat.set_shader_parameter("specular", std.metallic_specular)
	if std.metallic_texture != null:
		smat.set_shader_parameter("metallic_texture", std.metallic_texture)
		smat.set_shader_parameter("use_metallic_texture", true)
	if std.roughness_texture != null:
		smat.set_shader_parameter("roughness_texture", std.roughness_texture)
		smat.set_shader_parameter("use_roughness_texture", true)
	if std.normal_enabled and std.normal_texture != null:
		smat.set_shader_parameter("normal_texture", std.normal_texture)
		smat.set_shader_parameter("use_normal_texture", true)
		smat.set_shader_parameter("normal_scale", std.normal_scale)


func _apply_teleporter_materials(teleporter: Node) -> void:
	var meshes := _collect_meshes(teleporter as Node3D)
	for mesh: MeshInstance3D in meshes:
		for surface_id in range(mesh.mesh.get_surface_count()):
			var source_mat := mesh.get_active_material(surface_id)
			var mat_name: String = mesh.mesh.surface_get_name(surface_id)
			if mat_name.is_empty() and source_mat != null:
				mat_name = source_mat.resource_name

			var smat := ShaderMaterial.new()
			smat.shader = TELEPORTER_SHADER
			smat.set_shader_parameter("player_color", player_color)

			if mat_name == "PlayerColor":
				smat.set_shader_parameter("alpha", 1.0)
				smat.set_shader_parameter("emission_strength", 3.0)
			else:
				smat.set_shader_parameter("alpha", 0.15)
				smat.set_shader_parameter("emission_strength", 0.0)

			mesh.set_surface_override_material(surface_id, smat)
