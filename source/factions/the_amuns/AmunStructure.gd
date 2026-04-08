class_name AmunStructure
extends "res://source/match/units/Structure.gd"
## Base class for all Amun faction structures.
## Automatically plays the TeleporterEffect during construction (teleporter
## ring + pixelated reveal) and when sold (dissolve out).

const SELL_DURATION_SEC: float = SELL_DURATION_TICKS * 0.1

var _teleporter_effect: TeleporterEffect = null
var _was_selling: bool = false
var _sell_start_time: float = 0.0


func _ready() -> void:
	super()
	_teleporter_effect = TeleporterEffect.new()
	_teleporter_effect.name = "TeleporterEffect"
	add_child(_teleporter_effect)
	# If loaded mid-construction (save/load), start from correct progress.
	if is_under_construction():
		_teleporter_effect.set_progress(1.0 - _construction_progress)


func mark_as_under_construction(self_constructing = false) -> void:
	super(self_constructing)
	# Clear the grey construction material so the structure is fully visible.
	_change_geometry_material(null)
	if _teleporter_effect != null:
		_teleporter_effect.assembling = true
		_teleporter_effect.recompute_boundaries()
		_teleporter_effect.set_progress(1.0)  # start fully disassembled


func _finish_construction() -> void:
	if _teleporter_effect != null:
		_teleporter_effect.set_progress(0.0)
		_teleporter_effect.clear()
	super()


func _process(delta: float) -> void:
	if _teleporter_effect == null:
		return

	# Drive construction animation from the actual construction progress.
	if is_under_construction():
		_teleporter_effect.set_progress(1.0 - _construction_progress)
		return

	# Detect sell start.
	if is_selling and not _was_selling:
		_was_selling = true
		_sell_start_time = Time.get_ticks_msec() / 1000.0
		_teleporter_effect.assembling = false
		_teleporter_effect.recompute_boundaries()

	# Cancel sell.
	if not is_selling and _was_selling:
		_was_selling = false
		_teleporter_effect.reset()

	# Hide effect right before sell completes (structure is about to be freed).
	if is_selling:
		var elapsed := Time.get_ticks_msec() / 1000.0 - _sell_start_time
		_teleporter_effect.set_progress(clampf(elapsed / SELL_DURATION_SEC, 0.0, 1.0))
