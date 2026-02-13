extends Node

signal resources_required(resources, metadata)

const CommandCenter = preload("res://source/match/units/CommandCenter.gd")
const CommandCenterScene = preload("res://source/match/units/CommandCenter.tscn")
const Worker = preload("res://source/match/units/Worker.gd")
const WorkerScene = preload("res://source/match/units/Worker.tscn")
const CollectingResourcesSequentially = preload(
	"res://source/match/units/actions/CollectingResourcesSequentially.gd"
)

var _player = null
var _ccs = []
var _workers = []
var _number_of_pending_cc_resource_requests = 0
var _number_of_pending_worker_resource_requests = 0
var _number_of_pending_workers = 0
var _cc_base_position = null

@onready var _ai = get_parent()


func setup(player):
	_player = player
	_attach_current_ccs()
	_attach_current_workers()
	MatchSignals.unit_spawned.connect(_on_unit_spawned)
	_enforce_number_of_ccs()
	_enforce_number_of_workers()


func provision(resources, metadata):
	if metadata == "worker":
		assert(
			resources == UnitConstants.PRODUCTION_COSTS[WorkerScene.resource_path],
			"unexpected amount of resources"
		)
		_number_of_pending_worker_resource_requests -= 1
		if _ccs.is_empty():
			return
		# Queue worker production through CommandBus (not directly on production queue).
		# This ensures the command is recorded for replay determinism.
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.ENTITY_IS_QUEUED,
			"player_id": _player.id,
			"data": {
				"entity_id": _ccs[0].id,
				"unit_type": WorkerScene.resource_path,
				"time_total": UnitConstants.PRODUCTION_TIMES[WorkerScene.resource_path],
				"ignore_limit": true,
			}
		})
		_number_of_pending_workers += 1
	elif metadata == "cc":
		assert(
			resources == UnitConstants.CONSTRUCTION_COSTS[CommandCenterScene.resource_path],
			"unexpected amount of resources"
		)
		_number_of_pending_cc_resource_requests -= 1
		if _workers.is_empty():
			return
		_construct_cc()
	else:
		assert(false, "unexpected flow")


func _attach_cc(cc):
	_ccs.append(cc)
	cc.tree_exited.connect(_on_cc_died.bind(cc))


func _attach_current_ccs():
	var ccs = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is CommandCenter and unit.player == _player
	)
	if not ccs.is_empty():
		_cc_base_position = ccs[0].global_position
	for cc in ccs:
		_attach_cc(cc)


func _attach_worker(worker):
	if worker in _workers:
		return
	_workers.append(worker)
	worker.tree_exited.connect(_on_worker_died.bind(worker))
	worker.action_changed.connect(_on_worker_action_changed.bind(worker))
	if worker.action != null:
		return
	_make_worker_collecting_resources(worker)


func _attach_current_workers():
	var workers = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is Worker and unit.player == _player
	)
	for worker in workers:
		_attach_worker(worker)


func _enforce_number_of_ccs():
	if (
		_ccs.size() + _number_of_pending_cc_resource_requests + _number_of_pending_workers
		>= _ai.expected_number_of_ccs
	):
		return
	var number_of_extra_ccs_required = (
		_ai.expected_number_of_ccs
		- (_ccs.size() + _number_of_pending_cc_resource_requests + _number_of_pending_workers)
	)
	for _i in range(number_of_extra_ccs_required):
		resources_required.emit(
			UnitConstants.CONSTRUCTION_COSTS[CommandCenterScene.resource_path], "cc"
		)
		_number_of_pending_cc_resource_requests += 1


func _enforce_number_of_workers():
	if (
		_workers.size() + _number_of_pending_worker_resource_requests
		>= _ai.expected_number_of_workers
	):
		return
	var number_of_extra_workers_required = (
		_ai.expected_number_of_workers
		- (_workers.size() + _number_of_pending_worker_resource_requests)
	)
	for _i in range(number_of_extra_workers_required):
		resources_required.emit(
			UnitConstants.PRODUCTION_COSTS[WorkerScene.resource_path], "worker"
		)
		_number_of_pending_worker_resource_requests += 1


