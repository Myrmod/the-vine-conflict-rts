class_name CreepSystem

extends Node3D

## Handles creep decay and HP regeneration for all Radix players.
## Created lazily by the first CreepSource to enter the tree.
## Decay: each CREEP_DECAY_INTERVAL_TICKS, every living cell loses CREEP_DECAY_AMOUNT health.
## Cells not vitalized by their owning CreepSource reach 0 and are cleared automatically.
## This makes source death cause a natural gradual retraction with no explicit retraction queue.

var _decay_tick: int = 0
var _regen_tick: int = 0
## Cached player-id → Player mapping, built once on first regen tick.
var _player_cache: Dictionary = {}


func _ready() -> void:
	MatchSignals.tick_advanced.connect(_on_tick_advanced)
	var renderer: CreepRenderer = CreepRenderer.new()
	add_child(renderer)


func _exit_tree() -> void:
	if MatchSignals.tick_advanced.is_connected(_on_tick_advanced):
		MatchSignals.tick_advanced.disconnect(_on_tick_advanced)
	MatchGlobal.creep_system = null


func _on_tick_advanced() -> void:
	_decay_tick += 1
	if _decay_tick >= RadixConstants.CREEP_DECAY_INTERVAL_TICKS:
		_decay_tick = 0
		_process_decay()

	_regen_tick += 1
	if _regen_tick >= RadixConstants.CREEP_REGEN_INTERVAL_TICKS:
		_regen_tick = 0
		_process_regen()


## Decrement health on every live cell. Cells reaching 0 are cleared.
## Cells kept alive by their owning CreepSource (via _vitalize_cells) will never hit 0.
func _process_decay() -> void:
	var creep_map: CreepMap = MatchGlobal.creep_map
	if creep_map == null:
		return
	var changed: bool = false
	for y: int in range(creep_map.height):
		for x: int in range(creep_map.width):
			var cell: Vector2i = Vector2i(x, y)
			if not creep_map.is_any_creep(cell):
				continue
			var health: int = creep_map.get_cell_health(cell)
			if health <= RadixConstants.CREEP_DECAY_AMOUNT:
				creep_map.clear_cell(cell)
				changed = true
			else:
				creep_map.set_cell_health(cell, health - RadixConstants.CREEP_DECAY_AMOUNT)
	if changed:
		MatchSignals.creep_map_changed.emit()


func _process_regen() -> void:
	var creep_map: CreepMap = MatchGlobal.creep_map
	if creep_map == null:
		return
	for unit: Node in get_tree().get_nodes_in_group("units"):
		var u: Unit = unit as Unit
		if u == null or u.player == null:
			continue
		if u.player.faction != Enums.Faction.RADIX:
			continue
		if u.hp == null or u.hp_max == null or u.hp >= u.hp_max:
			continue
		var cell: Vector2i = creep_map.world_to_cell(u.global_position)
		if cell.x < 0 or cell.y < 0 or cell.x >= creep_map.width or cell.y >= creep_map.height:
			continue
		if not creep_map.is_any_creep(cell):
			continue
		if not _cell_is_allied(cell, creep_map, u):
			continue
		u.hp = mini(u.hp + RadixConstants.CREEP_REGEN_HP_PER_INTERVAL, u.hp_max)


## Returns true if any bit set on the cell belongs to the same team as the unit,
## or belongs to the unit's own player.
func _cell_is_allied(cell: Vector2i, creep_map: CreepMap, unit: Unit) -> bool:
	var bit_width: int = 8 if typeof(creep_map.cells) == TYPE_PACKED_BYTE_ARRAY else 32
	for bit: int in range(bit_width):
		if not creep_map.is_player_bit(cell, bit):
			continue
		var owner_id: int = bit
		var owner_player: Player = _get_cached_player(owner_id)
		if owner_player == null:
			continue
		if owner_player.team == unit.player.team:
			return true
	return false


func _get_cached_player(id: int) -> Player:
	if _player_cache.is_empty():
		for p: Node in get_tree().get_nodes_in_group("players"):
			_player_cache[(p as Player).id] = p
	if _player_cache.has(id):
		return _player_cache[id] as Player
	return null
