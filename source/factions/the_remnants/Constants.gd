class_name RemnantConstants

const SOUND_ROCKET_START = preload("res://assets/sound_effects/rocket1_start.mp3")
const SOUND_ROCKET_END = preload("res://assets/sound_effects/rocket1_end.mp3")

const STRUCTURES = {
	Enums.SceneId.REMNANTS_COMMAND_CENTER:
	{
		"scene": "res://source/factions/the_remnants/structures/CommandCenter.tscn",
		"unit_name": "remnants_CommandCenter",
		"description": "Central command hub. Builds structures and defences",
		"faction": Enums.Faction.REMNANTS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"produces": [Enums.ProductionTabType.STRUCTURE, Enums.ProductionTabType.DEFENCES],
		"structure_production_type": Enums.StructureProductionType.CONSTRUCT_OFF_FIELD_AND_TRICKLE,
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
	Enums.SceneId.REMNANTS_CASERN:
	{
		"scene": "res://source/factions/the_remnants/structures/Casern.tscn",
		"unit_name": "Casern",
		"description": "Trains Remnants infantry units",
		"faction": Enums.Faction.REMNANTS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F2,
		"produces": [Enums.ProductionTabType.INFANTRY],
		"sight_range": 8.0,
		"hp": 10,
		"hp_max": 10,
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
		"costs": {"credits": 600},
		"energy_required": 25,
		"structure_requirements":
		[
			Enums.SceneId.REMNANTS_COMMAND_CENTER,
		],
		"build_time": 6.0,
	},
	Enums.SceneId.REMNANTS_FACTORY:
	{
		"scene": "res://source/factions/the_remnants/structures/Factory.tscn",
		"unit_name": "Factory",
		"description": "Produces Remnants vehicles",
		"faction": Enums.Faction.REMNANTS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F3,
		"produces": [Enums.ProductionTabType.VEHICLE],
		"sight_range": 8.0,
		"hp": 12,
		"hp_max": 12,
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
		"costs": {"credits": 2000},
		"energy_required": 50,
		"structure_requirements":
		[
			Enums.SceneId.REMNANTS_COMMAND_CENTER,
		],
		"build_time": 20.0,
	},
	Enums.SceneId.REMNANTS_DRONE_TOWER:
	{
		"scene": "res://source/factions/the_remnants/structures/DroneTower.tscn",
		"unit_name": "Drone Tower",
		"description": "Produces Remnants air units",
		"faction": Enums.Faction.REMNANTS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F4,
		"produces": [Enums.ProductionTabType.AIR],
		"sight_range": 8.0,
		"hp": 12,
		"hp_max": 12,
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
		"costs": {"credits": 2000},
		"energy_required": 50,
		"structure_requirements":
		[
			Enums.SceneId.REMNANTS_COMMAND_CENTER,
		],
		"build_time": 20.0,
	},
}

const DEFENCES = {}

const INFANTRY = {
	Enums.SceneId.REMNANTS_INCINERATOR:
	{
		"scene": "res://source/factions/the_remnants/units/Incinerator.tscn",
		"unit_name": "Incinerator",
		"description": "Infantry burn-harvester that destroys vines in place.",
		"faction": Enums.Faction.REMNANTS,
		"production_tab_type": Enums.ProductionTabType.INFANTRY,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 8.0,
		"hp": 80,
		"hp_max": 80,
		"resources_max": 250,
		"resources_gather_rate": 125,
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
		"costs": {"credits": 2},
		"build_time": 3.0,
	},
}

const VEHICLES = {
	Enums.SceneId.REMNANTS_FLAME_TANK:
	{
		"scene": "res://source/factions/the_remnants/units/FlameTank.tscn",
		"unit_name": "Flame Tank",
		"description": "Vehicle burn-harvester that destroys vines in place.",
		"faction": Enums.Faction.REMNANTS,
		"production_tab_type": Enums.ProductionTabType.VEHICLE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 8.0,
		"hp": 1000,
		"hp_max": 1000,
		"resources_max": 500,
		"resources_gather_rate": 250,
		"can_move_through_vines": true,
		"can_reverse_move": true,
		"armor":
		{
			Enums.DamageTypes.CANNON: 0.5,
			Enums.DamageTypes.CORROSIVE: 0.5,
			Enums.DamageTypes.CRUSH: 0.5,
			Enums.DamageTypes.EXPLOSIVE: 0.5,
			Enums.DamageTypes.FIRE: 0.5,
			Enums.DamageTypes.LASER: 0.5,
			Enums.DamageTypes.MELEE: 0.5,
			Enums.DamageTypes.PLASMA: 0.5,
			Enums.DamageTypes.PRISM: 0.5,
			Enums.DamageTypes.RIFLE: 0.5,
			Enums.DamageTypes.ROCKET: 0.5,
			Enums.DamageTypes.TESLA: 0.5,
		},
		"costs": {"credits": 3},
		"build_time": 6.0,
	},
}

const AIR = {}

const NAVY = {}
