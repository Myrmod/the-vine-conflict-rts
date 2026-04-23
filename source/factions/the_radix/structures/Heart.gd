extends CreepSource

const BULB_OPEN_DURATION := 0.22
const BULB_HOLD_OPEN_DURATION := 0.16
const BULB_CLOSE_DURATION := 0.22

var _spawn_bulbs: Array[Node3D] = []
var _next_spawn_bulb_idx: int = 0
var _bulb_tweens_by_id: Dictionary = {}
var _reserved_bulb_by_unit_id: Dictionary = {}


func _ready() -> void:
	super()
	_cache_spawn_bulbs()


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
