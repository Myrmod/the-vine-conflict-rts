class_name ProductionQueue extends MarginContainer

const ProductionQueueElement = preload("res://source/match/hud/ProductionQueueElement.tscn")

var _production_queue = null

@onready var _queue_elements = find_child("QueueElements")


func _ready():
	_reset()


## Called by Hud.gd when the active producer changes.
## Pass null to clear the queue display.
func observe_structure(structure) -> void:
	_detach_observed_production_queue()
	_remove_queue_element_nodes()
	if structure == null or not is_instance_valid(structure):
		visible = false
		return
	if not "production_queue" in structure or structure.production_queue == null:
		visible = false
		return
	_observe(structure.production_queue)
	visible = true
	_try_rendering_queue()


func _reset():
	if not is_inside_tree():
		return
	_detach_observed_production_queue()
	visible = false
	_remove_queue_element_nodes()


func _remove_queue_element_nodes():
	for child in _queue_elements.get_children():
		child.queue_free()


func _is_observing_production_queue():
	return _production_queue != null


func _detach_observed_production_queue():
	if _production_queue != null:
		_production_queue.element_enqueued.disconnect(_on_production_queue_element_enqueued)
		_production_queue.element_removed.disconnect(_on_production_queue_element_removed)
		_production_queue = null


func _observe(a_production_queue):
	_production_queue = a_production_queue
	_production_queue.element_enqueued.connect(_on_production_queue_element_enqueued)
	_production_queue.element_removed.connect(_on_production_queue_element_removed)


func _try_rendering_queue():
	if not _is_observing_production_queue():
		return
	for queue_element in _production_queue.get_elements():
		_add_queue_element_node(queue_element)


func _add_queue_element_node(queue_element):
	var type_path: String = queue_element.unit_prototype.resource_path
	# Find existing stacked node for this type
	for child in _queue_elements.get_children():
		if child.unit_type_path == type_path:
			child.add_element(queue_element)
			return
	# Create new stacked node
	var queue_element_node = ProductionQueueElement.instantiate()
	queue_element_node.queue = _production_queue
	queue_element_node.queue_elements = [queue_element]
	queue_element_node.unit_type_path = type_path
	queue_element_node.entity_id = _production_queue.get_parent().id
	queue_element_node.player_id = _production_queue.get_parent().player.id
	_queue_elements.add_child(queue_element_node)
	_queue_elements.move_child(queue_element_node, 0)


func _on_production_queue_element_enqueued(element):
	_add_queue_element_node(element)


func _on_production_queue_element_removed(element):
	for child in _queue_elements.get_children():
		if element in child.queue_elements:
			child.remove_element(element)
			return


static func _generate_unit_production_command(entity_id, unit_type, player_id):
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
					"unit_type": unit_type,
					"time_total": UnitConstants.DEFAULT_PROPERTIES[unit_type]["build_time"],
				}
			}
		)
	)
