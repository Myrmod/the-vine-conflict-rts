extends Node3D

const LABEL_OFFSET_RIGHT = 0.4
const LABEL_OFFSET_UP = 0.6

var _set_action_names = [null]
var _get_action_names = [null]
var _unit_group_names = [null]
var _unit_group_labels = {}  # unit -> Label3D


func _ready():
	for group_id in range(1, 10):
		_set_action_names.append("unit_groups_set_{0}".format([group_id]))
		_get_action_names.append("unit_groups_access_{0}".format([group_id]))
		_unit_group_names.append("unit_group_{0}".format([group_id]))
	MatchSignals.unit_died.connect(_on_unit_died)


func _physics_process(_delta):
	# maybe we should put a picture in front of the unit instead for performance?
	# Reposition labels so they stay top-right from camera's perspective
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return
	var cam_right = camera.global_transform.basis.x.normalized()
	var offset = cam_right * LABEL_OFFSET_RIGHT + Vector3.UP * LABEL_OFFSET_UP
	for unit in _unit_group_labels:
		if is_instance_valid(unit) and is_instance_valid(_unit_group_labels[unit]):
			_unit_group_labels[unit].global_position = unit.global_position + offset


func _input(event):
	for group_id in range(1, 10):
		if event.is_action_pressed(_set_action_names[group_id]):
			set_group(group_id)
			return
		if event.is_action_pressed(_get_action_names[group_id]):
			access_group(group_id)
			return


func access_group(group_id: int):
	var units_in_group = Utils.Set.from_array(
		get_tree().get_nodes_in_group(_unit_group_names[group_id])
	)
	MatchUtils.select_units(units_in_group)


func set_group(group_id: int):
	# Remove old group members
	for unit in get_tree().get_nodes_in_group(_unit_group_names[group_id]):
		unit.remove_from_group(_unit_group_names[group_id])
		_update_unit_group_label(unit)
	# Add new group members
	for unit in get_tree().get_nodes_in_group("selected_units"):
		if unit.is_in_group("controlled_units"):
			unit.add_to_group(_unit_group_names[group_id])
			_update_unit_group_label(unit)
	MatchSignals.control_group_changed.emit(group_id)


func _update_unit_group_label(unit):
	# Collect all control groups this unit belongs to
	var groups: Array[int] = []
	for gid in range(1, 10):
		if unit.is_in_group(_unit_group_names[gid]):
			groups.append(gid)
	if groups.is_empty():
		# Remove label if no group
		if unit in _unit_group_labels:
			_unit_group_labels[unit].queue_free()
			_unit_group_labels.erase(unit)
	else:
		var label_text = ",".join(groups.map(func(g): return str(g)))
		if unit in _unit_group_labels:
			_unit_group_labels[unit].text = label_text
		else:
			var label = Label3D.new()
			label.text = label_text
			label.font_size = 24
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.render_priority = 3
			label.outline_size = 8
			label.modulate = Color.WHITE
			label.outline_modulate = Color.BLACK
			# Position will be set by _physics_process
			unit.add_child(label)
			_unit_group_labels[unit] = label


func _on_unit_died(unit):
	if unit in _unit_group_labels:
		_unit_group_labels.erase(unit)
	# Emit changed for any group this unit was in
	for gid in range(1, 10):
		if unit.is_in_group(_unit_group_names[gid]):
			MatchSignals.control_group_changed.emit(gid)
