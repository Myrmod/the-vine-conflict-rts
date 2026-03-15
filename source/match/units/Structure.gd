extends "res://source/match/units/Unit.gd"

signal constructed

const UNDER_CONSTRUCTION_MATERIAL = preload(
	"res://source/match/resources/materials/structure_under_construction.material.tres"
)
const SELL_DURATION_TICKS: int = 50  # 5 seconds at 10 ticks/s
const DISABLED_DARKEN := Color(0.4, 0.4, 0.4, 1.0)
const SELL_BAR_SCENE = preload("res://source/match/units/traits/SellBar.tscn")

## Terrain placement rules — checked by the map editor's EntityBrush.
## Add entries to allow placement on special terrain (WATER, SLOPE, etc.).
@export var placement_domains: Array[Enums.PlacementTypes] = []

## Which ProductionTabTypes this structure can produce units for.
## Set from Units.DEFAULT_PROPERTIES via _setup_default_properties_from_constants().
var produces: Array = []

## How structures produced by this building are constructed.
## Only meaningful on structures that produce STRUCTURE tab items (e.g. CommandCenter).
var structure_production_type: int = Enums.StructureProductionType.CONSTRUCT_ON_FIELD_AND_TRICKLE

## Maximum number of structures that can be produced concurrently.
var max_concurrent_structures: int = 1

## Completed off-field structures waiting to be placed (scene paths).
var _ready_structures: Array = []

## Energy this structure provides when constructed (e.g. PowerPlant).
var energy_provided: int = 0
## Energy this structure requires when constructed.
var energy_required: int = 0
## Scene paths of structures that must be built before this one can be placed.
var structure_requirements: Array = []

## ── Structure action state ──────────────────────────────
## Disabled: production halted, visually darkened.
var is_disabled: bool = false
## Selling: ticks down from SELL_DURATION_TICKS to 0, then sells.
var is_selling: bool = false
## Repairing: ticks up like reverse damage, costs proportional.
var is_repairing: bool = false
## Construction paused: first right-click in grid stops progress.
var is_construction_paused: bool = false

var _construction_progress: float = 1.0
var _self_constructing = false
var _self_construction_speed = 0.0

## Trickle cost state — set by Match.gd for ON_FIELD+TRICKLE structures.
## When non-empty, resources are deducted proportionally during construction.
var _trickle_cost: Dictionary = {}
var _trickle_cost_deducted: float = 0.0

## Public read access to construction progress (0.0 → 1.0).
var construction_progress: float:
	get:
		return _construction_progress
var _occupied_cell: Vector2i
var _footprint: Vector2i = Vector2i(1, 1)
var _sell_ticks_remaining: int = 0
var _repair_hp_per_tick: float = 0.0
var _repair_cost_per_tick: float = 0.0
var _repair_hp_remainder: float = 0.0

@onready var production_queue = find_child("ProductionQueue"):
	set(_value):
		pass


func _ready():
	super()
	var map = MatchGlobal.map
	if map == null:
		return

	_occupied_cell = map.world_to_cell(global_position)
	map.occupy_area(_occupied_cell, _footprint, Enums.OccupationType.STRUCTURE)
	MatchSignals.tick_advanced.connect(_on_tick_advanced)


func _process(delta):
	if (
		_self_constructing
		and is_under_construction()
		and not is_disabled
		and not is_construction_paused
		and _has_active_structure_producer()
	):
		var progress = delta * _self_construction_speed
		if not _trickle_cost.is_empty():
			if not _try_deduct_trickle(progress):
				return
		construct(progress)


func _on_tick_advanced() -> void:
	if is_selling:
		_sell_ticks_remaining -= 1
		if _sell_ticks_remaining <= 0:
			_complete_sell()
	if is_repairing:
		_tick_repair()


func is_revealing():
	return super() and is_constructed()


func mark_as_under_construction(self_constructing = false):
	assert(not is_under_construction(), "structure already under construction")
	_construction_progress = 0.0
	_self_constructing = self_constructing
	if _self_constructing:
		var scene_path = get_script().resource_path.replace(".gd", ".tscn")
		var construction_time = UnitConstants.DEFAULT_PROPERTIES.get(scene_path, {}).get(
			"build_time", 5.0
		)
		_self_construction_speed = 1.0 / construction_time
	_change_geometry_material(UNDER_CONSTRUCTION_MATERIAL)
	if hp == null:
		await ready
	hp = 1


