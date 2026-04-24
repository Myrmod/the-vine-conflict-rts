class_name Linker extends "res://source/factions/the_radix/structures/RadixSeedlingStartedStructure.gd"

const LINK_RADIUS_M: float = 8.0
const MAX_LINKED_TILES: int = 5
const INCOME_INTERVAL_TICKS: int = 10
const MAX_INCOME_PER_TILE_PER_INTERVAL: float = 4.0

static var _tile_link_owner_by_id: Dictionary = {}
static var _linked_tile_ids_by_linker_id: Dictionary = {}
static var _last_link_refresh_tick: int = -1

var _income_tick_counter: int = 0
var _income_remainder: float = 0.0
var _linked_tile_ids: Array[int] = []


func _ready() -> void:
	super()
	MatchSignals.tick_advanced.connect(_on_linker_tick)


func _exit_tree() -> void:
	super()
	if MatchSignals.tick_advanced.is_connected(_on_linker_tick):
		MatchSignals.tick_advanced.disconnect(_on_linker_tick)


func _on_linker_tick() -> void:
	if not is_constructed() or player == null:
		return
	_refresh_global_links_if_needed()
	_sync_owned_links_from_registry()
	_income_tick_counter += 1
	if _income_tick_counter < INCOME_INTERVAL_TICKS:
		return
	_income_tick_counter = 0
	_grant_linked_income()


func _grant_linked_income() -> void:
	var total_income: float = _income_remainder
	for tile_id: int in _linked_tile_ids:
		var tile = EntityRegistry.get_unit(tile_id)
		if tile == null or not is_instance_valid(tile):
			continue
		if not ("resource" in tile) or not ("resource_max" in tile):
			continue
		if tile.resource_max <= 0 or tile.resource <= 0:
			continue
		var fullness: float = float(tile.resource) / float(tile.resource_max)
		total_income += MAX_INCOME_PER_TILE_PER_INTERVAL * fullness
	var payout: int = int(floor(total_income))
	_income_remainder = total_income - float(payout)
	if payout > 0:
		player.credits += payout


func _sync_owned_links_from_registry() -> void:
	_linked_tile_ids.clear()
	var raw_link_ids: Variant = _linked_tile_ids_by_linker_id.get(id, [])
	for tile_id_variant: Variant in raw_link_ids:
		_linked_tile_ids.append(int(tile_id_variant))


func _refresh_global_links_if_needed() -> void:
	if _last_link_refresh_tick == Match.tick:
		return
	_last_link_refresh_tick = Match.tick
	_tile_link_owner_by_id.clear()
	_linked_tile_ids_by_linker_id.clear()

	var all_linkers: Array = get_tree().get_nodes_in_group("units").filter(
		func(unit):
			return (
				unit is Linker
				and is_instance_valid(unit)
				and unit.is_constructed()
				and unit.player != null
			)
	)
	all_linkers.sort_custom(func(a, b): return a.id < b.id)

	for linker_node: Variant in all_linkers:
		var linker: Linker = linker_node
		var chosen_tile_ids: Array[int] = []
		var candidates: Array = _build_link_candidates_for(linker)
		for candidate: Dictionary in candidates:
			if chosen_tile_ids.size() >= MAX_LINKED_TILES:
				break
			var tile_id: int = candidate["tile_id"]
			if _tile_link_owner_by_id.has(tile_id):
				continue
			_tile_link_owner_by_id[tile_id] = linker.id
			chosen_tile_ids.append(tile_id)
		_linked_tile_ids_by_linker_id[linker.id] = chosen_tile_ids


func _build_link_candidates_for(linker: Linker) -> Array:
	var candidates: Array = []
	for tile_variant: Variant in get_tree().get_nodes_in_group("resource_units"):
		if tile_variant == null or not is_instance_valid(tile_variant):
			continue
		if not ("resource" in tile_variant) or tile_variant.resource <= 0:
			continue
		if not ("resource_max" in tile_variant) or tile_variant.resource_max <= 0:
			continue
		if tile_variant.id == null:
			continue
		var distance: float = (linker.global_position * Vector3(1, 0, 1)).distance_to(
			tile_variant.global_position * Vector3(1, 0, 1)
		)
		if distance > LINK_RADIUS_M:
			continue
		var fullness: float = float(tile_variant.resource) / float(tile_variant.resource_max)
		(
			candidates
			. append(
				{
					"tile_id": int(tile_variant.id),
					"distance": distance,
					"fullness": fullness,
				}
			)
		)
	candidates.sort_custom(_sort_link_candidate)
	return candidates


func _sort_link_candidate(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(a["fullness"], b["fullness"]):
		return a["fullness"] > b["fullness"]
	if not is_equal_approx(a["distance"], b["distance"]):
		return a["distance"] < b["distance"]
	return a["tile_id"] < b["tile_id"]
