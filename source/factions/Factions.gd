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
	for key in UnitConstants.DEFAULT_PROPERTIES:
		if !key.contains(identifier):
			continue
		var entry = UnitConstants.DEFAULT_PROPERTIES[key].duplicate()
		entry["scene_path"] = key
		production_grid[entry.production_tab_type].append(entry)


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
