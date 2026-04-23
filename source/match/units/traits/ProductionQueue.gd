extends Node

signal element_enqueued(element)
signal element_removed(element)


class ProductionQueueElement:
	extends Resource
	var unit_prototype = null
	var time_total = null
	var time_left = null:
		set(value):
			time_left = value
			emit_changed()
	var paused := false:
		set(value):
			paused = value
			emit_changed()
	## True when this off-field structure has finished production and awaits placement.
	var completed := false:
		set(value):
			completed = value
			emit_changed()
	## True for HUD-only entries that mirror external construction progress.
	## These must never be finalized by this queue.
	var is_tracking_only := false:
		set(value):
			is_tracking_only = value
			emit_changed()
	## Entity ID of the tracked under-construction structure (for HUD interactions).
	var tracking_entity_id: int = -1
	## When non-empty, cost trickles over build_time instead of being deducted upfront.
	var trickle_cost: Dictionary = {}
	var trickle_deducted: float = 0.0

	func progress():
		return (time_total - time_left) / time_total

	## Returns true when this element is actively counting down
	## (i.e. within the first non-paused, non-completed elements in the queue).
	func is_producing(queue_array: Array, parallel_slots: int = 1) -> bool:
		if paused or completed or is_tracking_only:
			return false
		parallel_slots = max(1, parallel_slots)
		var seen_active := 0
		for el in queue_array:
			if el.paused or el.completed or el.is_tracking_only:
				continue
			if seen_active >= parallel_slots:
				return false
			if el == self:
				return true
			seen_active += 1
		return false


var _queue = []

@onready var _unit = get_parent()


func _ready():
	MatchSignals.tick_advanced.connect(_on_tick_advanced)


func _on_tick_advanced():
	if _queue.is_empty():
		return
	# Don't tick production while the parent structure is disabled or selling.
	if _unit != null and (_unit.get("is_disabled") or _unit.get("is_selling")):
		return
	# Tick the first N non-paused, non-completed elements in parallel.
	var active_elements: Array = []
	var parallel_slots: int = get_parallel_production_count()
	for el in _queue:
		if not el.paused and not el.completed and not el.is_tracking_only:
			active_elements.append(el)
			if active_elements.size() >= parallel_slots:
				break
	if active_elements.is_empty():
		return
	# Slow production by 25% when player energy is negative
	var effective_delta: float = MatchConstants.TICK_DELTA
	if _unit != null and _unit.player != null and _unit.player.energy < 0:
		effective_delta *= 0.75
	var finished_elements: Array = []
	for current_queue_element in active_elements:
		# Trickle cost: deduct proportional resources before progressing.
		if not current_queue_element.trickle_cost.is_empty():
			var new_time = max(0.0, current_queue_element.time_left - effective_delta)
			var target_progress = (
				(current_queue_element.time_total - new_time) / current_queue_element.time_total
			)
			if not _try_deduct_queue_trickle(current_queue_element, target_progress):
				continue  # can't afford this element right now
		current_queue_element.time_left = max(
			0.0, current_queue_element.time_left - effective_delta
		)
		if current_queue_element.time_left == 0.0:
			finished_elements.append(current_queue_element)

	for finished_element in finished_elements:
		if not finished_element in _queue:
			continue
		var scene_path = finished_element.unit_prototype.resource_path
		if _is_off_field_structure(scene_path):
			finished_element.completed = true
			MatchSignals.unit_production_finished.emit(null, _unit)
		else:
			_remove_element(finished_element)
			_finalize_production(finished_element)


func size():
	return _queue.size()


func get_elements():
	return _queue


func get_parallel_production_count() -> int:
	var slots := 1
	if _unit != null and _unit.has_method("get_parallel_production_count"):
		var custom_slots = _unit.get_parallel_production_count()
		if custom_slots is int:
			slots = custom_slots
		elif custom_slots is float:
			slots = int(custom_slots)
	return max(1, slots)


