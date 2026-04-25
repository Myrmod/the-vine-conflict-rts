extends CreepSource

const BULB_OPEN_DURATION := 0.22
const BULB_HOLD_OPEN_DURATION := 0.16
const BULB_CLOSE_DURATION := 0.22
const HEART_ENERGY_SPHERE_SHADER := preload("res://source/shaders/3d/heart_energy_sphere.gdshader")

@export_range(0.0, 20.0, 0.1) var player_color_emission_energy: float = 10.0
## Lower-intensity glow used for the spawn bulbs so their flat player color
## stays recognizable; the energy sphere keeps the higher value above.
@export_range(0.0, 20.0, 0.1)
var bulb_player_color_emission_energy: float = RadixPlayerColor.DEFAULT_EMISSION_ENERGY
@export_range(0.0, 0.5, 0.01) var sphere_flow_speed: float = 0.06
@export_range(0.1, 8.0, 0.1) var sphere_flow_scale: float = 2.2
@export_range(0.0, 3.0, 0.05) var sphere_rim_strength: float = 0.9
const MAX_PLAYER_COLOR_RETRIES := 60

var _spawn_bulbs: Array[Node3D] = []
var _next_spawn_bulb_idx: int = 0
var _bulb_tweens_by_id: Dictionary = {}
var _reserved_bulb_by_unit_id: Dictionary = {}
var _player_color_retry_count: int = 0


func _ready() -> void:
	super()
	_cache_spawn_bulbs()
	_apply_spawn_bulb_player_color()
	call_deferred("_apply_sphere_player_color_glow")


func get_parallel_production_count() -> int:
	# Radix Heart can produce one Seedling per pod at the same time.
	return max(1, _spawn_bulbs.size())


func handle_produced_unit_spawn(produced_unit: Node) -> bool:
	if not _is_seedling_unit(produced_unit):
		return false
	var unit_id: int = produced_unit.get_instance_id()
	var bulb: Node3D = _reserved_bulb_by_unit_id.get(unit_id, null)
	if _reserved_bulb_by_unit_id.has(unit_id):
		_reserved_bulb_by_unit_id.erase(unit_id)
	if bulb == null:
		bulb = _pick_spawn_bulb()
	if bulb == null:
		return false
	_position_seedling_at_bulb(produced_unit, bulb)
	_play_seedling_spawn_sequence(produced_unit, bulb)
	return true


func get_custom_spawn_transform_for_unit(produced_unit: Node):
	if not _is_seedling_unit(produced_unit):
		return null
	var bulb: Node3D = _pick_spawn_bulb()
	if bulb == null:
		return null
	_reserved_bulb_by_unit_id[produced_unit.get_instance_id()] = bulb
	var spawn_position: Vector3 = bulb.global_position
	if bulb.has_method("get_spawn_world_position"):
		spawn_position = bulb.get_spawn_world_position()
	return Transform3D(Basis(), spawn_position)


func _cache_spawn_bulbs() -> void:
	_spawn_bulbs.clear()
	for child: Node in get_children():
		if child is Node3D and child.name.begins_with("SpawningFlowerBulb"):
			_spawn_bulbs.append(child)


func _apply_spawn_bulb_player_color() -> void:
	if player == null:
		if _player_color_retry_count < MAX_PLAYER_COLOR_RETRIES:
			_player_color_retry_count += 1
			call_deferred("_apply_spawn_bulb_player_color")
		return
	_player_color_retry_count = 0
	for bulb in _spawn_bulbs:
		if bulb == null:
			continue
		if "player_color" in bulb:
			bulb.set("player_color", player.color)
		if "emission_energy" in bulb:
			bulb.set("emission_energy", bulb_player_color_emission_energy)


func _pick_spawn_bulb() -> Node3D:
	if _spawn_bulbs.is_empty():
		return null
	if _next_spawn_bulb_idx >= _spawn_bulbs.size():
		_next_spawn_bulb_idx = 0
	var bulb: Node3D = _spawn_bulbs[_next_spawn_bulb_idx]
	_next_spawn_bulb_idx = (_next_spawn_bulb_idx + 1) % _spawn_bulbs.size()
	return bulb


func _is_seedling_unit(unit_node: Node) -> bool:
	if unit_node == null or unit_node.get_script() == null:
		return false
	var scene_path: String = unit_node.get_script().resource_path.replace(".gd", ".tscn")
	return UnitConstants.get_scene_id(scene_path) == Enums.SceneId.RADIX_SEEDLING


