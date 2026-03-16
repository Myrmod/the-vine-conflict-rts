extends "res://source/match/units/actions/Action.gd"

var _target_unit: Node3D = null

@onready var _unit: Node3D = Utils.NodeEx.find_parent_with_group(self, "units")
@onready var _unit_movement_trait: Node = _unit.find_child("Movement")


func _init(target_unit: Node3D) -> void:
	_target_unit = target_unit


func _ready() -> void:
	if _teardown_if_out_of_range():
		return
	_target_unit.tree_exited.connect(_on_target_unit_removed)
	if _unit_movement_trait != null:
		_unit_movement_trait.passive_movement_started.connect(_on_passive_movement_started)
		_unit_movement_trait.passive_movement_finished.connect(_on_passive_movement_finished)
	MatchSignals.tick_advanced.connect(_on_tick_advanced)
	# Try to fire immediately if cooldown has elapsed
	_try_hit()


func _physics_process(_delta: float) -> void:
	if _unit_movement_trait == null:
		_rotate_unit_towards_target()  # stationary units can rotate every frame


func _on_tick_advanced() -> void:
	_try_hit()


func _try_hit() -> void:
	var next_attack_tick: int = _unit.get_meta("next_attack_tick", 0)
	if Match.tick < next_attack_tick:
		return
	if _teardown_if_out_of_range():
		return
	_hit_target()


func _rotate_unit_towards_target() -> void:
	_unit.global_transform = _unit.global_transform.looking_at(
		Vector3(
			_target_unit.global_position.x, _unit.global_position.y, _target_unit.global_position.z
		),
		Vector3(0, 1, 0)
	)


func _hit_target() -> void:
	_rotate_unit_towards_target()
	# Schedule next attack in ticks (attack_interval is in seconds)
	var cooldown_ticks: int = maxi(1, int(_unit.attack_interval / MatchConstants.TICK_DELTA))
	_unit.set_meta("next_attack_tick", Match.tick + cooldown_ticks)
	var from: Vector3 = _unit.global_position + _unit.projectile_origin
	var to: Vector3 = _target_unit.global_position
	var config: Dictionary = _unit.projectile_config.duplicate()
	config["damage"] = _unit.attack_damage
	config["target_unit"] = _target_unit
	config["source_player"] = _unit.player
	config["attack_type"] = _unit.attack_type
	Projectile.fire(_unit.projectile_type, from, to, config)


func _teardown_if_out_of_range() -> bool:
	if (
		_unit.global_position_yless.distance_to(_target_unit.global_position_yless)
		> _unit.attack_range
	):
		queue_free()
		return true
	return false


func _on_target_unit_removed() -> void:
	queue_free()


func _on_passive_movement_started() -> void:
	pass  # no-op: tick-based attack will simply not fire while out of range


func _on_passive_movement_finished() -> void:
	_rotate_unit_towards_target()
