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
		"produces":
		[
			Enums.ProductionTabType.STRUCTURE,
			Enums.ProductionTabType.DEFENCES,
			Enums.ProductionTabType.INFANTRY,
		],
		"max_concurrent_structures": 99,
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
	Enums.SceneId.RADIX_BROOD_NEST:
	{
		"scene": "res://source/factions/the_radix/structures/BroodNest.tscn",
		"unit_name": "Brood Nest",
		"description": "Tier 1 infantry nursery seeded into place by a Seedling.",
		"faction": Enums.Faction.RADIX,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F2,
		"produces": [Enums.ProductionTabType.INFANTRY],
		"requires_seedling_to_start": true,
		"sight_range": 8.0,
		"hp": 12,
		"hp_max": 12,
		"armor":
		{
			Enums.DamageTypes.CANNON: 0.0,
			Enums.DamageTypes.CORROSIVE: 0.0,
			Enums.DamageTypes.CRUSH: 0.25,
			Enums.DamageTypes.EXPLOSIVE: 0.0,
			Enums.DamageTypes.FIRE: 0.0,
			Enums.DamageTypes.LASER: 0.0,
			Enums.DamageTypes.MELEE: 0.25,
			Enums.DamageTypes.PLASMA: 0.0,
			Enums.DamageTypes.PRISM: 0.0,
			Enums.DamageTypes.RIFLE: 0.25,
			Enums.DamageTypes.ROCKET: 0.0,
			Enums.DamageTypes.TESLA: 0.0,
		},
		"costs": {"credits": 600},
		"build_time": 6.0,
	},
	Enums.SceneId.RADIX_THORN_FORGE:
	{
		"scene": "res://source/factions/the_radix/structures/ThornForge.tscn",
		"unit_name": "Thorn Forge",
		"description": "Tier 1 vehicle foundry seeded into place by a Seedling.",
		"faction": Enums.Faction.RADIX,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F3,
		"produces": [Enums.ProductionTabType.VEHICLE],
		"requires_seedling_to_start": true,
		"sight_range": 8.0,
		"hp": 18,
		"hp_max": 18,
		"armor":
		{
			Enums.DamageTypes.CANNON: 0.25,
			Enums.DamageTypes.CORROSIVE: 0.0,
			Enums.DamageTypes.CRUSH: 0.35,
			Enums.DamageTypes.EXPLOSIVE: 0.0,
			Enums.DamageTypes.FIRE: 0.0,
			Enums.DamageTypes.LASER: 0.15,
			Enums.DamageTypes.MELEE: 0.25,
			Enums.DamageTypes.PLASMA: 0.15,
			Enums.DamageTypes.PRISM: 0.15,
			Enums.DamageTypes.RIFLE: 0.35,
			Enums.DamageTypes.ROCKET: 0.15,
			Enums.DamageTypes.TESLA: 0.15,
		},
		"costs": {"credits": 2000},
		"build_time": 20.0,
	},
	Enums.SceneId.RADIX_SKY_BLOOM:
	{
		"scene": "res://source/factions/the_radix/structures/SkyBloom.tscn",
		"unit_name": "Sky Bloom",
		"description": "Tier 1 aerial cradle seeded into place by a Seedling.",
		"faction": Enums.Faction.RADIX,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F4,
		"produces": [Enums.ProductionTabType.AIR],
		"requires_seedling_to_start": true,
		"sight_range": 8.0,
		"hp": 16,
		"hp_max": 16,
		"armor":
		{
			Enums.DamageTypes.CANNON: 0.15,
			Enums.DamageTypes.CORROSIVE: 0.0,
			Enums.DamageTypes.CRUSH: 0.25,
			Enums.DamageTypes.EXPLOSIVE: 0.0,
			Enums.DamageTypes.FIRE: 0.0,
			Enums.DamageTypes.LASER: 0.15,
			Enums.DamageTypes.MELEE: 0.25,
			Enums.DamageTypes.PLASMA: 0.15,
			Enums.DamageTypes.PRISM: 0.15,
			Enums.DamageTypes.RIFLE: 0.25,
			Enums.DamageTypes.ROCKET: 0.15,
			Enums.DamageTypes.TESLA: 0.15,
		},
		"costs": {"credits": 2000},
		"build_time": 20.0,
	},
	Enums.SceneId.RADIX_LINKER:
	{
		"scene": "res://source/factions/the_radix/structures/Linker.tscn",
		"unit_name": "Linker",
		"description":
		"Passive bio-link structure that siphons income from nearby resource tiles without consuming them.",
		"faction": Enums.Faction.RADIX,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F5,
		"requires_seedling_to_start": true,
		"sight_range": 8.0,
		"hp": 14,
		"hp_max": 14,
		"armor":
		{
			Enums.DamageTypes.CANNON: 0.1,
			Enums.DamageTypes.CORROSIVE: 0.0,
			Enums.DamageTypes.CRUSH: 0.25,
			Enums.DamageTypes.EXPLOSIVE: 0.0,
			Enums.DamageTypes.FIRE: 0.0,
			Enums.DamageTypes.LASER: 0.1,
			Enums.DamageTypes.MELEE: 0.25,
			Enums.DamageTypes.PLASMA: 0.1,
			Enums.DamageTypes.PRISM: 0.1,
			Enums.DamageTypes.RIFLE: 0.25,
			Enums.DamageTypes.ROCKET: 0.1,
			Enums.DamageTypes.TESLA: 0.1,
		},
		"costs": {"credits": 900},
		"build_time": 10.0,
	},
	Enums.SceneId.RADIX_SAPLING:
	{
		"scene": "res://source/factions/the_radix/structures/Sapling.tscn",
		"unit_name": "Sapling",
		"description":
		"Rooted Seedling. Spreads creep in a small radius. Created by the Seedling 'spread' ability.",
		"faction": Enums.Faction.RADIX,
		# Sapling is not produced via a production tab; it is spawned by the spread ability.
		"sight_range": 5.0,
		"hp": 40,
		"hp_max": 40,
		"armor":
		{
			Enums.DamageTypes.CANNON: 0.0,
			Enums.DamageTypes.CORROSIVE: 0.0,
			Enums.DamageTypes.CRUSH: 0.1,
			Enums.DamageTypes.EXPLOSIVE: 0.0,
			Enums.DamageTypes.FIRE: 0.0,
			Enums.DamageTypes.LASER: 0.0,
			Enums.DamageTypes.MELEE: 0.1,
			Enums.DamageTypes.PLASMA: 0.0,
			Enums.DamageTypes.PRISM: 0.0,
			Enums.DamageTypes.RIFLE: 0.1,
			Enums.DamageTypes.ROCKET: 0.0,
			Enums.DamageTypes.TESLA: 0.0,
		},
		"costs": {"credits": 0},
		"build_time": 0.5,
	},
}

