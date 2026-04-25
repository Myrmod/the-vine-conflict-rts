class_name CreepSource extends RadixStructure

@export var spread_radius: int = 10

var _player_bit: int = 0
var _owned_cells: Array[Vector2i] = []
## Frontier = owned cells that still have at least one unowned neighbour
## within spread_radius. Updated incrementally instead of rescanning all cells.
var _frontier: Array[Vector2i] = []
var _frontier_set: Dictionary = {}
var _tick_counter: int = 0
## Pre-computed set of local cell offsets that are valid for spreading.
## Matches the build radius shape (circular with cardinal protrusions pruned).
var _allowed_offsets: Dictionary = {}


func _init() -> void:
	# CreepSource produces its own creep — no off-creep damage.
	requires_creep = false


func _ready() -> void:
	super()
	_ensure_creep_map_initialized()
	_ensure_creep_system()
	_player_bit = _compute_player_bit()
	_compute_allowed_offsets()
	MatchSignals.tick_advanced.connect(_on_creep_tick)


## Build the set of local offsets that creep can spread to.
## Uses the BuildRadius node's radius_in_cells if present, otherwise spread_radius.
## Applies the same circular + cardinal-protrusion-pruning as BuildRadius.
func _compute_allowed_offsets() -> void:
	var radius: int = spread_radius
	var build_radius_node: Node = find_child("BuildRadius")
	if build_radius_node != null and build_radius_node.get("radius_in_cells") != null:
		var r: int = build_radius_node.radius_in_cells
		if r > 0:
			radius = r
	spread_radius = radius
	# First pass: collect all cells within radius.
	var candidates: Dictionary = {}
	for x: int in range(-radius, radius + 1):
		for y: int in range(-radius, radius + 1):
			if Vector2(x, y).length() <= float(radius):
				candidates[Vector2i(x, y)] = true
	# Second pass: prune cells with fewer than 2 cardinal neighbours.
	for offset: Vector2i in candidates.keys():
		var neighbor_count: int = 0
		for dir: Vector2i in _ORTHO_DIRS:
			if candidates.has(offset + dir):
				neighbor_count += 1
		if neighbor_count >= 2:
			_allowed_offsets[offset] = true


## Fill the entire spread radius with creep immediately.
func spread_creep_instantly() -> void:
	var creep_map: CreepMap = MatchGlobal.creep_map
	if creep_map == null:
		return
	var map = MatchGlobal.map
	if map == null:
		return
	var center: Vector2i = map.world_to_cell(global_position)
	for offset: Vector2i in _allowed_offsets:
		var cell: Vector2i = center + offset
		if not _cell_in_bounds(cell, map):
			continue
		if creep_map.is_any_creep(cell):
			continue
		creep_map.set_player_bit(cell, _player_bit, true)
		creep_map.set_cell_health(cell, RadixConstants.CREEP_CELL_MAX_HEALTH)
		_owned_cells.append(cell)
	_frontier.clear()
	_frontier_set.clear()
	for cell: Vector2i in _owned_cells:
		_add_to_frontier(cell, creep_map, center, map)
	MatchSignals.creep_map_changed.emit()


func _exit_tree() -> void:
	super()
	if MatchSignals.tick_advanced.is_connected(_on_creep_tick):
		MatchSignals.tick_advanced.disconnect(_on_creep_tick)
	# Owned cells are abandoned. The decay system will remove them naturally.


func _on_creep_tick() -> void:
	if not is_constructed():
		return
	_tick_counter += 1
	if _tick_counter < RadixConstants.CREEP_SPREAD_INTERVAL_TICKS:
		return
	_tick_counter = 0
	_vitalize_cells()
	_spread_creep()


func _spread_creep() -> void:
	var creep_map: CreepMap = MatchGlobal.creep_map
	if creep_map == null:
		return
	var map = MatchGlobal.map
	var center: Vector2i = map.world_to_cell(global_position)

	# Bootstrap: seed owned cells if nothing owned yet.
	if _owned_cells.is_empty():
		if not _cell_in_bounds(center, map):
			return
		# Always start from the source center, so expansion radiates out from this
		# source and does not "jump" to nearby creep already inside the radius.
		creep_map.set_player_bit(center, _player_bit, true)
		creep_map.set_cell_health(center, RadixConstants.CREEP_CELL_MAX_HEALTH)
		_owned_cells.append(center)
		for cell: Vector2i in _owned_cells:
			_add_to_frontier(cell, creep_map, center, map)
		MatchSignals.creep_map_changed.emit()
		return

	if _frontier.is_empty():
		return

	# Build candidate list from frontier neighbours only.
	var candidates: Array[Vector2i] = _gather_candidates(creep_map, center, map)
	if candidates.is_empty():
		return

	for _i: int in range(RadixConstants.CREEP_SPREAD_TILES_PER_INTERVAL):
		if candidates.is_empty():
			break
		var cell: Vector2i = candidates[0]
		candidates.remove_at(0)
		creep_map.set_player_bit(cell, _player_bit, true)
		creep_map.set_cell_health(cell, RadixConstants.CREEP_CELL_MAX_HEALTH)
		_owned_cells.append(cell)
		_add_to_frontier(cell, creep_map, center, map)
	_prune_frontier(creep_map, center, map)
	MatchSignals.creep_map_changed.emit()