## Deduct the trickle share of construction cost for the given progress fraction.
## Returns false if the player can't afford it (construction should pause).
func _try_deduct_trickle(progress: float) -> bool:
	if player == null:
		return true
	var target_progress = minf(_construction_progress + progress, 1.0)
	# Check affordability first
	for key in _trickle_cost:
		var total_for_key: int = _trickle_cost[key]
		var already: int = int(_trickle_cost_deducted * total_for_key)
		var wanted: int = int(target_progress * total_for_key)
		var delta_cost: int = wanted - already
		if delta_cost > 0 and not player.has_resources({key: delta_cost}):
			return false
	# Deduct
	for key in _trickle_cost:
		var total_for_key: int = _trickle_cost[key]
		var already: int = int(_trickle_cost_deducted * total_for_key)
		var wanted: int = int(target_progress * total_for_key)
		var delta_cost: int = wanted - already
		if delta_cost > 0:
			player.subtract_resources({key: delta_cost})
	_trickle_cost_deducted = target_progress
	return true


func construct(progress):
	assert(is_under_construction(), "structure must be under construction")

	var expected_hp_before_progressing = int(_construction_progress * float(hp_max - 1))
	_construction_progress += progress
	var expected_hp_after_progressing = int(_construction_progress * float(hp_max - 1))
	if expected_hp_after_progressing > expected_hp_before_progressing:
		hp += 1
	if _construction_progress >= 1.0:
		_finish_construction()


## Pause / unpause construction progress (grid right-click).
func pause_construction() -> void:
	is_construction_paused = not is_construction_paused


func cancel_construction():
	# Only refund for non-trickle (upfront cost) builds.
	# Trickle builds only deducted what was spent — nothing to refund.
	if _trickle_cost.is_empty():
		var scene_path = get_script().resource_path.replace(".gd", ".tscn")
		var construction_cost = UnitConstants.DEFAULT_PROPERTIES[scene_path]["costs"]
		player.add_resources(construction_cost, Enums.ResourceType.CREDITS)
	EntityRegistry.unregister(self)
	queue_free()


func _exit_tree():
	if MatchGlobal.map != null:
		MatchGlobal.map.clear_area(_occupied_cell, _footprint)


func _handle_unit_death():
	if is_constructed():
		_remove_energy_from_player()
	super()


func is_constructed():
	return _construction_progress >= 1.0


func is_under_construction():
	return not is_constructed()


## Returns true if at least one constructed, non-disabled, non-selling
## structure of the same player produces the STRUCTURE tab.
func _has_active_structure_producer() -> bool:
	if player == null:
		return true
	for unit in get_tree().get_nodes_in_group("controlled_units"):
		if unit == self:
			continue
		if not "produces" in unit:
			continue
		if unit.player != player:
			continue
		if unit.is_under_construction():
			continue
		if unit.get("is_disabled"):
			continue
		if unit.get("is_selling"):
			continue
		if unit.produces.has(Enums.ProductionTabType.STRUCTURE):
			return true
	return false


## Cancel (refund + free) every under-construction structure owned by the
## same player that would no longer have any active producer after this
## structure is removed.  Called right before queue_free in _complete_sell().
func _cancel_orphaned_constructions() -> void:
	if player == null:
		return
	# Collect other active structure-producers (excluding self)
	var other_producers: Array = []
	for unit in get_tree().get_nodes_in_group("controlled_units"):
		if unit == self:
			continue
		if not "produces" in unit:
			continue
		if unit.player != player:
			continue
		if unit.is_under_construction():
			continue
		if unit.get("is_disabled"):
			continue
		if unit.get("is_selling"):
			continue
		if unit.produces.has(Enums.ProductionTabType.STRUCTURE):
			other_producers.append(unit)
	# If another producer still exists, nothing to cancel
	if not other_producers.is_empty():
		return
	# No producers left — cancel all under-construction structures
	var to_cancel: Array = []
	for unit in get_tree().get_nodes_in_group("controlled_units"):
		if unit == self:
			continue
		if unit.player != player:
			continue
		if not unit.has_method("is_under_construction"):
			continue
		if unit.is_under_construction():
			to_cancel.append(unit)
	for unit in to_cancel:
		unit.cancel_construction()


func _finish_construction():
	_self_constructing = false
	_change_geometry_material(null)
	_apply_energy_to_player()
	if is_inside_tree():
		constructed.emit()
		MatchSignals.unit_construction_finished.emit(self)


func _change_geometry_material(material):
	for child in find_child("Geometry").find_children("*"):
		if "material_override" in child:
			child.material_override = material


## Apply this structure's energy contribution/consumption to its player.
func _apply_energy_to_player() -> void:
	if player == null:
		return
	var delta := energy_provided - energy_required
	if delta != 0:
		player.energy += delta


## Reverse this structure's energy contribution/consumption from its player.
func _remove_energy_from_player() -> void:
	if player == null:
		return
	var delta := energy_provided - energy_required
	if delta != 0:
		player.energy -= delta


# ── Structure action helpers ─────────────────────────────


## Toggle sell countdown. Calling again cancels the sell.
## Cannot sell structures that are still under construction.
func toggle_sell() -> void:
	if is_under_construction():
		return
	if is_selling:
		is_selling = false
		_sell_ticks_remaining = 0
		_remove_sell_bar()
		return
	is_selling = true
	_sell_ticks_remaining = SELL_DURATION_TICKS
	_add_sell_bar()


