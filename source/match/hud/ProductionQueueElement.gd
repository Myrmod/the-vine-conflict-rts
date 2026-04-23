extends Button

## All queue elements of the same unit type grouped into this node.
var queue_elements: Array = []
## Shared dict mapping each element Resource → its owning trait ProductionQueue.
## Set by the parent ProductionQueue HUD widget.
var element_to_source: Dictionary = {}
var unit_type_path: String = ""


func _ready():
	if queue_elements.is_empty():
		return
	gui_input.connect(_on_gui_input)

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

	# Check for completed (ready to deploy) elements first
	var has_completed := false
	for el in queue_elements:
		if el.completed:
			has_completed = true
			break
	if has_completed:
		time_label.text = tr("READY")
		time_label.visible = true
		if queue_elements.size() > 1:
			count_label.text = "x%d" % queue_elements.size()
			count_label.visible = true
		else:
			count_label.visible = false
		return

	# Show remaining time for the element with the least time left
	# that is actually producing in its own queue.
	var best_element = null
	var best_tracking_element = null
	for el in queue_elements:
		if el.is_tracking_only:
			if best_tracking_element == null or el.time_left < best_tracking_element.time_left:
				best_tracking_element = el
			continue
		var src_queue = element_to_source.get(el)
		if src_queue == null:
			continue
		var q_elements = src_queue.get_elements()
		var parallel_slots := 1
		if src_queue.has_method("get_parallel_production_count"):
			parallel_slots = src_queue.get_parallel_production_count()
		if el.is_producing(q_elements, parallel_slots):
			if best_element == null or el.time_left < best_element.time_left:
				best_element = el
	if best_element == null and best_tracking_element != null:
		best_element = best_tracking_element
	if best_element != null:
		time_label.text = (
			"%.1fs ||" % best_element.time_left
			if best_element.paused
			else "%.1fs" % best_element.time_left
		)
		time_label.visible = true
	else:
		time_label.visible = false

	# Show count when more than 1
	if queue_elements.size() > 1:
		count_label.text = "x%d" % queue_elements.size()
		count_label.visible = true
	else:
		count_label.visible = false


func _on_gui_input(event: InputEvent):
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_on_left_click()
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.shift_pressed:
			_on_cancel_all_of_type()
		else:
			_on_right_click()
		accept_event()


## Right-click: if this type is currently being produced, pause it.
## If it is already paused or not yet started, cancel one instead.
func _on_right_click():
	if queue_elements.is_empty():
		return
	if _has_tracking_only_elements():
		_on_right_click_tracking()
		return
	var is_producing := false
	for el in queue_elements:
		var src_queue = element_to_source.get(el)
		if src_queue == null:
			continue
		var parallel_slots := 1
		if src_queue.has_method("get_parallel_production_count"):
			parallel_slots = src_queue.get_parallel_production_count()
		if el.is_producing(src_queue.get_elements(), parallel_slots):
			is_producing = true
			break
	if is_producing:
		_on_pause_production()
	else:
		_on_cancel_production()


## Left-click: if a completed off-field structure, deploy it.
## If this type has a paused element, resume it. Otherwise focus camera.
func _on_left_click():
	if _has_tracking_only_elements():
		_on_left_click_tracking()
		return
	# Deploy completed off-field structure
	var completed_el = null
	for el in queue_elements:
		if el.completed:
			completed_el = el
			break
	if completed_el != null:
		var src_queue = element_to_source.get(completed_el)
		if src_queue != null:
			var structure = src_queue.get_parent()
			MatchSignals.pending_off_field_deploy = true
			MatchSignals.pending_trickle = false
			MatchSignals.pending_off_field_producer_id = structure.id
			var prototype = load(unit_type_path)
			if prototype:
				MatchSignals.place_structure.emit(prototype)
		return

	var has_paused := false
	for el in queue_elements:
		if el.paused:
			has_paused = true
			break
	if has_paused:
		_on_pause_production()  # toggle_pause will unpause
	else:
		_on_focus_structure()


func _on_left_click_tracking() -> void:
	# For tracked on-field constructions, left-click resumes a paused one, else focuses producer.
	for el in queue_elements:
		if not el.is_tracking_only or not el.paused:
			continue
		if el.tracking_entity_id < 0:
			continue
		var structure = EntityRegistry.get_unit(el.tracking_entity_id)
		if structure == null or not is_instance_valid(structure):
			continue
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.PAUSE_CONSTRUCTION,
					"player_id": structure.player.id,
					"data": {"entity_id": structure.id},
				}
			)
		)
		return
	_on_focus_structure()