const _ORTHO_DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]


func _gather_candidates(creep_map: CreepMap, center: Vector2i, map) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen: Dictionary = {}
	for owned: Vector2i in _frontier:
		for dir: Vector2i in _ORTHO_DIRS:
			var candidate: Vector2i = owned + dir
			if seen.has(candidate):
				continue
			seen[candidate] = true
			if not _cell_in_bounds(candidate, map):
				continue
			if creep_map.is_any_creep(candidate):
				continue
			if not _allowed_offsets.has(candidate - center):
				continue
			result.append(candidate)
	# Sort closest-first so spread always expands outward from the source center.
	result.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (a - center).length_squared() < (b - center).length_squared()
	)
	return result


## Add a newly-owned cell to the frontier if it has expandable orthogonal neighbours.
func _add_to_frontier(cell: Vector2i, creep_map: CreepMap, center: Vector2i, map) -> void:
	if _frontier_set.has(cell):
		return
	for dir: Vector2i in _ORTHO_DIRS:
		var n: Vector2i = cell + dir
		if not _cell_in_bounds(n, map):
			continue
		if creep_map.is_any_creep(n):
			continue
		if not _allowed_offsets.has(n - center):
			continue
		_frontier.append(cell)
		_frontier_set[cell] = true
		return


## Remove frontier cells that no longer have any expandable neighbours.
func _prune_frontier(creep_map: CreepMap, center: Vector2i, map) -> void:
	var new_frontier: Array[Vector2i] = []
	var new_set: Dictionary = {}
	for cell: Vector2i in _frontier:
		if _has_expandable_neighbour(cell, creep_map, center, map):
			new_frontier.append(cell)
			new_set[cell] = true
	_frontier = new_frontier
	_frontier_set = new_set


func _has_expandable_neighbour(cell: Vector2i, creep_map: CreepMap, center: Vector2i, map) -> bool:
	for dir: Vector2i in _ORTHO_DIRS:
		var n: Vector2i = cell + dir
		if not _cell_in_bounds(n, map):
			continue
		if creep_map.is_any_creep(n):
			continue
		if not _allowed_offsets.has(n - center):
			continue
		return true
	return false


func _cell_in_bounds(cell: Vector2i, map) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(map.size.x) and cell.y < int(map.size.y)


## Reset health to max for all owned cells, keeping them alive while this source exists.
## Called every spread interval, so cells decay at most DECAY_AMOUNT between vitalizations.
func _vitalize_cells() -> void:
	var creep_map: CreepMap = MatchGlobal.creep_map
	if creep_map == null:
		return
	for cell: Vector2i in _owned_cells:
		creep_map.set_cell_health(cell, RadixConstants.CREEP_CELL_MAX_HEALTH)


func _compute_player_bit() -> int:
	var radix_count: int = _count_radix_players()
	var bit_width: int = 8 if radix_count <= 8 else 32
	if player == null:
		return 0
	return player.id % bit_width


func _count_radix_players() -> int:
	var count: int = 0
	for p: Node in get_tree().get_nodes_in_group("players"):
		if (p as Player).faction == Enums.Faction.RADIX:
			count += 1
	return count


func _ensure_creep_map_initialized() -> void:
	if MatchGlobal.creep_map != null:
		return
	var map = MatchGlobal.map
	if map == null:
		return
	var radix_count: int = _count_radix_players()
	var cm: CreepMap = CreepMap.new()
	cm.initialize(int(map.size.x), int(map.size.y), radix_count)
	MatchGlobal.creep_map = cm


func _ensure_creep_system() -> void:
	if MatchGlobal.creep_system != null:
		return
	var cs: CreepSystem = CreepSystem.new()
	MatchGlobal.map.get_parent().add_child(cs)
	MatchGlobal.creep_system = cs
