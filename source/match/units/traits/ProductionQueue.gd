extends Node

signal element_enqueued(element)
signal element_removed(element)

const Moving = preload("res://source/match/units/actions/Moving.gd")


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
	## When non-empty, cost trickles over build_time instead of being deducted upfront.
	var trickle_cost: Dictionary = {}
	var trickle_deducted: float = 0.0

	func progress():
		return (time_total - time_left) / time_total

	## Returns true when this element is actively counting down
	## (i.e. first non-paused element in the queue).
	func is_producing(queue_array: Array) -> bool:
		if paused:
			return false
		for el in queue_array:
			if not el.paused:
				return el == self
		return false


var _queue = []

@onready var _unit = get_parent()


func _process(delta):
	if _queue.is_empty() or delta <= 0.0:
		return
	# Don't tick production while the parent structure is disabled or selling.
	if _unit != null and (_unit.get("is_disabled") or _unit.get("is_selling")):
		return
	# Find the first non-paused element and tick it.
	var current_queue_element = null
	for el in _queue:
		if not el.paused:
			current_queue_element = el
			break
	if current_queue_element == null:
		return
	# Trickle cost: deduct proportional resources before progressing
	if not current_queue_element.trickle_cost.is_empty():
		var new_time = max(0.0, current_queue_element.time_left - delta)
		var target_progress = (
			(current_queue_element.time_total - new_time) / current_queue_element.time_total
		)
		if not _try_deduct_queue_trickle(current_queue_element, target_progress):
			return  # can't afford, pause production
	current_queue_element.time_left = max(0.0, current_queue_element.time_left - delta)
	if current_queue_element.time_left == 0.0:
		_remove_element(current_queue_element)
		_finalize_production(current_queue_element)


func size():
	return _queue.size()


func get_elements():
	return _queue


func produce(unit_prototype, _ignore_limit = false):
	var scene_path = unit_prototype.resource_path
	var production_cost = UnitConstants.DEFAULT_PROPERTIES[scene_path]["costs"]
	var is_trickle = _is_off_field_trickle(scene_path)
	if not is_trickle:
		if not _unit.player.has_resources(production_cost):
			MatchSignals.not_enough_resources_for_production.emit(_unit.player)
			return
		_unit.player.subtract_resources(production_cost)
	var queue_element = ProductionQueueElement.new()
	queue_element.unit_prototype = unit_prototype
	queue_element.time_total = (UnitConstants.DEFAULT_PROPERTIES[scene_path]["build_time"])
	queue_element.time_left = (UnitConstants.DEFAULT_PROPERTIES[scene_path]["build_time"])
	if is_trickle:
		queue_element.trickle_cost = production_cost.duplicate()
	_enqueue_element(queue_element)
	MatchSignals.unit_production_started.emit(unit_prototype, _unit)


func cancel_all():
	for element in _queue.duplicate():
		cancel(element)


func cancel(element):
	if not element in _queue:
		return
	var type_path = element.unit_prototype.resource_path
	var type_is_paused = element.paused
	# Only refund for non-trickle elements (trickle only deducted what was spent)
	if element.trickle_cost.is_empty():
		var production_cost = UnitConstants.DEFAULT_PROPERTIES[type_path]["costs"]
		_unit.player.add_resources(production_cost, Enums.ResourceType.CREDITS)
	_remove_element(element)
	# If the cancelled element's type was paused and a new element becomes the
	# front, pause it so production does not auto-continue.
	if type_is_paused and not _queue.is_empty() and not _queue.front().paused:
		_queue.front().paused = true


func toggle_pause(unit_type_path: String):
	# Check whether any element of this type is currently paused.
	var any_paused := false
	for element in _queue:
		if element.unit_prototype.resource_path == unit_type_path and element.paused:
			any_paused = true
			break
	# Toggle: if any are paused, unpause all of that type; otherwise pause all.
	for element in _queue:
		if element.unit_prototype.resource_path == unit_type_path:
			element.paused = not any_paused


func _enqueue_element(element):
	_queue.push_back(element)
	element_enqueued.emit(element)


func _remove_element(element):
	_queue.erase(element)
	element_removed.emit(element)


func _finalize_production(former_queue_element):
	var scene_path = former_queue_element.unit_prototype.resource_path
	# Off-field structures: add to ready list instead of spawning
	if _is_off_field_structure(scene_path):
		_unit._ready_structures.append(scene_path)
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
	(
		MatchSignals
		. setup_and_spawn_unit
		. emit(
			produced_unit,
			Transform3D(Basis(), placement_position),
			_unit.player,
			false,
		)
	)
	MatchSignals.unit_production_finished.emit(produced_unit, _unit)

	var rally_point = _unit.find_child("RallyPoint")
	if rally_point != null:
		MatchSignals.navigate_unit_to_rally_point.emit(produced_unit, rally_point)


## Returns true if the given scene_path is a structure produced off-field by this producer.
func _is_off_field_structure(scene_path: String) -> bool:
	if not UnitConstants.STRUCTURE_BLUEPRINTS.has(scene_path):
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
	if not UnitConstants.STRUCTURE_BLUEPRINTS.has(scene_path):
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
		if not UnitConstants.STRUCTURE_BLUEPRINTS.has(path):
			continue
		var props = UnitConstants.DEFAULT_PROPERTIES.get(path, {})
		if props.get("production_tab_type", -1) == tab:
			count += 1
	return count
