extends RadixStructure

var requires_seedling_to_start: bool = true
var _consumed_seedling_scene_path: String = ""
var _consumed_seedling_stats: Dictionary = {}
var _has_consumed_seedling: bool = false


func begin_seedling_self_construction(seedling: Unit) -> bool:
	if seedling == null or not is_instance_valid(seedling):
		return false
	if is_constructed() or _self_constructing or not is_under_construction():
		return false
	_capture_consumed_seedling(seedling)
	seedling.global_position = global_position
	_self_constructing = true
	is_construction_paused = false
	if _self_construction_speed <= 0.0:
		var scene_path := scene_file_path
		if scene_path.is_empty():
			scene_path = get_script().resource_path.replace(".gd", ".tscn")
		var construction_time = UnitConstants.get_default_properties(scene_path).get(
			"build_time", 5.0
		)
		_self_construction_speed = 1.0 / construction_time
	return true


func cancel_construction():
	_restore_consumed_seedling_on_cancel()
	super()


func _capture_consumed_seedling(seedling: Unit) -> void:
	if seedling == null or not is_instance_valid(seedling):
		return
	var scene_path: String = seedling.scene_file_path
	if scene_path.is_empty():
		scene_path = seedling.get_script().resource_path.replace(".gd", ".tscn")
	_consumed_seedling_scene_path = scene_path
	_consumed_seedling_stats = {
		"hp": seedling.hp,
		"hp_max": seedling.hp_max,
		"sight_range": seedling.sight_range,
		"attack_range": seedling.attack_range,
		"attack_damage": seedling.attack_damage,
		"armor": seedling.armor.duplicate(true),
		"movement_domains": seedling.movement_domains.duplicate(),
	}
	_has_consumed_seedling = true


func _restore_consumed_seedling_on_cancel() -> void:
	if not _has_consumed_seedling:
		return
	if player == null:
		return
	if _consumed_seedling_scene_path.is_empty():
		return
	var seedling_scene: PackedScene = load(_consumed_seedling_scene_path) as PackedScene
	if seedling_scene == null:
		return
	var restored_node: Node = seedling_scene.instantiate()
	if not (restored_node is Unit):
		restored_node.queue_free()
		return
	var restored_seedling: Unit = restored_node
	MatchSignals.setup_and_spawn_unit.emit(restored_seedling, global_transform, player, false)
	if _consumed_seedling_stats.has("hp_max"):
		restored_seedling.hp_max = _consumed_seedling_stats["hp_max"]
	if _consumed_seedling_stats.has("hp"):
		restored_seedling.hp = _consumed_seedling_stats["hp"]
	if _consumed_seedling_stats.has("sight_range"):
		restored_seedling.sight_range = _consumed_seedling_stats["sight_range"]
	if _consumed_seedling_stats.has("attack_range"):
		restored_seedling.attack_range = _consumed_seedling_stats["attack_range"]
	if _consumed_seedling_stats.has("attack_damage"):
		restored_seedling.attack_damage = _consumed_seedling_stats["attack_damage"]
	if _consumed_seedling_stats.has("armor"):
		restored_seedling.armor = _consumed_seedling_stats["armor"].duplicate(true)
	if _consumed_seedling_stats.has("movement_domains"):
		restored_seedling.movement_domains = (
			_consumed_seedling_stats["movement_domains"].duplicate()
		)
	_has_consumed_seedling = false
