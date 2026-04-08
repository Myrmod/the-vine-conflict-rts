extends "res://source/match/units/actions/Action.gd"

const COLLECT_TICKS = 10  # 1.0s at TICK_RATE 10

var _resource_unit = null
var _collect_counter: int = 0
var _paused: bool = false

@onready var _unit = Utils.NodeEx.find_parent_with_group(self, "units")
@onready var _unit_movement_trait = _unit.find_child("Movement")


static func is_applicable(source_unit, target_unit):
	return (
		source_unit is ResourceGatherer
		and target_unit is ResourceUnit
		and not source_unit.is_full()
		and MatchUtils.Movement.units_adhere(source_unit, target_unit)
	)


func _init(resource_unit):
	_resource_unit = resource_unit


func _ready():
	_resource_unit.tree_exited.connect(queue_free)
	if "resource_changed" in _resource_unit:
		_resource_unit.resource_changed.connect(_on_resource_changed)
	_unit_movement_trait.passive_movement_started.connect(_on_passive_movement_started)
	_unit_movement_trait.passive_movement_finished.connect(_on_passive_movement_finished)
	MatchSignals.tick_advanced.connect(_on_tick_advanced)
	_unit.get_node("Sparkling").enable()


func _exit_tree():
	_unit.get_node("Sparkling").disable()


func _on_tick_advanced():
	if not is_inside_tree():
		return
	if _paused:
		return
	if not ("resource" in _resource_unit):
		return
	_collect_counter += 1
	if _collect_counter >= COLLECT_TICKS:
		_collect_counter = 0
		_transfer_single_resource_unit_from_resource_to_worker()


func _transfer_single_resource_unit_from_resource_to_worker():
	if not MatchUtils.Movement.units_adhere(_unit, _resource_unit):
		queue_free()
		return
	if "resource" in _resource_unit:
		var remaining_capacity = _unit.resources_max - _unit.resource
		var amount = mini(
			_unit.resources_gather_rate, mini(_resource_unit.resource, remaining_capacity)
		)
		_resource_unit.resource -= amount
		_unit.resource += amount
	if _unit.is_full() or _resource_unit.resource <= 0:
		queue_free()


func _rotate_unit_towards_resource_unit():
	_unit.global_transform = _unit.global_transform.looking_at(
		Vector3(
			_resource_unit.global_position.x,
			_unit.global_position.y,
			_resource_unit.global_position.z
		),
		Vector3(0, 1, 0)
	)


func _on_passive_movement_started():
	_paused = true


func _on_passive_movement_finished():
	_paused = false
	_rotate_unit_towards_resource_unit()


func _on_resource_changed():
	if _resource_unit.resource <= 0:
		queue_free()
