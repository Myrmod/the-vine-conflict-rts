class_name AmunStructure
extends "res://source/match/units/Structure.gd"
## Base class for all Amun faction structures.
## Automatically plays the AssemblyEffect during construction (assemble in)
## and when sold (dissolve out).

const SELL_DURATION_SEC: float = SELL_DURATION_TICKS * 0.1  # mirrors TICK_DELTA

var _assembly_effect: AssemblyEffect = null
var _was_selling: bool = false
var _sell_start_time: float = 0.0


func _ready() -> void:
	super()
	_assembly_effect = AssemblyEffect.new()
	_assembly_effect.name = "AssemblyEffect"
	add_child(_assembly_effect)
	# If loaded mid-construction (save/load), start from correct progress.
	if is_under_construction():
		_assembly_effect.set_progress(1.0 - _construction_progress)


func mark_as_under_construction(self_constructing = false) -> void:
	super(self_constructing)
	# super() sets material_override to the grey construction material which
	# hides our per-surface shader overrides. Clear it so the effect is visible.
	_change_geometry_material(null)
	if _assembly_effect != null:
		_assembly_effect.assembling = true
		_assembly_effect.set_progress(1.0)  # start fully scattered


func _finish_construction() -> void:
	if _assembly_effect != null:
		_assembly_effect.set_progress(0.0)
		_assembly_effect.clear()
	super()


func _process(delta: float) -> void:
	if _assembly_effect == null:
		return

	# Drive construction animation from the actual construction progress.
	if is_under_construction():
		_assembly_effect.set_progress(1.0 - _construction_progress)
		return

	# Detect sell start.
	if is_selling and not _was_selling:
		_was_selling = true
		_sell_start_time = Time.get_ticks_msec() / 1000.0
		_assembly_effect.assembling = false  # switch to dissolve direction
		_assembly_effect._build_scatter_positions()  # fresh random scatter targets

	# Cancel sell.
	if not is_selling and _was_selling:
		_was_selling = false
		_assembly_effect.set_progress(0.0)

	# Drive sell animation in real-time (SELL_DURATION_SEC = 5 s).
	if is_selling:
		var elapsed := Time.get_ticks_msec() / 1000.0 - _sell_start_time
		_assembly_effect.set_progress(clampf(elapsed / SELL_DURATION_SEC, 0.0, 1.0))
