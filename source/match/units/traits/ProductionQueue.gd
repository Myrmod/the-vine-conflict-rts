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
	# Find the first non-paused element and tick it.
	var current_queue_element = null
	for el in _queue:
		if not el.paused:
			current_queue_element = el
			break
	if current_queue_element == null:
		return
	current_queue_element.time_left = max(0.0, current_queue_element.time_left - delta)
	if current_queue_element.time_left == 0.0:
		_remove_element(current_queue_element)
		_finalize_production(current_queue_element)


func size():
	return _queue.size()


func get_elements():
	return _queue


func produce(unit_prototype, _ignore_limit = false):
	var production_cost = UnitConstants.DEFAULT_PROPERTIES[unit_prototype.resource_path]["costs"]
	if not _unit.player.has_resources(production_cost):
		MatchSignals.not_enough_resources_for_production.emit(_unit.player)
		return
	_unit.player.subtract_resources(production_cost)
	var queue_element = ProductionQueueElement.new()
	queue_element.unit_prototype = unit_prototype
	queue_element.time_total = (
		UnitConstants.DEFAULT_PROPERTIES[unit_prototype.resource_path]["build_time"]
	)
	queue_element.time_left = (
		UnitConstants.DEFAULT_PROPERTIES[unit_prototype.resource_path]["build_time"]
	)
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