func _position_seedling_at_bulb(unit_node: Node, bulb: Node3D) -> void:
	if unit_node is Node3D:
		var spawn_position: Vector3 = bulb.global_position
		if bulb.has_method("get_spawn_world_position"):
			spawn_position = bulb.get_spawn_world_position()
		(unit_node as Node3D).global_position = spawn_position


func _play_seedling_spawn_sequence(produced_unit: Node, bulb: Node3D) -> void:
	if produced_unit == null or bulb == null:
		return
	var bulb_id: int = bulb.get_instance_id()
	if _bulb_tweens_by_id.has(bulb_id):
		var previous_tween: Tween = _bulb_tweens_by_id[bulb_id]
		if is_instance_valid(previous_tween):
			previous_tween.kill()
	bulb.set("open_progress", 0.0)
	var tween := create_tween()
	_bulb_tweens_by_id[bulb_id] = tween
	tween.tween_property(bulb, "open_progress", 1.0, BULB_OPEN_DURATION)
	tween.tween_callback(
		func():
			if bulb.has_method("set_unit_placeholder_visible"):
				bulb.set_unit_placeholder_visible(false)
	)
	tween.tween_interval(BULB_HOLD_OPEN_DURATION)
	tween.tween_callback(
		func():
			if is_instance_valid(produced_unit):
				var rally_point: Node = find_child("RallyPoint")
				if rally_point != null:
					MatchSignals.navigate_unit_to_rally_point.emit(produced_unit, rally_point)
	)
	tween.tween_property(bulb, "open_progress", 0.0, BULB_CLOSE_DURATION)
	tween.tween_callback(
		func():
			if bulb.has_method("set_unit_placeholder_visible"):
				bulb.set_unit_placeholder_visible(true)
	)
	await tween.finished
	if _bulb_tweens_by_id.get(bulb_id) == tween:
		_bulb_tweens_by_id.erase(bulb_id)


func _apply_sphere_player_color_glow() -> void:
	if player == null:
		if _player_color_retry_count < MAX_PLAYER_COLOR_RETRIES:
			_player_color_retry_count += 1
			call_deferred("_apply_sphere_player_color_glow")
		return
	_player_color_retry_count = 0
	_apply_spawn_bulb_player_color()
	if not player.changed.is_connected(_on_player_changed):
		player.changed.connect(_on_player_changed)
	var geometry: Node = find_child("Geometry")
	if geometry == null:
		return
	var energy_material := _build_energy_sphere_material(player.color)
	if energy_material == null:
		return
	for mesh in _collect_mesh_instances(geometry):
		if not mesh.name.to_lower().contains("sphere"):
			continue
		_apply_glow_to_player_color_surfaces(mesh, energy_material)


func _on_player_changed() -> void:
	_apply_spawn_bulb_player_color()
	_apply_sphere_player_color_glow()


func _collect_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var results: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		results.append(root)
	for child: Node in root.get_children():
		results.append_array(_collect_mesh_instances(child))
	return results


func _apply_glow_to_player_color_surfaces(mesh: MeshInstance3D, glow_material: Material) -> void:
	if mesh.mesh == null:
		return
	var matched_any := false
	for surface_idx: int in range(mesh.mesh.get_surface_count()):
		if not _is_player_color_surface(mesh, surface_idx):
			continue
		mesh.set_surface_override_material(surface_idx, glow_material)
		matched_any = true
	if matched_any:
		return
	# Fallback: some imports lose PlayerColor resource names after import.
	# In that case tint the full sphere mesh so team color stays visible.
	for surface_idx: int in range(mesh.mesh.get_surface_count()):
		mesh.set_surface_override_material(surface_idx, glow_material)


func _build_energy_sphere_material(player_color: Color) -> ShaderMaterial:
	if HEART_ENERGY_SPHERE_SHADER == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = HEART_ENERGY_SPHERE_SHADER
	mat.set_shader_parameter("player_color", player_color)
	mat.set_shader_parameter("emission_strength", player_color_emission_energy)
	mat.set_shader_parameter("flow_speed", sphere_flow_speed)
	mat.set_shader_parameter("flow_scale", sphere_flow_scale)
	mat.set_shader_parameter("rim_strength", sphere_rim_strength)
	return mat


func _is_player_color_surface(mesh: MeshInstance3D, surface_idx: int) -> bool:
	if mesh == null or mesh.mesh == null:
		return false
	var original_material: Material = mesh.mesh.surface_get_material(surface_idx)
	if original_material != null and original_material.resource_name == "PlayerColor":
		return true
	var active_material: Material = mesh.get_active_material(surface_idx)
	return active_material != null and active_material.resource_name == "PlayerColor"
