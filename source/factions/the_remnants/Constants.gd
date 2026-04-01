class_name RemnantConstants

const SOUND_ROCKET_START = preload("res://assets/sound_effects/rocket1_start.mp3")
const SOUND_ROCKET_END = preload("res://assets/sound_effects/rocket1_end.mp3")

const STRUCTURES = {
	"res://source/factions/the_remnants/structures/CommandCenter.tscn":
	{
		"unit_name": "remnants_CommandCenter",
		"description": "Central command hub. Builds structures and defences",
		"faction": Enums.Faction.REMNANTS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"produces": [Enums.ProductionTabType.STRUCTURE, Enums.ProductionTabType.DEFENCES],
		"max_concurrent_structures": 1,
		"sight_range": 10.0,
		"hp": 20,
		"hp_max": 20,
		"armor":
		{
			Enums.DamageTypes.CANNON: 0.5,
			Enums.DamageTypes.CORROSIVE: 0.0,
			Enums.DamageTypes.CRUSH: 0.75,
			Enums.DamageTypes.EXPLOSIVE: 0.0,
			Enums.DamageTypes.FIRE: 0.0,
			Enums.DamageTypes.LASER: 0.5,
			Enums.DamageTypes.MELEE: 0.75,
			Enums.DamageTypes.PLASMA: 0.25,
			Enums.DamageTypes.PRISM: 0.5,
			Enums.DamageTypes.RIFLE: 0.75,
			Enums.DamageTypes.ROCKET: 0.25,
			Enums.DamageTypes.TESLA: 0.25,
		},
		"costs": {"credits": 8},
		"build_time": 10.0,
	},
}

const DEFENCES = {}

const INFANTRY = {}

const VEHICLES = {}

const AIR = {}

const NAVY = {}
