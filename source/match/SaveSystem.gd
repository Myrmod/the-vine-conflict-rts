extends Node

const SAVE_DIR := "user://saves/"

signal game_saved
signal game_loaded(save: SaveGameResource)


func save_game(save_name: String = "") -> Error:
	var match_node: Match = _get_match()
	if match_node == null:
		push_error("SaveSystem: no active Match node found")
		return ERR_DOES_NOT_EXIST

	var save := _serialize_match(match_node)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	if save_name.is_empty():
		save_name = get_default_save_name(match_node)
	var path := SAVE_DIR + save_name + ".tres"

	var err := ResourceSaver.save(save, path)
	if err != OK:
		push_error("SaveSystem: failed to save game: %s" % error_string(err))
		return err

	if FeatureFlags.get("debug_save_json"):
		_save_json_debug(save, save_name)

	game_saved.emit()
	return OK


func load_game(path: String = "") -> SaveGameResource:
	if path.is_empty():
		path = _find_latest_save()
	if path.is_empty() or not FileAccess.file_exists(path):
		push_warning("SaveSystem: no save file at %s" % path)
		return null
	var save = ResourceLoader.load(path) as SaveGameResource
	if save == null:
		push_error("SaveSystem: failed to load save file")
		return null
	return save


func has_save() -> bool:
	return not list_saves().is_empty()


