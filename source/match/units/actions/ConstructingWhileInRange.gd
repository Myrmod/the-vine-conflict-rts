extends "res://source/match/units/actions/Action.gd"

var _target_unit = null
## When the target structure requires a Seedling to start, the unit must first
## play the `build` animation for SEEDLING_BUILD_ANIM_TICKS ticks before being
## consumed. This counter is incremented while the unit is in range.
var _build_anim_ticks: int = 0
var _build_anim_started: bool = false

@onready var _unit = Utils.NodeEx.find_parent_with_group(self, "units")


func _init(target_unit):
	_target_unit = target_unit


func _ready():
	_target_unit.tree_exited.connect(queue_free)
	_target_unit.constructed.connect(queue_free)
	var sparkling = _unit.get_node_or_null("Sparkling")
	if sparkling != null:
		sparkling.enable()
	MatchSignals.tick_advanced.connect(_on_tick_advanced)


func _exit_tree():
	var sparkling = _unit.get_node_or_null("Sparkling")
	if sparkling != null:
		sparkling.disable()
	if _build_anim_started and _unit != null and is_instance_valid(_unit):
		var animator = _unit.find_child("UnitAnimator")
		if animator != null and animator.has_method("stop_special"):
			animator.stop_special()


func _on_tick_advanced():
	if not MatchUtils.Movement.units_adhere(_unit, _target_unit) or _target_unit.is_constructed():
		queue_free()
		return
	if _target_unit.has_method("begin_seedling_self_construction"):
		# Seedling-started construction: play the build animation first, then
		# consume the Seedling once the animation ticks have elapsed.
		if not _build_anim_started:
			_start_build_animation()
		_build_anim_ticks += 1
		if _build_anim_ticks < RadixConstants.SEEDLING_BUILD_ANIM_TICKS:
			return
		if _target_unit.begin_seedling_self_construction(_unit):
			EntityRegistry.unregister(_unit)
			_unit.queue_free()
			queue_free()
			return
	var speed_mult := 0.75 if _unit.player != null and _unit.player.energy < 0 else 1.0
	_target_unit.construct(
		MatchConstants.TICK_DELTA * UnitConstants.STRUCTURE_CONSTRUCTING_SPEED * speed_mult
	)


func _start_build_animation() -> void:
	_build_anim_started = true
	# Snap the seedling to the structure center so the animation plays in place.
	if _target_unit is Node3D and _unit is Node3D:
		var movement_trait: Node = _unit.find_child("Movement")
		if movement_trait != null and movement_trait.has_method("stop"):
			movement_trait.stop()
		_unit.global_position = (_target_unit as Node3D).global_position
		if movement_trait != null and movement_trait.has_method("resync_tick_transform"):
			movement_trait.resync_tick_transform()
	var animator = _unit.find_child("UnitAnimator")
	if animator != null and animator.has_method("play_special"):
		animator.play_special("build")
