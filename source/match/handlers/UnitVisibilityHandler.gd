extends Node3D

const SIGHT_COMPENSATION = 2.0  # compensates for blurry edges of FoW

const Structure = preload("res://source/match/units/Structure.gd")
const ResourceUnit = preload("res://source/match/units/non-player/ResourceUnit.gd")

var _units_processed_at_least_once = {}
var _structure_to_dummy_mapping = {}
var _orphaned_dummies = []


func _ready():
	MatchSignals.unit_spawned.connect(_recalculate_unit_visibility)
	MatchSignals.unit_died.connect(_on_unit_died)


func _physics_process(_delta):
	var all_units = get_tree().get_nodes_in_group("units")
	var revealed_units = all_units.filter(func(unit): return unit.is_in_group("revealed_units"))
	for unit in all_units:
		_recalculate_unit_visibility(unit, revealed_units)
	_update_resource_unit_dummies(revealed_units)
	_orphan_dummies_of_freed_units()
	for orphaned_dummy in _orphaned_dummies:
		_recalcuate_orphaned_dummy_existence(orphaned_dummy, revealed_units)


func _is_disabled():
	return not visible


func _recalculate_unit_visibility(unit, revealed_units = null):
	if unit.is_in_group("revealed_units") or _is_disabled():
		_update_unit_visibility(unit, true)
		return

	var should_be_visible = false
	if revealed_units == null:
		revealed_units = get_tree().get_nodes_in_group("units").filter(
			func(a_unit): return a_unit.is_in_group("revealed_units")
		)
	for revealed_unit in revealed_units:
		if revealed_unit.is_revealing() and revealed_unit.sight_range != null:
			var effective_sight = revealed_unit.sight_range
			if "forest_zones_inside" in revealed_unit and revealed_unit.forest_zones_inside > 0:
				effective_sight *= revealed_unit.forest_sight_multiplier
			if (
				(revealed_unit.global_position * Vector3(1, 0, 1)).distance_to(
					unit.global_position * Vector3(1, 0, 1)
				)
				<= effective_sight + SIGHT_COMPENSATION
			):
				should_be_visible = true
				break
	_update_unit_visibility(unit, should_be_visible)


func _update_unit_visibility(unit, should_be_visible):
	if (
		unit in _units_processed_at_least_once
		and unit is Structure
		and unit.visible != should_be_visible
	):
		if unit.visible:
			_create_dummy_structure(unit)
		else:
			_try_removing_dummy_structure(unit)
	unit.visible = should_be_visible
	_units_processed_at_least_once[unit] = true


func _create_dummy_structure(unit):
	if unit in _structure_to_dummy_mapping:
		return
	var visual_node = _get_visual_node(unit)
	if visual_node == null:
		return
	var dummy = visual_node.duplicate()
	dummy.global_transform = visual_node.global_transform
	add_child(dummy)
	_structure_to_dummy_mapping[unit] = dummy


func _get_visual_node(unit):
	var geometry = unit.find_child("Geometry")
	if geometry:
		return geometry
	for child in unit.get_children():
		if child is MeshInstance3D:
			return child
	return null


func _try_removing_dummy_structure(unit):
	if unit in _structure_to_dummy_mapping:
		_structure_to_dummy_mapping[unit].queue_free()
		_structure_to_dummy_mapping.erase(unit)


func _update_resource_unit_dummies(revealed_units):
	if _is_disabled():
		return
	for resource_unit in get_tree().get_nodes_in_group("resource_units"):
		var in_vision = _is_in_vision_range(resource_unit, revealed_units)
		resource_unit.in_player_vision = in_vision
		if in_vision:
			_try_removing_dummy_structure(resource_unit)
		elif not resource_unit in _structure_to_dummy_mapping:
			_create_dummy_structure(resource_unit)


func _is_in_vision_range(target, revealed_units):
	for revealed_unit in revealed_units:
		if (
			revealed_unit.is_revealing()
			and revealed_unit.sight_range != null
			and (
				(revealed_unit.global_position * Vector3(1, 0, 1)).distance_to(
					target.global_position * Vector3(1, 0, 1)
				)
				<= revealed_unit.sight_range + SIGHT_COMPENSATION
			)
		):
			return true
	return false


func _recalcuate_orphaned_dummy_existence(orphaned_dummy, revealed_units = null):
	var should_exist = true
	if revealed_units == null:
		revealed_units = get_tree().get_nodes_in_group("units").filter(
			func(unit): return unit.is_in_group("revealed_units")
		)
	for revealed_unit in revealed_units:
		if (
			revealed_unit.is_revealing()
			and revealed_unit.sight_range != null
			and (
				(revealed_unit.global_position * Vector3(1, 0, 1)).distance_to(
					orphaned_dummy.global_position * Vector3(1, 0, 1)
				)
				<= revealed_unit.sight_range + SIGHT_COMPENSATION
			)
		):
			should_exist = false
			break
	if not should_exist:
		_orphaned_dummies.erase(orphaned_dummy)
		orphaned_dummy.queue_free()


func _orphan_dummies_of_freed_units():
	var freed_units = []
	for mapped_unit in _structure_to_dummy_mapping:
		if not is_instance_valid(mapped_unit):
			freed_units.append(mapped_unit)
	for freed_unit in freed_units:
		_units_processed_at_least_once.erase(freed_unit)
		var orphaned_dummy = _structure_to_dummy_mapping[freed_unit]
		_structure_to_dummy_mapping.erase(freed_unit)
		_orphaned_dummies.append(orphaned_dummy)


func _on_unit_died(unit):
	_units_processed_at_least_once.erase(unit)
	if unit in _structure_to_dummy_mapping:
		var orphaned_dummy = _structure_to_dummy_mapping[unit]
		_structure_to_dummy_mapping.erase(unit)
		_orphaned_dummies.append(orphaned_dummy)
		_recalcuate_orphaned_dummy_existence(orphaned_dummy)
