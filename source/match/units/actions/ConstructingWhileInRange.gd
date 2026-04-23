extends "res://source/match/units/actions/Action.gd"

var _target_unit = null

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


func _on_tick_advanced():
	if not MatchUtils.Movement.units_adhere(_unit, _target_unit) or _target_unit.is_constructed():
		queue_free()
		return
	if _target_unit.has_method("begin_seedling_self_construction"):
		if _target_unit.begin_seedling_self_construction(_unit):
			EntityRegistry.unregister(_unit)
			_unit.queue_free()
			queue_free()
			return
	var speed_mult := 0.75 if _unit.player != null and _unit.player.energy < 0 else 1.0
	_target_unit.construct(
		MatchConstants.TICK_DELTA * UnitConstants.STRUCTURE_CONSTRUCTING_SPEED * speed_mult
	)