func _on_focus_structure():
	# Focus on the structure that owns the first element
	if queue_elements.is_empty():
		return
	var src_queue = element_to_source.get(queue_elements[0])
	if src_queue == null:
		return
	var structure = src_queue.get_parent()
	if structure == null or not is_instance_valid(structure):
		return
	var camera = get_viewport().get_camera_3d()
	if camera and camera.has_method("set_position_safely"):
		camera.set_position_safely(structure.global_position)


func _on_pause_production():
	# Pause/unpause at every structure that has elements of this type
	var sent_to: Dictionary = {}
	var unit_scene_id: int = UnitConstants.get_scene_id(unit_type_path)
	if unit_scene_id == Enums.SceneId.INVALID:
		return
	for el in queue_elements:
		var src_queue = element_to_source.get(el)
		if src_queue == null:
			continue
		var structure = src_queue.get_parent()
		if sent_to.has(structure):
			continue
		sent_to[structure] = true
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.ENTITY_PRODUCTION_PAUSED,
					"player_id": structure.player.id,
					"data":
					{
						"entity_id": structure.id,
						"unit_type": unit_scene_id,
					}
				}
			)
		)


func _on_right_click_tracking() -> void:
	# 1st right-click pauses an active tracked construction, 2nd cancels a paused one.
	var unpaused_candidates: Array = []
	var paused_candidates: Array = []
	for el in queue_elements:
		if not el.is_tracking_only:
			continue
		if el.tracking_entity_id < 0:
			continue
		var structure = EntityRegistry.get_unit(el.tracking_entity_id)
		if structure == null or not is_instance_valid(structure):
			continue
		if structure.is_under_construction():
			if structure.is_construction_paused:
				paused_candidates.append(structure)
			else:
				unpaused_candidates.append(structure)
	if not unpaused_candidates.is_empty():
		var best = unpaused_candidates[0]
		for s in unpaused_candidates:
			if s.construction_progress < best.construction_progress:
				best = s
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.PAUSE_CONSTRUCTION,
					"player_id": best.player.id,
					"data": {"entity_id": best.id},
				}
			)
		)
		return
	if not paused_candidates.is_empty():
		var best_paused = paused_candidates[0]
		for s in paused_candidates:
			if s.construction_progress < best_paused.construction_progress:
				best_paused = s
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.CANCEL_CONSTRUCTION,
					"player_id": best_paused.player.id,
					"data": {"entity_id": best_paused.id},
				}
			)
		)


func _on_cancel_all_of_type():
	if queue_elements.is_empty():
		return
	if _has_tracking_only_elements():
		var sent_ids: Dictionary = {}
		for el in queue_elements:
			if not el.is_tracking_only:
				continue
			if el.tracking_entity_id < 0 or sent_ids.has(el.tracking_entity_id):
				continue
			var structure = EntityRegistry.get_unit(el.tracking_entity_id)
			if structure == null or not is_instance_valid(structure):
				continue
			if not structure.is_under_construction():
				continue
			sent_ids[el.tracking_entity_id] = true
			(
				CommandBus
				. push_command(
					{
						"tick": Match.tick + 1,
						"type": Enums.CommandType.CANCEL_CONSTRUCTION,
						"player_id": structure.player.id,
						"data": {"entity_id": structure.id},
					}
				)
			)
		return
	for element in queue_elements.duplicate():
		var src_queue = element_to_source.get(element)
		if src_queue == null:
			continue
		var scene_id: int = UnitConstants.get_scene_id(element.unit_prototype.resource_path)
		if scene_id == Enums.SceneId.INVALID:
			continue
		var structure = src_queue.get_parent()
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.ENTITY_PRODUCTION_CANCELED,
					"player_id": structure.player.id,
					"data":
					{
						"entity_id": structure.id,
						"unit_type": scene_id,
					}
				}
			)
		)


func _on_cancel_production():
	if queue_elements.is_empty():
		return
	if _has_tracking_only_elements():
		_on_right_click_tracking()
		return
	# Cancel the last-enqueued element of this type
	var element = queue_elements.back()
	var src_queue = element_to_source.get(element)
	if src_queue == null:
		return
	var scene_id: int = UnitConstants.get_scene_id(element.unit_prototype.resource_path)
	if scene_id == Enums.SceneId.INVALID:
		return
	var structure = src_queue.get_parent()
	(
		CommandBus
		. push_command(
			{
				"tick": Match.tick + 1,
				"type": Enums.CommandType.ENTITY_PRODUCTION_CANCELED,
				"player_id": structure.player.id,
				"data":
				{
					"entity_id": structure.id,
					"unit_type": scene_id,
				}
			}
		)
	)


func _has_tracking_only_elements() -> bool:
	for el in queue_elements:
		if el.is_tracking_only:
			return true
	return false
