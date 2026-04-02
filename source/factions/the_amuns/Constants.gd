class_name AmunsConstants

const SOUND_ROCKET_START = preload("res://assets/sound_effects/rocket1_start.mp3")
const SOUND_ROCKET_END = preload("res://assets/sound_effects/rocket1_end.mp3")

const STRUCTURES = {
	Enums.SceneId.AMUNS_BEKHENET:
	{
		"scene": "res://source/factions/the_amuns/structures/Bekhenet.tscn",
		"unit_name": "Nemet",
		"description": "Central command hub. Builds structures and defences",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F7,
		"produces": [Enums.ProductionTabType.STRUCTURE, Enums.ProductionTabType.DEFENCES],
		"structure_production_type": Enums.StructureProductionType.CONSTRUCT_ON_FIELD_AND_TRICKLE,
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
		"costs": {"credits": 2500},
		"build_time": 25.0,
	},
	Enums.SceneId.AMUNS_NAUCRATIS:
	{
		"scene": "res://source/factions/the_amuns/structures/Naucratis.tscn",
		"unit_name": "Naucratis",
		"description": "Produces ground vehicles",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F5,
		"produces": [Enums.ProductionTabType.VEHICLE],
		"sight_range": 8.0,
		"hp": 16,
		"hp_max": 16,
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
		"build_time": 20.0,
		"structure_requirements":
		[
			Enums.SceneId.AMUNS_BEKHENET,
			Enums.SceneId.AMUNS_KISLAGH, # or Nemet
			Enums.SceneId.AMUNS_NEMET, # or Kislagh
		],
	},
	Enums.SceneId.AMUNS_NEMET:
	{
		"scene": "res://source/factions/the_amuns/structures/Nemet.tscn",
		"unit_name": "Nemet",
		"description": "Produces aircraft",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F4,
		"produces": [Enums.ProductionTabType.AIR],
		"sight_range": 8.0,
		"hp": 16,
		"hp_max": 16,
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
		"build_time": 20.0,
		"structure_requirements":
		[
			Enums.SceneId.AMUNS_BEKHENET,
		],
	},
	Enums.SceneId.AMUNS_MNI:
	{
		"scene": "res://source/factions/the_amuns/structures/Mni.tscn",
		"unit_name": "Mni",
		"description": "Produces naval units",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F6,
		"produces": [Enums.ProductionTabType.WATER],
		"sight_range": 8.0,
		"hp": 16,
		"hp_max": 16,
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
		"costs": {"credits": 1500},
		"build_time": 15.0,
		"structure_requirements":
		[
			Enums.SceneId.AMUNS_BEKHENET,
			Enums.SceneId.AMUNS_KISLAGH, # or Nemet
			Enums.SceneId.AMUNS_NEMET, # or Kislagh
		],
	},
	Enums.SceneId.AMUNS_KISLAGH:
	{
		"scene": "res://source/factions/the_amuns/structures/Kislagh.tscn",
		"unit_name": "Kislagh",
		"description": "Trains infantry units",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F3,
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
		"costs": {"credits": 4},
		"energy_required": 5,
		"structure_requirements":
		[
			Enums.SceneId.AMUNS_BEKHENET,
		],
		"produces": [Enums.ProductionTabType.INFANTRY],
		"build_time": 6.0,
	},
	Enums.SceneId.AMUNS_PYLON:
	{
		"scene": "res://source/factions/the_amuns/structures/Pylon.tscn",
		"unit_name": "Pylon",
		"description": "Transforms vines into resources for the Amuns",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
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
		"costs": {"credits": 1000},
		"energy_required": 0,
		"structure_requirements":
		[
			Enums.SceneId.AMUNS_BEKHENET,
		],
		"build_time": 10.0,
	},
	Enums.SceneId.AMUNS_ALTAR:
	{
		"scene": "res://source/factions/the_amuns/structures/Altar.tscn",
		"unit_name": "Altar",
		"description": "Harvests vines around it",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F2,
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
		"costs": {"credits": 1500},
		"energy_required": 0,
		"structure_requirements":
		[
			Enums.SceneId.AMUNS_BEKHENET,
			Enums.SceneId.AMUNS_PYLON,
		],
		"build_time": 15.0,
	},
}