func list_saves() -> Array[String]:
	var saves: Array[String] = []
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return saves
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return saves
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if (
			not dir.current_is_dir()
			and file_name.ends_with(".tres")
			and not file_name.ends_with(".import")
		):
			saves.append(SAVE_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	saves.sort()
	saves.reverse()
	return saves


func get_default_save_name(match_node: Match = null) -> String:
	var map_name := "save"
	if match_node != null and not match_node.map_source_path.is_empty():
		map_name = (match_node.map_source_path.get_file().get_basename())
	var ts := Time.get_datetime_string_from_system()
	ts = ts.replace("T", "_").replace(":", "_").replace("-", "_")
	return map_name + "_" + ts


func _find_latest_save() -> String:
	var saves := list_saves()
	if saves.is_empty():
		return ""
	return saves[0]


func serialize_match_to_dict(match_node: Match) -> Dictionary:
	var save := _serialize_match(match_node)
	return _save_to_dict(save)


func deserialize_match_from_dict(data: Dictionary) -> SaveGameResource:
	return _dict_to_save(data)


func _serialize_match(match_node: Match) -> SaveGameResource:
	var save := SaveGameResource.new()
	save.timestamp = Time.get_datetime_string_from_system()
	save.map_source_path = match_node.map_source_path
	save.match_tick = Match.tick
	save.rng_state = Match.rng.state
	save.rng_seed = Match.rng.seed

	# Serialize match settings
	save.match_settings_data = _serialize_settings(match_node.settings)

	# Serialize players
	var players := match_node.get_tree().get_nodes_in_group("players")
	players.sort_custom(func(a, b): return a.id < b.id)
	for player in players:
		save.players_data.append(_serialize_player(player))

	# Serialize entities
	var ids: Array = EntityRegistry.entities.keys()
	ids.sort()
	for eid in ids:
		var entity = EntityRegistry.entities[eid]
		if entity == null or not is_instance_valid(entity):
			continue
		if entity is Unit:
			var ed := _serialize_entity(entity)
			save.entities_data.append(ed)
		elif entity is ResourceUnit:
			save.entities_data.append(_serialize_resource_entity(entity))
		# Other entity types (VineSpawner, etc.) are part of the map and don't need saving
	save.entity_registry_next_id = EntityRegistry._next_id

	# Serialize pending commands
	for tick_key in CommandBus.commands:
		if tick_key > Match.tick:
			for cmd in CommandBus.commands[tick_key]:
				save.pending_commands.append(cmd.duplicate(true))

	return save


func _serialize_settings(settings: Resource) -> Dictionary:
	var data := {}
	data["visibility"] = settings.visibility
	data["visible_player"] = settings.visible_player
	var players_arr: Array[Dictionary] = []
	for ps in settings.players:
		(
			players_arr
			. append(
				{
					"color": ps.color.to_html(),
					"team": ps.team,
					"faction": ps.faction,
					"controller": ps.controller,
					"spawn_index": ps.spawn_index,
					"uuid": ps.get("uuid") if ps.get("uuid") else "",
				}
			)
		)
	data["players"] = players_arr
	return data


func _deserialize_settings(data: Dictionary) -> Resource:
	var settings = load("res://source/data-model/MatchSettings.gd").new()
	settings.visibility = data.get("visibility", 0)
	settings.visible_player = data.get("visible_player", 0)
	for pd in data.get("players", []):
		var ps := PlayerSettings.new()
		ps.color = Color.html(pd.get("color", "0000ff"))
		ps.team = pd.get("team", 0)
		ps.faction = pd.get("faction", Enums.Faction.AMUNS)
		ps.controller = pd.get("controller", Constants.PlayerType.SIMPLE_CLAIRVOYANT_AI)
		ps.spawn_index = pd.get("spawn_index", -1)
		if pd.has("uuid"):
			ps.uuid = pd["uuid"]
		settings.players.append(ps)
	return settings


func _serialize_player(player: Player) -> Dictionary:
	return {
		"id": player.id,
		"uuid": player.get("uuid") if player.get("uuid") else "",
		"credits": player.credits,
		"energy": player.energy,
		"color": player.color.to_html(),
		"team": player.team,
		"faction": player.faction,
		"support_powers": player.support_powers.duplicate(true),
	}


func _serialize_resource_entity(entity) -> Dictionary:
	var spath: String = entity.scene_file_path
	if spath.is_empty():
		spath = entity.get_script().resource_path.replace(".gd", ".tscn")
	var data := {
		"entity_type": "resource",
		"entity_id": entity.id,
		"scene_path": spath,
		"position": _vec3_to_arr(entity.global_position),
		"rotation": _vec3_to_arr(entity.rotation),
	}
	if entity.get("resource") != null:
		data["resource_amount"] = entity.resource
	return data


func _serialize_entity(entity) -> Dictionary:
	var spath: String = entity.scene_file_path
	if spath.is_empty():
		spath = entity.get_script().resource_path.replace(".gd", ".tscn")
	# Use the authoritative tick transform from the Movement node when
	# available.  entity.global_position is the *interpolated* visual
	# position (lerped between ticks by _process) and will be slightly
	# off from the deterministic value, causing desyncs on restore.
	var pos: Vector3 = entity.global_position
	var rot: Vector3 = entity.rotation
	var movement = entity.find_child("Movement")
	if movement and movement._initialized:
		pos = movement._tick_transform.origin
		rot = movement._tick_transform.basis.get_euler()
	var data := {
		"entity_type": "unit",
		"entity_id": entity.id,
		"player_id": entity.player.id if entity.player else -1,
		"scene_path": spath,
		"position": _vec3_to_arr(pos),
		"rotation": _vec3_to_arr(rot),
		"hp": entity.hp,
		"hp_max": entity.hp_max,
		"stopped": entity._stopped,
	}

	# Action serialization
	data["action"] = _serialize_action(entity.action)

	# Command queue
	var queue_node = entity.find_child("UnitCommandQueue")
	if queue_node:
		data["command_queue"] = _serialize_command_queue(queue_node)
	else:
		data["command_queue"] = []

	# Structure-specific
	var is_structure: bool = entity.get_script().resource_path.find("structures/") >= 0
	data["is_structure"] = is_structure
	if is_structure:
		data["construction_progress"] = entity.get("_construction_progress")
		data["is_selling"] = entity.get("is_selling")
		data["is_repairing"] = entity.get("is_repairing")
		data["is_construction_paused"] = entity.get("is_construction_paused")
		data["is_disabled"] = entity.get("is_disabled")
		data["sell_ticks_remaining"] = entity.get("_sell_ticks_remaining")
		data["energy_provided"] = entity.get("energy_provided")
		data["energy_required"] = entity.get("energy_required")
		data["trickle_cost"] = entity.get("_trickle_cost")
		data["trickle_cost_deducted"] = entity.get("_trickle_cost_deducted")
		data["self_constructing"] = entity.get("_self_constructing")
		data["self_construction_speed"] = entity.get("_self_construction_speed")
		data["ready_structures"] = entity.get("_ready_structures").duplicate()

		# Production queue
		var pq = entity.find_child("ProductionQueue")
		if pq:
			data["production_queue"] = _serialize_production_queue(pq)
		else:
			data["production_queue"] = []

		# Rally point
		var rally = entity.find_child("RallyPoint")
		if rally:
			data["rally_position"] = _vec3_to_arr(rally.global_position)
			var target_u = rally.get("target_unit")
			data["rally_target_unit"] = (
				target_u.id if target_u and is_instance_valid(target_u) else -1
			)
		else:
			data["rally_position"] = null
			data["rally_target_unit"] = -1

	return data


func _serialize_action(action_node) -> Dictionary:
	if action_node == null or not is_instance_valid(action_node):
		return {"type": "none"}

	var script_path: String = action_node.get_script().resource_path
	var type_name: String = script_path.get_file().replace(".gd", "")
	var data := {"type": type_name}

	match type_name:
		"Moving":
			data["target_position"] = _vec3_to_arr(action_node._target_position)
		"ReverseMoving":
			data["target_position"] = _vec3_to_arr(action_node._target_position)
		"MovingToUnit":
			var t = action_node._target_unit
			data["target_unit_id"] = t.id if t and is_instance_valid(t) else -1
		"Following":
			var t = action_node._target_unit
			data["target_unit_id"] = t.id if t and is_instance_valid(t) else -1
		"AutoAttacking":
			var t = action_node._target_unit
			data["target_unit_id"] = t.id if t and is_instance_valid(t) else -1
		"Constructing":
			var t = action_node._target_unit
			data["target_unit_id"] = t.id if t and is_instance_valid(t) else -1
		"CollectingResourcesSequentially":
			data["state"] = action_node._state
			var r = action_node._resource_unit
			data["resource_unit_id"] = r.id if r and is_instance_valid(r) else -1
			var cc = action_node._cc_unit
			data["cc_unit_id"] = cc.id if cc and is_instance_valid(cc) else -1
		"AttackMoving":
			data["target_position"] = _vec3_to_arr(action_node._target_position)
			data["state"] = action_node._state
		"HoldPosition":
			pass
		"Patrolling":
			data["point_a"] = _vec3_to_arr(action_node._point_a)
			data["point_b"] = _vec3_to_arr(action_node._point_b)
			data["moving_to_b"] = action_node._moving_to_b
		"WaitingForTargets":
			pass

	return data


func _serialize_command_queue(queue_node) -> Array:
	var result: Array = []
	for cmd in queue_node.get_all():
		result.append(cmd.duplicate(true))
	return result


func _serialize_production_queue(pq) -> Array:
	var result: Array = []
	for el in pq.get_elements():
		(
			result
			. append(
				{
					"unit_scene_path": el.unit_prototype.resource_path,
					"time_total": el.time_total,
					"time_left": el.time_left,
					"paused": el.paused,
					"completed": el.completed,
					"trickle_cost": el.trickle_cost.duplicate(),
					"trickle_deducted": el.trickle_deducted,
				}
			)
		)
	return result


# ── Deserialization helpers ──────────────────────────────────────────


func restore_action_on_unit(unit, action_data: Dictionary) -> void:
	if action_data.get("type", "none") == "none":
		return

	var type_name: String = action_data["type"]
	match type_name:
		"Moving":
			unit.action = Actions.Moving.new(_arr_to_vec3(action_data["target_position"]))
		"ReverseMoving":
			unit.action = Actions.ReverseMoving.new(_arr_to_vec3(action_data["target_position"]))
		"MovingToUnit":
			var target = EntityRegistry.get_unit(action_data["target_unit_id"])
			if target:
				unit.action = Actions.MovingToUnit.new(target)
		"Following":
			var target = EntityRegistry.get_unit(action_data["target_unit_id"])
			if target:
				unit.action = Actions.Following.new(target)
		"AutoAttacking":
			var target = EntityRegistry.get_unit(action_data["target_unit_id"])
			if target:
				unit.action = Actions.AutoAttacking.new(target)
		"Constructing":
			var target = EntityRegistry.get_unit(action_data["target_unit_id"])
			if target:
				unit.action = Actions.Constructing.new(target)
		"CollectingResourcesSequentially":
			var res_unit = EntityRegistry.get_unit(action_data.get("resource_unit_id", -1))
			if res_unit:
				unit.action = Actions.CollectingResourcesSequentially.new(res_unit)
		"AttackMoving":
			unit.action = Actions.AttackMoving.new(_arr_to_vec3(action_data["target_position"]))
		"HoldPosition":
			unit.action = Actions.HoldPosition.new()
		"Patrolling":
			unit.action = (
				Actions
				. Patrolling
				. new(
					_arr_to_vec3(action_data["point_a"]),
					_arr_to_vec3(action_data["point_b"]),
				)
			)
		"WaitingForTargets":
			unit.action = Actions.WaitingForTargets.new()


func restore_production_queue(pq, data: Array) -> void:
	for el_data in data:
		var proto = load(el_data["unit_scene_path"])
		if proto == null:
			continue
		var el = pq.ProductionQueueElement.new()
		el.unit_prototype = proto
		el.time_total = el_data["time_total"]
		el.time_left = el_data["time_left"]
		el.paused = el_data["paused"]
		el.completed = el_data["completed"]
		el.trickle_cost = el_data.get("trickle_cost", {})
		el.trickle_deducted = el_data.get("trickle_deducted", 0.0)
		pq._queue.push_back(el)
		pq.element_enqueued.emit(el)


func restore_command_queue(queue_node, data: Array) -> void:
	for cmd in data:
		queue_node.enqueue(cmd)


# ── Conversion helpers ───────────────────────────────────────────────


func _vec3_to_arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _arr_to_vec3(a) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO


func _save_to_dict(save: SaveGameResource) -> Dictionary:
	return {
		"version": save.version,
		"timestamp": save.timestamp,
		"map_source_path": save.map_source_path,
		"match_tick": save.match_tick,
		"rng_state": save.rng_state,
		"rng_seed": save.rng_seed,
		"match_settings_data": save.match_settings_data,
		"players_data": save.players_data,
		"entities_data": save.entities_data,
		"entity_registry_next_id": save.entity_registry_next_id,
		"pending_commands": save.pending_commands,
	}


func _dict_to_save(data: Dictionary) -> SaveGameResource:
	var save := SaveGameResource.new()
	save.version = data.get("version", 1)
	save.timestamp = data.get("timestamp", "")
	save.map_source_path = data.get("map_source_path", "")
	save.match_tick = data.get("match_tick", 0)
	save.rng_state = data.get("rng_state", 0)
	save.rng_seed = data.get("rng_seed", 0)
	save.match_settings_data = data.get("match_settings_data", {})
	save.players_data = data.get("players_data", [])
	save.entities_data = data.get("entities_data", [])
	save.entity_registry_next_id = data.get("entity_registry_next_id", 1)
	save.pending_commands = data.get("pending_commands", [])
	return save


func _save_json_debug(save: SaveGameResource, save_name: String = "savegame") -> void:
	var dict := _save_to_dict(save)
	var json_str := JSON.stringify(dict, "\t")
	var path := SAVE_DIR + save_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)


func _get_match() -> Match:
	var tree := get_tree()
	if tree == null:
		return null
	var current := tree.current_scene
	if current is Match:
		return current
	# Search for Match node in the tree
	for node in tree.get_nodes_in_group(""):
		if node is Match:
			return node
	return tree.root.find_child("Match", true, false) as Match
