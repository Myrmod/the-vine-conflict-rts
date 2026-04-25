class_name Factions

extends Node3D

static var production_grid = {
	Enums.ProductionTabType.STRUCTURE: [],
	Enums.ProductionTabType.DEFENCES: [],
	Enums.ProductionTabType.INFANTRY: [],
	Enums.ProductionTabType.VEHICLE: [],
	Enums.ProductionTabType.AIR: [],
	Enums.ProductionTabType.WATER: [],
}

static var credits = 10000
static var energy = 0


static func get_faction_by_enum(id: Enums.Faction):
	match id:
		Enums.Faction.AMUNS:
			return AmunsFaction
		Enums.Faction.LEGION:
			return LegionFaction
		Enums.Faction.RADIX:
			return RadixFaction
		Enums.Faction.REMNANTS:
			return RemnantsFaction
		_:
			push_error("Faction does not exist with enum: ", id)


static func _init_production_grid_values_by_identifier(identifier) -> void:
	UnitConstants.ensure_ready()
	# Reset all lists so repeated calls don't accumulate duplicates
	for tab_type in production_grid:
		production_grid[tab_type] = []
	for scene_id in UnitConstants.DEFAULT_PROPERTIES:
		var scene_path: String = UnitConstants.DEFAULT_PROPERTIES[scene_id].get("scene", "")
		if scene_path.is_empty() or !scene_path.contains(identifier):
			continue
		var entry = UnitConstants.DEFAULT_PROPERTIES[scene_id].duplicate()
		entry["scene_path"] = scene_path
		entry["scene_id"] = scene_id
		if entry.has("structure_requirements"):
			var req_ids: Array = []
			for req in entry["structure_requirements"]:
				req_ids.append(UnitConstants.get_scene_id(req))
			entry["structure_requirements"] = req_ids
		# Some units/structures exist only for runtime spawning (no production tab).
		if not entry.has("production_tab_type"):
			continue
		var tab_type: int = entry["production_tab_type"]
		if not production_grid.has(tab_type):
			continue
		production_grid[tab_type].append(entry)


static func get_production_grid():
	return production_grid


static func get_starting_resource():
	return {
		"credits": credits,
		"energy": energy,
	}


static func set_starting_resource(_credits: int, _energy: int):
	credits = _credits
	energy = _energy
