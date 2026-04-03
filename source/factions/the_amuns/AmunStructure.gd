class_name AmunStructure
extends "res://source/match/units/Structure.gd"
## Base class for all Amun faction structures.
## Displays a refraction-glass plane during construction and sell.

const SELL_DURATION_SEC: float = SELL_DURATION_TICKS * 0.1

var _assembly_effect: AssemblyEffect = null
var _was_selling: bool = false
var _sell_start_time: float = 0.0


func _ready() -> void:
	super()
	_assembly_effect = AssemblyEffect.new()
	_assembly_effect.name = "AssemblyEffect"
	add_child(_assembly_effect)


func mark_as_under_construction(self_constructing = false) -> void:
	super(self_constructing)
	# Clear the grey construction material so the structure is fully visible.
	_change_geometry_material(null)
	if _assembly_effect != null:
		_assembly_effect.show_effect()


func _finish_construction() -> void:
	if _assembly_effect != null:
		_assembly_effect.hide_effect()
	super()


func _process(delta: float) -> void:
	if _assembly_effect == null:
		return

	# Detect sell start.
	if is_selling and not _was_selling:
		_was_selling = true
		_sell_start_time = Time.get_ticks_msec() / 1000.0
		_assembly_effect.show_effect()

	# Cancel sell.
	if not is_selling and _was_selling:
		_was_selling = false
		_assembly_effect.hide_effect()

	# Hide effect right before sell completes (structure is about to be freed).
	if is_selling:
		var elapsed := Time.get_ticks_msec() / 1000.0 - _sell_start_time
		if elapsed >= SELL_DURATION_SEC * 0.95:
			_assembly_effect.hide_effect()