const DEFENCES = {
	Enums.SceneId.AMUNS_WALL_PILLAR:
	{
		"scene": "res://source/factions/the_amuns/structures/WallPillar.tscn",
		"unit_name": "amuns_WallPillar",
		"description": "Defensive wall",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.DEFENCES,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 4.0,
		"hp": 100,
		"hp_max": 100,
		"armor":
		{
			Enums.DamageTypes.CANNON: 0.5,
			Enums.DamageTypes.CORROSIVE: 0.5,
			Enums.DamageTypes.CRUSH: 0.5,
			Enums.DamageTypes.EXPLOSIVE: 0.5,
			Enums.DamageTypes.FIRE: 0.0,
			Enums.DamageTypes.LASER: 0.5,
			Enums.DamageTypes.MELEE: 0.5,
			Enums.DamageTypes.PLASMA: 0.5,
			Enums.DamageTypes.PRISM: 0.5,
			Enums.DamageTypes.RIFLE: 0.5,
			Enums.DamageTypes.ROCKET: 0.5,
			Enums.DamageTypes.TESLA: 0.5,
		},
		"costs": {"credits": 50},
		"build_time": 5.0,
		"structure_requirements":
		[
			Enums.SceneId.AMUNS_BEKHENET,
		],
		## wall specific settings
		"connection_length": 5,
	},
	Enums.SceneId.AMUNS_ANTI_GROUND_TURRET:
	{
		"scene": "res://source/factions/the_amuns/structures/AntiGroundTurret.tscn",
		"unit_name": "amuns_AntiGroundTurret",
		"description": "Defensive turret that fires cannons at ground targets",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.DEFENCES,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F3,
		"sight_range": 8.0,
		"hp": 8,
		"hp_max": 8,
		"attack_damage": 2,
		"attack_type": "cannon",
		"attack_interval": 1.0,
		"attack_range": 8.0,
		"can_attack_vines": true,
		"projectile_type": Enums.Projectile.CANNON,
		"projectile_config":
		{
			"sound_start": SOUND_ROCKET_START,
			"sound_end": SOUND_ROCKET_END,
		},
		"attack_domains":
		[
			Enums.MovementTypes.LAND,
		],
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
		"costs": {"credits": 2},
		"build_time": 5.0,
		"structure_requirements":
		[
			Enums.SceneId.AMUNS_BEKHENET,
		],
	},
	Enums.SceneId.AMUNS_ANTI_AIR_TURRET:
	{
		"scene": "res://source/factions/the_amuns/structures/AntiAirTurret.tscn",
		"unit_name": "amuns_AntiAirTurret",
		"description": "Defensive turret that fires rockets at air targets",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.DEFENCES,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F4,
		"sight_range": 8.0,
		"hp": 8,
		"hp_max": 8,
		"attack_damage": 2,
		"attack_type": "rocket",
		"attack_interval": 0.75,
		"attack_range": 8.0,
		"can_attack_vines": true,
		"projectile_type": Enums.Projectile.ROCKET,
		"projectile_config":
		{
			"sound_start": SOUND_ROCKET_START,
			"sound_end": SOUND_ROCKET_END,
		},
		"attack_domains":
		[
			Enums.MovementTypes.AIR,
		],
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
		"costs": {"credits": 2},
		"build_time": 5.0,
		"structure_requirements":
		[
			Enums.SceneId.AMUNS_BEKHENET,
		],
	},
}

const INFANTRY = {
	Enums.SceneId.AMUNS_SOLDIER:
	{
		"scene": "res://source/factions/the_amuns/units/Soldier.tscn",
		"unit_name": "amuns_Soldier",
		"description": "Light infantry armed with a laser rifle",
		"faction": Enums.Faction.AMUNS,
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

const VEHICLES = {
	Enums.SceneId.AMUNS_WORKER:
	{
		"scene": "res://source/factions/the_amuns/units/Worker.tscn",
		"unit_name": "amuns_Worker",
		"description": "Unarmed construction and resource gathering vehicle",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.VEHICLE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 5.0,
		"hp": 6,
		"hp_max": 6,
		"resources_max": 500,
		"resources_gather_rate": 250,
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
	Enums.SceneId.AMUNS_TANK:
	{
		"scene": "res://source/factions/the_amuns/units/Tank.tscn",
		"unit_name": "amuns_Tank",
		"description": "Heavy armored ground vehicle with an autocannon",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.VEHICLE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F2,
		"sight_range": 8.0,
		"hp": 10,
		"hp_max": 10,
		"attack_damage": 2,
		"attack_type": "cannon",
		"attack_interval": 0.75,
		"attack_range": 5.0,
		"can_attack_vines": true,
		"projectile_type": Enums.Projectile.CANNON,
		"projectile_config":
		{
			"sound_start": preload("res://assets/sound_effects/autocannon-20mm.mp3"),
		},
		"can_reverse_move": true,
		"rotation_speed": 1,
		"attack_domains":
		[
			Enums.MovementTypes.LAND,
		],
		"armor":
		{
			Enums.DamageTypes.LASER: 0.5,
			Enums.DamageTypes.CANNON: 0.5,
			Enums.DamageTypes.CORROSIVE: 0.5,
			Enums.DamageTypes.CRUSH: 0.5,
			Enums.DamageTypes.EXPLOSIVE: 0.5,
			Enums.DamageTypes.FIRE: 0.5,
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

const AIR = {
	Enums.SceneId.AMUNS_HELICOPTER:
	{
		"scene": "res://source/factions/the_amuns/units/Helicopter.tscn",
		"unit_name": "amuns_Helicopter",
		"description": "Versatile attack helicopter armed with rockets",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.AIR,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 8.0,
		"hp": 10,
		"hp_max": 10,
		"attack_damage": 1,
		"attack_type": "rocket",
		"attack_interval": 1.0,
		"attack_range": 5.0,
		"can_attack_vines": true,
		"projectile_type": Enums.Projectile.ROCKET,
		"projectile_config":
		{
			"sound_start": SOUND_ROCKET_START,
			"sound_end": SOUND_ROCKET_END,
		},
		"attack_domains":
		[
			Enums.MovementTypes.LAND,
			Enums.MovementTypes.AIR,
		],
		"armor":
		{
			Enums.DamageTypes.RIFLE: 0.25,
		},
		"costs": {"credits": 1},
		"build_time": 6.0,
	},
}

const NAVY = {
	Enums.SceneId.AMUNS_DRONE:
	{
		"scene": "res://source/factions/the_amuns/units/Drone.tscn",
		"unit_name": "amuns_Drone",
		"description": "Light aquatic scout drone",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.WATER,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 10.0,
		"hp": 6,
		"hp_max": 6,
		"movement_domains": [Enums.MovementTypes.WATER],
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
