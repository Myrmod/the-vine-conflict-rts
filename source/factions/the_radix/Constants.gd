class_name RadixConstants

const SOUND_ROCKET_START = preload("res://assets/sound_effects/rocket1_start.mp3")
const SOUND_ROCKET_END = preload("res://assets/sound_effects/rocket1_end.mp3")

const STRUCTURES = {
	Enums.SceneId.RADIX_HEART:
	{
		"scene": "res://source/factions/the_radix/structures/Heart.tscn",
		"unit_name": "Heart",
		"description": "Central command hub. Builds structures and defences",
		"faction": Enums.Faction.RADIX,
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
		"spreads_vines": true,
		"costs": {"credits": 8},
		"build_time": 10.0,
	},
}

const DEFENCES = {}

const INFANTRY = {}

const VEHICLES = {}

const AIR = {}

const NAVY = {}

const CREEP_SPREAD_INTERVAL_TICKS: int = 10
const CREEP_SPREAD_TILES_PER_INTERVAL: int = 1
## Maximum vitality health a creep cell can hold.
## A cell's health is reset to this value by its owning source each spread tick.
const CREEP_CELL_MAX_HEALTH: int = 20
## How many game ticks between each global decay pass.
const CREEP_DECAY_INTERVAL_TICKS: int = 10
## Health lost per cell per decay pass when not vitalized by any source.
## A dead source's cells will disappear after MAX_HEALTH/DECAY_AMOUNT decay passes.
const CREEP_DECAY_AMOUNT: int = 1
const CREEP_REGEN_INTERVAL_TICKS: int = 10
const CREEP_REGEN_HP_PER_INTERVAL: int = 1
