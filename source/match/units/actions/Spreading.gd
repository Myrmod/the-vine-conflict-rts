## Spreading: Radix Seedling `spread` ability.
## Phases:
##   1. WALK   - move to target ground position via the Movement trait.
##   2. BUILD  - play `build` animation for SEEDLING_BUILD_ANIM_TICKS.
##   3. GROW   - play `grow` animation for SEEDLING_GROW_ANIM_TICKS.
##   4. SPAWN  - replace the Seedling with a Sapling structure at the target.
##
## Designed to be deterministic for lockstep multiplayer: phase progression is
## driven by MatchSignals.tick_advanced, never by real-time animation signals.
extends "res://source/match/units/actions/Action.gd"

const SAPLING_SCENE := preload("res://source/factions/the_radix/structures/Sapling.tscn")

enum Phase { WALK, BUILD, GROW, DONE }

var _target_position: Vector3
var _phase: int = Phase.WALK
var _phase_ticks: int = 0

@onready var _unit = Utils.NodeEx.find_parent_with_group(self, "units")
@onready var _movement_trait = _unit.find_child("Movement") if _unit != null else null


static func is_applicable(unit) -> bool:
	if unit == null:
		return false
	return unit.find_child("Movement") != null


func _init(target_position: Vector3) -> void:
	_target_position = target_position


func _ready() -> void:
	if _movement_trait == null:
		queue_free()
		return
	# Ensure animation traits re-evaluate runtime state as this action starts.
	if _unit != null:
		_unit.action_updated.emit()
	_movement_trait.move(_target_position)
	_movement_trait.movement_finished.connect(_on_movement_finished)
	MatchSignals.tick_advanced.connect(_on_tick_advanced)


func _exit_tree() -> void:
	if is_inside_tree() and _movement_trait != null and _phase == Phase.WALK:
		_movement_trait.stop()
	if _unit != null and is_instance_valid(_unit):
		var animator = _unit.find_child("UnitAnimator")
		if animator != null and animator.has_method("stop_special"):
			animator.stop_special()


func _on_movement_finished() -> void:
	if _phase != Phase.WALK:
		return
	_enter_build_phase()


func _on_tick_advanced() -> void:
	match _phase:
		Phase.BUILD:
			_phase_ticks += 1
			if _phase_ticks >= RadixConstants.SEEDLING_BUILD_ANIM_TICKS:
				_enter_grow_phase()
		Phase.GROW:
			_phase_ticks += 1
			if _phase_ticks >= RadixConstants.SEEDLING_GROW_ANIM_TICKS:
				_complete_spread()


func _enter_build_phase() -> void:
	_phase = Phase.BUILD
	_phase_ticks = 0
	if _unit is Node3D:
		(_unit as Node3D).global_position = _target_position
		if _movement_trait != null and _movement_trait.has_method("resync_tick_transform"):
			_movement_trait.resync_tick_transform()
		if _movement_trait != null and _movement_trait.has_method("stop"):
			_movement_trait.stop()
		# Persist the exact planted position after movement/terrain resync so the
		# Sapling appears exactly where the Seedling rooted itself.
		_target_position = (_unit as Node3D).global_position
	_play_animation("build")


func _enter_grow_phase() -> void:
	_phase = Phase.GROW
	_phase_ticks = 0
	_play_animation("grow")


func _complete_spread() -> void:
	_phase = Phase.DONE
	if _unit == null or not is_instance_valid(_unit):
		queue_free()
		return
	var player = _unit.player
	var spawn_transform := Transform3D(Basis(), _target_position)
	if _unit is Node3D:
		spawn_transform = (_unit as Node3D).global_transform
	var sapling: Node = SAPLING_SCENE.instantiate()
	if sapling != null and sapling.has_method("adopt_seedling_visuals"):
		sapling.adopt_seedling_visuals(_unit)
	MatchSignals.setup_and_spawn_unit.emit(sapling, spawn_transform, player, false)
	EntityRegistry.unregister(_unit)
	_unit.queue_free()
	queue_free()


func _play_animation(key: String) -> void:
	if _unit == null or not is_instance_valid(_unit):
		return
	var animator = _unit.find_child("UnitAnimator")
	if animator != null and animator.has_method("play_special"):
		animator.play_special(key)
