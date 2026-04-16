class_name RadixStructure extends "res://source/match/units/Structure.gd"

## Radix structures must be placed on creep tiles.
## Structures that produce their own creep (CreepSource) override this to false.
var requires_creep: bool = true

## Accumulated fractional damage from off-creep decay.
var _off_creep_damage_remainder: float = 0.0
var _off_creep_tick: int = 0


func _ready():
	super()
	MatchSignals.tick_advanced.connect(_on_radix_structure_tick)


func _exit_tree():
	super()
	if MatchSignals.tick_advanced.is_connected(_on_radix_structure_tick):
		MatchSignals.tick_advanced.disconnect(_on_radix_structure_tick)


func _on_radix_structure_tick() -> void:
	if not requires_creep:
		return
	if not is_constructed():
		return
	_off_creep_tick += 1
	if _off_creep_tick < RadixConstants.CREEP_OFF_CREEP_DAMAGE_INTERVAL_TICKS:
		return
	_off_creep_tick = 0
	if _is_on_creep():
		_off_creep_damage_remainder = 0.0
		return
	# 0.5% of max HP per interval
	var damage: float = (
		float(hp_max) * RadixConstants.CREEP_OFF_CREEP_DAMAGE_PERCENT + _off_creep_damage_remainder
	)
	var whole_damage: int = int(damage)
	_off_creep_damage_remainder = damage - float(whole_damage)
	if whole_damage > 0:
		hp = maxi(hp - whole_damage, 0)
		if hp <= 0:
			_handle_unit_death()


func _is_on_creep() -> bool:
	var creep_map: CreepMap = MatchGlobal.creep_map
	if creep_map == null:
		return false
	var cell: Vector2i = creep_map.world_to_cell(global_position)
	if cell.x < 0 or cell.y < 0 or cell.x >= creep_map.width or cell.y >= creep_map.height:
		return false
	return creep_map.is_any_creep(cell)


## Check whether a world position has creep (used by placement validation).
static func is_creep_at_position(pos: Vector3) -> bool:
	var creep_map: CreepMap = MatchGlobal.creep_map
	if creep_map == null:
		return false
	var cell: Vector2i = creep_map.world_to_cell(pos)
	if cell.x < 0 or cell.y < 0 or cell.x >= creep_map.width or cell.y >= creep_map.height:
		return false
	return creep_map.is_any_creep(cell)
