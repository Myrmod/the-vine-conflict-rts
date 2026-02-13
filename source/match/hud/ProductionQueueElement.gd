extends Button

var queue = null
var queue_element = null
var entity_id = null
var player_id = null


func _ready():
	if queue == null or queue_element == null:
		return
	queue_element.changed.connect(_on_queue_element_changed)
	pressed.connect(_on_cancel_production)
	text = queue_element.unit_prototype.resource_path[
		queue_element.unit_prototype.resource_path.rfind("/") + 1
	]
	find_child("Label").text = "{0}%".format([int(queue_element.progress() * 100.0)])


func _on_queue_element_changed():
	find_child("Label").text = "{0}%".format([int(queue_element.progress() * 100.0)])


func _on_cancel_production():
	CommandBus.push_command({
		"tick": Match.tick + 1,
		"type": Enums.CommandType.ENTITY_PRODUCTION_CANCELED,
		"player_id": player_id,
		"data": {
			"entity_id": entity_id,
			"unit_type": queue_element.unit_prototype.resource_path,
		}
	})
