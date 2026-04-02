class_name ProductionQueue extends MarginContainer

const ProductionQueueElement = preload("res://source/match/hud/ProductionQueueElement.tscn")

## All currently observed trait queues (one per structure).
var _production_queues: Array = []
## Maps each queue element Resource → its owning trait ProductionQueue node.
var _element_to_source: Dictionary = {}

@onready var _queue_elements = find_child("QueueElements")


func _ready():
	_reset()


## Observe ALL production structures at once.
## Pass an empty array to clear the display.
func observe_structures(structures: Array) -> void:
	_detach_all()
	_remove_queue_element_nodes()
	_element_to_source.clear()
	for structure in structures:
		if structure == null or not is_instance_valid(structure):
			continue
		if not "production_queue" in structure or structure.production_queue == null:
			continue
		_attach(structure.production_queue)
	visible = not _production_queues.is_empty()
	_try_rendering_queue()


## Legacy single-structure observe kept for compatibility.
func observe_structure(structure) -> void:
	if structure == null:
		observe_structures([])
	else:
		observe_structures([structure])


func _reset():
	if not is_inside_tree():
		return
	_detach_all()
	visible = false
	_remove_queue_element_nodes()


func _remove_queue_element_nodes():
	for child in _queue_elements.get_children():
		_queue_elements.remove_child(child)
		child.queue_free()


func _detach_all():
	for pq in _production_queues:
		if not is_instance_valid(pq):
			continue
		if pq.element_enqueued.is_connected(_on_production_queue_element_enqueued):
			pq.element_enqueued.disconnect(_on_production_queue_element_enqueued)
		if pq.element_removed.is_connected(_on_production_queue_element_removed):
			pq.element_removed.disconnect(_on_production_queue_element_removed)
	_production_queues.clear()
	_element_to_source.clear()


func _attach(a_production_queue):
	_production_queues.append(a_production_queue)
	a_production_queue.element_enqueued.connect(
		_on_production_queue_element_enqueued.bind(a_production_queue)
	)
	a_production_queue.element_removed.connect(
		_on_production_queue_element_removed.bind(a_production_queue)
	)


func _try_rendering_queue():
	for pq in _production_queues:
		for queue_element in pq.get_elements():
			_element_to_source[queue_element] = pq
			_add_queue_element_node(queue_element, pq)


func _add_queue_element_node(queue_element, source_queue):
	var type_path: String = queue_element.unit_prototype.resource_path
	# Find existing stacked node for this type
	for child in _queue_elements.get_children():
		if child.unit_type_path == type_path:
			child.add_element(queue_element)
			_sort_queue_element_nodes()
			return
	# Create new stacked node
	var queue_element_node = ProductionQueueElement.instantiate()
	queue_element_node.element_to_source = _element_to_source
	queue_element_node.queue_elements = [queue_element]
	queue_element_node.unit_type_path = type_path
	_queue_elements.add_child(queue_element_node)
	_sort_queue_element_nodes()


## Sort UI nodes so the type currently being produced appears first.
## Producing = first non-paused element across all queues.
func _sort_queue_element_nodes():
	if _production_queues.is_empty():
		return
	var all_elements := _get_all_elements()
	var children = _queue_elements.get_children()
	children.sort_custom(
		func(a, b):
			var a_idx := _earliest_queue_index(a, all_elements)
			var b_idx := _earliest_queue_index(b, all_elements)
			return a_idx < b_idx
	)
	for i in children.size():
		_queue_elements.move_child(children[i], i)


## Collect elements from all observed queues into a flat array.
func _get_all_elements() -> Array:
	var result: Array = []
	for pq in _production_queues:
		result.append_array(pq.get_elements())
	return result


static func _earliest_queue_index(node, all_elements: Array) -> int:
	var best := all_elements.size()
	for el in node.queue_elements:
		var idx := all_elements.find(el)
		if idx != -1 and idx < best:
			best = idx
	return best


func _on_production_queue_element_enqueued(element, source_queue):
	_element_to_source[element] = source_queue
	_add_queue_element_node(element, source_queue)


func _on_production_queue_element_removed(element, _source_queue):
	_element_to_source.erase(element)
	for child in _queue_elements.get_children():
		if element in child.queue_elements:
			child.remove_element(element)
			_sort_queue_element_nodes()
			return


static func _generate_unit_production_command(entity_id, unit_type, player_id):
	var scene_id: int = UnitConstants.get_scene_id(unit_type)
	if scene_id == Enums.SceneId.INVALID:
		return
	(
		CommandBus
		. push_command(
			{
				"tick": Match.tick + 1,
				"type": Enums.CommandType.ENTITY_IS_QUEUED,
				"player_id": player_id,
				"data":
				{
					"entity_id": entity_id,
					"unit_type": scene_id,
					"time_total": UnitConstants.get_default_properties(scene_id)["build_time"],
				}
			}
		)
	)
