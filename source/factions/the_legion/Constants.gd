class_name LegionConstants

const STRUCTURES = {
	"res://source/factions/the_legion/structures/CommandCenter.tscn":
	{
		"unit_name": "legion_CommandCenter",
		"description": "Central command hub. Builds structures and defences",
		"faction": Enums.Faction.LEGION,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F3,
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
		"energy_required": 0,
		"build_time": 10.0,
	},
	"res://source/factions/the_legion/structures/PowerPlant.tscn":
	{
		"unit_name": "legion_PowerPlant",
		"description": "Generates energy to power other structures",
		"faction": Enums.Faction.LEGION,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 6.0,
		"hp": 8,
		"hp_max": 8,
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
		"costs": {"credits": 4},
		"energy_provided": 5,
		"build_time": 5.0,
	},
	"res://source/factions/the_legion/structures/Barracks.tscn":
	{
		"unit_name": "legion_Barracks",
		"description": "Trains infantry units",
		"faction": Enums.Faction.LEGION,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F2,
		"sight_range": 8.0,
		"hp": 10,
		"hp_max": 10,
		"produces": [Enums.ProductionTabType.INFANTRY],
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
		"costs": {"credits": 4},
		"energy_required": 5,
		"structure_requirements":
		[
			"res://source/factions/the_legion/structures/CommandCenter.tscn",
			"res://source/factions/the_legion/structures/PowerPlant.tscn",
		],
		"build_time": 6.0,
	},
}

const DEFENCES = {}

const INFANTRY = {
	"res://source/factions/the_legion/units/Soldier.tscn":
	{
		"unit_name": "legion_Soldier",
		"description": "Light infantry armed with a laser rifle",
		"faction": Enums.Faction.LEGION,
		"production_tab_type": Enums.ProductionTabType.INFANTRY,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 8.0,
		"hp": 5,
		"hp_max": 5,
		"can_move_through_vines": true,
		"attack_damage": 1,
		"attack_type": "laser",
		"attack_interval": 0.55,
		"attack_range": 4.0,
		"can_attack_vines": true,
		"projectile_type": Enums.Projectile.LASER,
		"projectile_origin": Vector3(-0.22, 0.3, -0.1),
		"projectile_config":
		{
			"color": Color("1034a6ff"),
			"laser_count": 2,
			"laser_width": 0.03,
			"laser_duration": 0.25,
			"sound_start": preload("res://assets/sound_effects/laser-shot.mp3"),
		},
		"rotation_speed": 1,
		"attack_domains":
		[
			Enums.MovementTypes.LAND,
		],
		"armor":
		{
			Enums.DamageTypes.LASER: 0.5,
		},
		"costs": {"credits": 2},
		"build_time": 3.0,
	},
}

const VEHICLES = {}

const AIR = {}

const NAVY = {}