func _construct_cc():
	var construction_cost = UnitConstants.CONSTRUCTION_COSTS[
		CommandCenterScene.resource_path
	]
	# Pre-check resources as an optimistic filter. The authoritative check happens in
	# Match._execute_command() — between queueing and execution another command may
	# spend the resources, which Match handles gracefully.
	if not _player.has_resources(construction_cost):
		return
	var unit_to_spawn = CommandCenterScene.instantiate()
	var placement_position = Utils.MatchUtils.Placement.find_valid_position_radially(
		_cc_base_position if _cc_base_position != null else _workers[0].global_position,
		unit_to_spawn.radius + UnitConstants.EMPTY_SPACE_RADIUS_SURROUNDING_STRUCTURE_M,
		find_parent("Match").navigation.get_navigation_map_rid_by_domain(
			unit_to_spawn.movement_domain
		),
		get_tree()
	)
	var target_transform = Transform3D(Basis(), placement_position).looking_at(
		placement_position + Vector3(0, 0, 1), Vector3.UP
	)
	# Free the temporary instance used for radius calculation
	unit_to_spawn.free()
	# Place structure through CommandBus — resources are deducted by Match._execute_command()
	CommandBus.push_command({
		"tick": Match.tick + 1,
		"type": Enums.CommandType.STRUCTURE_PLACED,
		"player_id": _player.id,
		"data": {
			"structure_prototype": CommandCenterScene.resource_path,
			"transform": target_transform,
		}
	})


func _calculate_resource_collecting_statistics():
	var number_of_workers_per_resource_kind = {
		"resource_a": 0,
		"resource_b": 0,
	}
	for worker in _workers:
		if worker.action != null and worker.action is CollectingResourcesSequentially:
			var resource_unit = worker.action.get_resource_unit()
			if resource_unit == null:
				continue
			if "resource_a" in resource_unit:
				number_of_workers_per_resource_kind["resource_a"] += 1
			elif "resource_b" in resource_unit:
				number_of_workers_per_resource_kind["resource_b"] += 1
			else:
				assert(false, "unexpected flow")
	return number_of_workers_per_resource_kind


func _make_worker_collecting_resources(worker):
	var number_of_workers_per_resource_kind = _calculate_resource_collecting_statistics()
	var resource_filter = null
	if (
		number_of_workers_per_resource_kind["resource_a"] != 0
		or number_of_workers_per_resource_kind["resource_b"] != 0
	):
		if (
			number_of_workers_per_resource_kind["resource_a"]
			<= number_of_workers_per_resource_kind["resource_b"]
		):
			resource_filter = func(resource_unit): return "resource_a" in resource_unit
		else:
			resource_filter = func(resource_unit): return "resource_b" in resource_unit
	var closest_resource_unit = (
		ResourceUtils
		.find_resource_unit_closest_to_unit_yet_no_further_than(
			worker, UnitConstants.NEW_RESOURCE_SEARCH_RADIUS_M, resource_filter
		)
	)
	if closest_resource_unit != null:
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.COLLECTING_RESOURCES_SEQUENTIALLY,
			"player_id": _player.id,
			"data": {
				"targets": [{"unit": worker.id, "pos": worker.global_position, "rot": worker.global_rotation}],
				"target_unit": closest_resource_unit.id,
			}
		})


func _retarget_workers_if_necessary():
	var number_of_workers_per_resource_kind = _calculate_resource_collecting_statistics()
	if (
		abs(
			(
				number_of_workers_per_resource_kind["resource_a"]
				- number_of_workers_per_resource_kind["resource_b"]
			)
		)
		>= 2
	):
		for worker in _workers:
			_make_worker_collecting_resources(worker)


func _on_cc_died(cc):
	if not is_inside_tree():
		return
	_ccs.erase(cc)
	_enforce_number_of_ccs()


func _on_worker_died(worker):
	if not is_inside_tree():
		return
	_workers.erase(worker)
	_enforce_number_of_workers()
	_retarget_workers_if_necessary()


func _on_unit_spawned(unit):
	if unit.player != _player:
		return
	if unit is Worker:
		if _number_of_pending_workers > 0:
			_number_of_pending_workers -= 1
		_attach_worker(unit)
	elif unit is CommandCenter:
		_attach_cc(unit)


func _on_worker_action_changed(new_action, worker):
	if new_action != null:
		return
	_make_worker_collecting_resources(worker)