func produce(unit_prototype, _ignore_limit = false):
	var scene_path = unit_prototype.resource_path
	var production_cost = UnitConstants.get_default_properties(scene_path)["costs"]
	var is_trickle = _is_off_field_trickle(scene_path)
	if not is_trickle:
		if not _unit.player.has_resources(production_cost):
			MatchSignals.not_enough_resources_for_production.emit(_unit.player)
			return
		_unit.player.subtract_resources(production_cost)
	var queue_element = ProductionQueueElement.new()
	queue_element.unit_prototype = unit_prototype
	queue_element.time_total = (UnitConstants.get_default_properties(scene_path)["build_time"])
	queue_element.time_left = (UnitConstants.get_default_properties(scene_path)["build_time"])
	if is_trickle:
		queue_element.trickle_cost = production_cost.duplicate()
	_enqueue_element(queue_element)
	MatchSignals.unit_production_started.emit(unit_prototype, _unit)


func cancel_all():
	for element in _queue.duplicate():
		cancel(element)


## Remove a completed off-field structure from the queue (player is deploying it).
func deploy_completed(scene_id: int) -> bool:
	var scene_path: String = UnitConstants.get_scene_path(scene_id)
	if scene_path == "":
		return false
	for el in _queue:
		if el.completed and el.unit_prototype.resource_path == scene_path:
			_remove_element(el)
			return true
	return false


## Returns true if any element with the given scene_path is completed.
func has_completed(scene_id: int) -> bool:
	var scene_path: String = UnitConstants.get_scene_path(scene_id)
	if scene_path == "":
		return false
	for el in _queue:
		if el.completed and el.unit_prototype.resource_path == scene_path:
			return true
	return false


func cancel(element):
	if not element in _queue:
		return
	var type_path = element.unit_prototype.resource_path
	var type_is_paused = element.paused
	# Refund canceled production.
	# - Upfront-cost elements: refund full cost.
	# - Trickle elements: refund what has been deducted so far.
	if not element.trickle_cost.is_empty():
		var spent_cost: Dictionary = {}
		for key in element.trickle_cost:
			var total_for_key: int = element.trickle_cost[key]
			var spent_for_key: int = int(element.trickle_deducted * total_for_key)
			if spent_for_key > 0:
				spent_cost[key] = spent_for_key
		if not spent_cost.is_empty():
			_unit.player.add_resources(spent_cost, Enums.ResourceType.CREDITS)
	else:
		var production_cost = UnitConstants.get_default_properties(type_path)["costs"]
		_unit.player.add_resources(production_cost, Enums.ResourceType.CREDITS)
	_remove_element(element)
	# If the cancelled element's type was paused and a new element becomes the
	# front, pause it so production does not auto-continue.
	if type_is_paused and not _queue.is_empty() and not _queue.front().paused:
		_queue.front().paused = true


func toggle_pause(unit_type_id: int):
	# Check whether any element of this type is currently paused.
	var any_paused := false
	for element in _queue:
		if (
			UnitConstants.get_scene_id(element.unit_prototype.resource_path) == unit_type_id
			and element.paused
		):
			any_paused = true
			break
	# Toggle: if any are paused, unpause all of that type; otherwise pause all.
	for element in _queue:
		if UnitConstants.get_scene_id(element.unit_prototype.resource_path) == unit_type_id:
			element.paused = not any_paused


func _enqueue_element(element):
	_queue.push_back(element)
	element_enqueued.emit(element)


func _remove_element(element):
	_queue.erase(element)
	element_removed.emit(element)