func _complete_sell() -> void:
	is_selling = false
	_remove_sell_bar()
	_remove_energy_from_player()
	var scene_path = get_script().resource_path.replace(".gd", ".tscn")
	var cost = UnitConstants.DEFAULT_PROPERTIES.get(scene_path, {}).get("costs", {})
	# Refund 50 %
	if not cost.is_empty():
		var refund := {}
		for key in cost:
			refund[key] = int(cost[key] * 0.5)
		player.add_resources(refund)
	# Cancel all under-construction structures that no longer have a producer
	_cancel_orphaned_constructions()
	EntityRegistry.unregister(self)
	queue_free()


func _add_sell_bar() -> void:
	if find_child("SellBar") != null:
		return
	var bar = SELL_BAR_SCENE.instantiate()
	add_child(bar)


func _remove_sell_bar() -> void:
	var bar = find_child("SellBar")
	if bar != null:
		remove_child(bar)
		bar.queue_free()


## Toggle repair.  repair_rate_percentage defines the fraction of hp_max
## restored per second (default 5 %).  Cost per second equals
## repair_rate_percentage × total_damage_cost (so full-damage repair costs
## the same total credits regardless of rate).
func toggle_repair(repair_rate_percentage: float = 0.05) -> void:
	if is_repairing:
		is_repairing = false
		_repair_hp_per_tick = 0.0
		_repair_cost_per_tick = 0.0
		_repair_hp_remainder = 0.0
		return
	if hp >= hp_max:
		return  # already full
	var scene_path = get_script().resource_path.replace(".gd", ".tscn")
	var props = UnitConstants.DEFAULT_PROPERTIES.get(scene_path, {})
	var cost = props.get("costs", {})
	var credit_cost: float = float(cost.get("credits", 0))
	var missing_hp: float = float(hp_max - hp)
	# HP restored per tick  (rate is per second, TICK_RATE ticks per second)
	_repair_hp_per_tick = (repair_rate_percentage * float(hp_max)) / float(MatchConstants.TICK_RATE)
	# Cost per tick: repair_rate_percentage of total damage cost, per second
	var damage_cost: float = credit_cost * (missing_hp / float(hp_max))
	_repair_cost_per_tick = (repair_rate_percentage * damage_cost) / float(MatchConstants.TICK_RATE)
	# Check the player can afford at least the first tick
	if not player.has_resources({"credits": int(ceil(_repair_cost_per_tick))}):
		return
	_repair_hp_remainder = 0.0
	is_repairing = true


func _tick_repair() -> void:
	# Deduct cost
	var tick_cost := int(ceil(_repair_cost_per_tick))
	if tick_cost > 0:
		if not player.has_resources({"credits": tick_cost}):
			# Out of money — stop repairing
			is_repairing = false
			_repair_hp_per_tick = 0.0
			_repair_cost_per_tick = 0.0
			_repair_hp_remainder = 0.0
			return
		player.subtract_resources({"credits": tick_cost})
	# Accumulate fractional HP and apply whole points
	_repair_hp_remainder += _repair_hp_per_tick
	var whole_hp := int(_repair_hp_remainder)
	if whole_hp > 0:
		_repair_hp_remainder -= float(whole_hp)
		hp = mini(hp + whole_hp, hp_max)
	if hp >= hp_max:
		hp = hp_max
		is_repairing = false
		_repair_hp_per_tick = 0.0
		_repair_cost_per_tick = 0.0
		_repair_hp_remainder = 0.0


## Toggle disabled state: halts production, darkens visual.
## On under-construction structures this also pauses building.
func toggle_disable() -> void:
	is_disabled = not is_disabled
	if is_disabled:
		_apply_disabled_visual()
		# Pause all production
		if production_queue != null:
			for el in production_queue.get_elements():
				if not el.paused:
					production_queue.toggle_pause(el.unit_prototype.resource_path)
	else:
		_remove_disabled_visual()
		# Unpause all production
		if production_queue != null:
			for el in production_queue.get_elements():
				if el.paused:
					production_queue.toggle_pause(el.unit_prototype.resource_path)
	MatchSignals.structure_disabled_changed.emit(self)


func _apply_disabled_visual() -> void:
	var geo = find_child("Geometry")
	if geo == null:
		return
	for child in geo.find_children("*"):
		if child is MeshInstance3D:
			if child.material_override == null:
				var mat := StandardMaterial3D.new()
				mat.albedo_color = DISABLED_DARKEN
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				child.material_override = mat


func _remove_disabled_visual() -> void:
	var geo = find_child("Geometry")
	if geo == null:
		return
	for child in geo.find_children("*"):
		if child is MeshInstance3D:
			if (
				child.material_override != null
				and child.material_override is StandardMaterial3D
				and child.material_override.albedo_color == DISABLED_DARKEN
			):
				child.material_override = null