const DEFENCES = {}

const INFANTRY = {
	Enums.SceneId.RADIX_SEEDLING:
	{
		"scene": "res://source/factions/the_radix/units/Seedling.tscn",
		"unit_name": "Seedling",
		"description":
		"A fragile sprout creature. Unarmed support unit for scouting, creep spread, and construction.",
		"faction": Enums.Faction.RADIX,
		"production_tab_type": Enums.ProductionTabType.INFANTRY,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 6.0,
		"hp": 80,
		"hp_max": 80,
		"can_move_through_vines": true,
		"armor":
		{
			Enums.DamageTypes.CANNON: 0.0,
			Enums.DamageTypes.CORROSIVE: 0.0,
			Enums.DamageTypes.CRUSH: 0.0,
			Enums.DamageTypes.EXPLOSIVE: 0.0,
			Enums.DamageTypes.FIRE: 0.0,
			Enums.DamageTypes.LASER: 0.0,
			Enums.DamageTypes.MELEE: 0.0,
			Enums.DamageTypes.PLASMA: 0.0,
			Enums.DamageTypes.PRISM: 0.0,
			Enums.DamageTypes.RIFLE: 0.0,
			Enums.DamageTypes.ROCKET: 0.0,
			Enums.DamageTypes.TESLA: 0.0,
		},
		"costs": {"credits": 1},
		"build_time": 2.5,
	},
}

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
## How many ticks between off-creep damage checks for Radix structures.
const CREEP_OFF_CREEP_DAMAGE_INTERVAL_TICKS: int = 10
## Fraction of hp_max lost per interval when a structure is not on creep.
const CREEP_OFF_CREEP_DAMAGE_PERCENT: float = 0.005

## Ticks the Seedling spends playing the `build` animation before consuming
## itself into a structure or before transitioning to the `grow` phase.
const SEEDLING_BUILD_ANIM_TICKS: int = 10
## Ticks the Seedling spends playing the `grow` animation before transforming
## into a Sapling (only used by the spread ability).
const SEEDLING_GROW_ANIM_TICKS: int = 15
