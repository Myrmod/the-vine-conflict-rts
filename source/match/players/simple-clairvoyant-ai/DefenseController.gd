extends Node

signal resources_required(resources, metadata)

const Worker = preload("res://source/match/units/Worker.gd")
const CommandCenter = preload("res://source/match/units/CommandCenter.gd")
const AGTurret = preload("res://source/match/units/AntiGroundTurret.gd")
const AGTurretScene = preload("res://source/match/units/AntiGroundTurret.tscn")
const AATurret = preload("res://source/match/units/AntiAirTurret.gd")
const AATurretScene = preload("res://source/match/units/AntiAirTurret.tscn")

# Tick-based refresh interval. At TICK_RATE 10, 5 ticks = 0.5 s.
const REFRESH_INTERVAL_TICKS = 5

var _player = null
var _number_of_pending_ag_turret_resource_requests = 0
var _number_of_pending_aa_turret_resource_requests = 0

@onready var _ai = get_parent()


var _ticks_until_refresh = REFRESH_INTERVAL_TICKS


func setup(player):
	_player = player
	_setup_tick_refresh()
	_attach_current_turrets()
	MatchSignals.unit_spawned.connect(_on_unit_spawned)
	_enforce_number_of_ag_turrets()
	_enforce_number_of_aa_turrets()


func provision(resources, metadata):
	var workers = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is Worker and unit.player == _player
	)
	var ccs = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is CommandCenter and unit.player == _player
	)
	if metadata == "ag_turret":
		assert(
			resources == UnitConstants.CONSTRUCTION_COSTS[AGTurretScene.resource_path],
			"unexpected amount of resources"
		)
		_number_of_pending_ag_turret_resource_requests -= 1
		if workers.is_empty() or ccs.is_empty():
			return
		_construct_turret(AGTurretScene)
	elif metadata == "aa_turret":
		assert(
			resources == UnitConstants.CONSTRUCTION_COSTS[AATurretScene.resource_path],
			"unexpected amount of resources"
		)
		_number_of_pending_aa_turret_resource_requests -= 1
		if workers.is_empty() or ccs.is_empty():
			return
		_construct_turret(AATurretScene)
	else:
		assert(false, "unexpected flow")


func _setup_tick_refresh():
	MatchSignals.tick_advanced.connect(_on_tick_advanced)


func _on_tick_advanced():
	_ticks_until_refresh -= 1
	if _ticks_until_refresh > 0:
		return
	_ticks_until_refresh = REFRESH_INTERVAL_TICKS
	_on_refresh_timer_timeout()


func _attach_current_turrets():
	var turrets = get_tree().get_nodes_in_group("units").filter(
		func(unit): return (unit is AGTurret or unit is AATurret) and unit.player == _player
	)
	for turret in turrets:
		_attach_turret(turret)


func _attach_turret(turret):
	turret.tree_exited.connect(_on_unit_died.bind(turret))


func _enforce_number_of_ag_turrets():
	var ag_turrets = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is AGTurret and unit.player == _player
	)
	if (
		ag_turrets.size() + _number_of_pending_ag_turret_resource_requests
		>= _ai.expected_number_of_ag_turrets
	):
		return
	var number_of_extra_ag_turrets_required = (
		_ai.expected_number_of_ag_turrets
		- (ag_turrets.size() + _number_of_pending_ag_turret_resource_requests)
	)
	for _i in range(number_of_extra_ag_turrets_required):
		resources_required.emit(
			UnitConstants.CONSTRUCTION_COSTS[AGTurretScene.resource_path], "ag_turret"
		)
		_number_of_pending_ag_turret_resource_requests += 1


func _enforce_number_of_aa_turrets():
	var aa_turrets = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is AATurret and unit.player == _player
	)
	if (
		aa_turrets.size() + _number_of_pending_aa_turret_resource_requests
		>= _ai.expected_number_of_aa_turrets
	):
		return
	var number_of_extra_aa_turrets_required = (
		_ai.expected_number_of_aa_turrets
		- (aa_turrets.size() + _number_of_pending_aa_turret_resource_requests)
	)
	for _i in range(number_of_extra_aa_turrets_required):
		resources_required.emit(
			UnitConstants.CONSTRUCTION_COSTS[AATurretScene.resource_path], "aa_turret"
		)
		_number_of_pending_aa_turret_resource_requests += 1


func _construct_turret(turret_scene):
	var construction_cost = UnitConstants.CONSTRUCTION_COSTS[turret_scene.resource_path]
	# Pre-check resources as an optimistic filter. The authoritative check happens in
	# Match._execute_command() — another command may spend the resources before execution.
	if not _player.has_resources(construction_cost):
		return
	var ccs = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is CommandCenter and unit.player == _player
	)
	var unit_to_spawn = turret_scene.instantiate()
	# TODO: introduce actual algorithm which takes enemy positions into account
	var placement_position = Utils.MatchUtils.Placement.find_valid_position_radially(
		ccs[0].global_position,
		unit_to_spawn.radius + UnitConstants.EMPTY_SPACE_RADIUS_SURROUNDING_STRUCTURE_M,
		find_parent("Match").navigation.get_navigation_map_rid_by_domain(
			unit_to_spawn.movement_domain
		),
		get_tree()
	)
	var target_transform = Transform3D(Basis(), placement_position).looking_at(
		placement_position + Vector3(0, 0, 1), Vector3.UP
	)
	# Free the temporary instance used for radius/domain calculation
	unit_to_spawn.free()
	# Place structure through CommandBus — resources deducted by Match._execute_command()
	CommandBus.push_command({
		"tick": Match.tick + 1,
		"type": Enums.CommandType.STRUCTURE_PLACED,
		"player_id": _player.id,
		"data": {
			"structure_prototype": turret_scene.resource_path,
			"transform": target_transform,
		}
	})


func _on_unit_died(unit):
	if not is_inside_tree():
		return
	if unit is AGTurret:
		_enforce_number_of_ag_turrets()
	elif unit is AATurret:
		_enforce_number_of_aa_turrets()
	else:
		assert(false, "unexpected flow")


func _on_unit_spawned(unit):
	if unit.player != _player:
		return
	if unit is AGTurret or unit is AATurret:
		_attach_turret(unit)


func _on_refresh_timer_timeout():
	_enforce_number_of_ag_turrets()
	_enforce_number_of_aa_turrets()
