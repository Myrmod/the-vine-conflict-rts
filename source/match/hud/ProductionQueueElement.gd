extends Button

## All queue elements of the same unit type grouped into this node.
var queue_elements: Array = []
var queue = null
var entity_id = null
var player_id = null
var unit_type_path: String = ""


func _ready():
	if queue_elements.is_empty():
		return
	pressed.connect(_on_cancel_production)

	# Show icon from the first element
	var unit_name: String = unit_type_path.get_file().get_basename()
	var icon_path: String = "res://assets/ui/icons/%s.png" % unit_name
	expand_icon = true
	if ResourceLoader.exists(icon_path):
		icon = load(icon_path)
	else:
		text = unit_name[0]

	for el in queue_elements:
		el.changed.connect(_update_display)
	_update_display()


func add_element(element) -> void:
	queue_elements.append(element)
	if is_inside_tree() and not element.changed.is_connected(_update_display):
		element.changed.connect(_update_display)
	_update_display()


func remove_element(element) -> void:
	if element.changed.is_connected(_update_display):
		element.changed.disconnect(_update_display)
	queue_elements.erase(element)
	if queue_elements.is_empty():
		queue_free()
	else:
		_update_display()


func _update_display():
	var time_label := find_child("TimeLabel") as Label
	var count_label := find_child("CountLabel") as Label

	# Show remaining time (with ms) only for the element next to finish
	var all_elements = queue.get_elements()
	var front_element = all_elements.front() if all_elements.size() > 0 else null
	var has_front := false
	for el in queue_elements:
		if el == front_element:
			has_front = true
			break
	if has_front and front_element != null:
		time_label.text = "%.1fs" % front_element.time_left
		time_label.visible = true
	else:
		time_label.visible = false

	# Show count when more than 1
	if queue_elements.size() > 1:
		count_label.text = "x%d" % queue_elements.size()
		count_label.visible = true
	else:
		count_label.visible = false


func _on_cancel_production():
	if queue_elements.is_empty():
		return
	# Cancel the last-enqueued element of this type
	var element = queue_elements.back()
	(
		CommandBus
		. push_command(
			{
				"tick": Match.tick + 1,
				"type": Enums.CommandType.ENTITY_PRODUCTION_CANCELED,
				"player_id": player_id,
				"data":
				{
					"entity_id": entity_id,
					"unit_type": element.unit_prototype.resource_path,
				}
			}
		)
	)