func _finalize_production(former_queue_element):
	var scene_path = former_queue_element.unit_prototype.resource_path
	var scene_id: int = UnitConstants.get_scene_id(scene_path)
	# Off-field structures: add to ready list instead of spawning
	if _is_off_field_structure(scene_path):
		_unit._ready_structures.append(scene_id)
		MatchSignals.unit_production_finished.emit(null, _unit)
		return
	var produced_unit = former_queue_element.unit_prototype.instantiate()
	var placement_position = (
		UnitPlacementUtils
		. find_valid_position_radially_yet_skip_starting_radius(
			_unit.global_position,
			_unit.radius,
			produced_unit.radius,
			0.1,
			Vector3(0, 0, 1),
			false,
			find_parent("Match").navigation.get_navigation_map_rid_by_domain(
				produced_unit.get_nav_domain()
			),
			get_tree()
		)
	)
	var spawn_transform := Transform3D(Basis(), placement_position)
	# Allow producers to override unit spawn transform (e.g. spawn from specific sockets).
	if _unit != null and _unit.has_method("get_custom_spawn_transform_for_unit"):
		var custom_transform = _unit.get_custom_spawn_transform_for_unit(produced_unit)
		if custom_transform is Transform3D:
			spawn_transform = custom_transform
	(
		MatchSignals
		. setup_and_spawn_unit
		. emit(
			produced_unit,
			spawn_transform,
			_unit.player,
			false,
		)
	)
	MatchSignals.unit_production_finished.emit(produced_unit, _unit)
	# Allow producers to handle custom spawn sequences (e.g. delayed rally navigation).
	if _unit != null and _unit.has_method("handle_produced_unit_spawn"):
		if _unit.handle_produced_unit_spawn(produced_unit):
			return

	var rally_point = _unit.find_child("RallyPoint")
	if rally_point != null:
		MatchSignals.navigate_unit_to_rally_point.emit(produced_unit, rally_point)


## Returns true if the given scene_path is a structure produced off-field by this producer.
func _is_off_field_structure(scene_path: String) -> bool:
	if not UnitHelper.is_structure(scene_path):
		return false
	if _unit == null:
		return false
	var prod_type = _unit.get("structure_production_type")
	if prod_type == null:
		return false
	return (
		prod_type
		in [
			Enums.StructureProductionType.CONSTRUCT_OFF_FIELD_AND_TRICKLE,
			Enums.StructureProductionType.CONSTRUCT_OFF_FIELD_AND_DONT_TRICKLE,
		]
	)


## Returns true if the given scene_path is an off-field structure that should trickle cost.
func _is_off_field_trickle(scene_path: String) -> bool:
	if not UnitHelper.is_structure(scene_path):
		return false
	if _unit == null:
		return false
	var prod_type = _unit.get("structure_production_type")
	return prod_type == Enums.StructureProductionType.CONSTRUCT_OFF_FIELD_AND_TRICKLE


## Deduct trickle share of cost for a queue element. Returns false if can't afford.
func _try_deduct_queue_trickle(element: ProductionQueueElement, target_progress: float) -> bool:
	if _unit == null or _unit.player == null:
		return true
	for key in element.trickle_cost:
		var total_for_key: int = element.trickle_cost[key]
		var already: int = int(element.trickle_deducted * total_for_key)
		var wanted: int = int(target_progress * total_for_key)
		var delta_cost: int = wanted - already
		if delta_cost > 0 and not _unit.player.has_resources({key: delta_cost}):
			return false
	for key in element.trickle_cost:
		var total_for_key: int = element.trickle_cost[key]
		var already: int = int(element.trickle_deducted * total_for_key)
		var wanted: int = int(target_progress * total_for_key)
		var delta_cost: int = wanted - already
		if delta_cost > 0:
			_unit.player.subtract_resources({key: delta_cost})
	element.trickle_deducted = target_progress
	return true


## Returns the number of structure elements in the queue whose
## production_tab_type matches the given tab.
func structure_count_in_queue_for_tab(tab: int) -> int:
	var count := 0
	for el in _queue:
		var path: String = el.unit_prototype.resource_path
		if not UnitHelper.is_structure(path):
			continue
		var props = UnitConstants.get_default_properties(path)
		if props.get("production_tab_type", -1) == tab:
			count += 1
	return count
