const PRODUCTION_QUEUE_LIMIT = 5
const STRUCTURE_BLUEPRINTS = {
	# the Amuns
	"res://source/factions/the_amuns/structures/CommandCenter.tscn":
	"res://source/factions/the_amuns/structures/structure-geometries/CommandCenter.tscn",
	"res://source/factions/the_amuns/structures/VehicleFactory.tscn":
	"res://source/factions/the_amuns/structures/structure-geometries/VehicleFactory.tscn",
	"res://source/factions/the_amuns/structures/AircraftFactory.tscn":
	"res://source/factions/the_amuns/structures/structure-geometries/AircraftFactory.tscn",
	"res://source/factions/the_amuns/structures/AntiGroundTurret.tscn":
	"res://source/factions/the_amuns/structures/structure-geometries/AntiGroundTurret.tscn",
	"res://source/factions/the_amuns/structures/AntiAirTurret.tscn":
	"res://source/factions/the_amuns/structures/structure-geometries/AntiAirTurret.tscn",
	"res://source/factions/the_amuns/structures/Shipyard.tscn":
	"res://source/factions/the_amuns/structures/structure-geometries/Shipyard.tscn",
	# the Legion
	"res://source/factions/the_legion/structures/CommandCenter.tscn":
	"res://source/factions/the_legion/structures/structure-geometries/CommandCenter.tscn",
	"res://source/factions/the_legion/structures/PowerPlant.tscn":
	"res://source/factions/the_legion/structures/structure-geometries/PowerPlant.tscn",
	"res://source/factions/the_legion/structures/Barracks.tscn":
	"res://source/factions/the_legion/structures/structure-geometries/Barracks.tscn",
	# the Radix
	"res://source/factions/the_radix/structures/CommandCenter.tscn":
	"res://source/factions/the_radix/structures/structure-geometries/CommandCenter.tscn",
	# the Remnants
	"res://source/factions/the_remnants/structures/CommandCenter.tscn":
	"res://source/factions/the_remnants/structures/structure-geometries/CommandCenter.tscn",
}
const DEFAULT_PROPERTIES = {
	# the Amuns
	"res://source/factions/the_amuns/units/Drone.tscn":
	{
		"unit_name": "amuns_Drone",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.WATER,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 10.0,
		"hp": 6,
		"hp_max": 6,
		"movement_domains": [Enums.MovementTypes.WATER],
		"costs": {"credits": 2},
		"build_time": 3.0,
	},
	"res://source/factions/the_amuns/units/Worker.tscn":
	{
		"unit_name": "amuns_Worker",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.VEHICLE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 5.0,
		"hp": 6,
		"hp_max": 6,
		"resources_max": 500,
		"resources_gather_rate": 250,
		"costs": {"credits": 2},
		"build_time": 3.0,
	},
	"res://source/factions/the_amuns/units/Helicopter.tscn":
	{
		"unit_name": "amuns_Helicopter",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.AIR,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 8.0,
		"hp": 10,
		"hp_max": 10,
		"attack_damage": 1,
		"attack_interval": 1.0,
		"attack_range": 5.0,
		"projectile_type": Enums.Projectile.ROCKET,
		"attack_domains":
		[
			Enums.MovementTypes.LAND,
			Enums.MovementTypes.AIR,
		],
		"costs": {"credits": 1},
		"build_time": 6.0,
	},
	"res://source/factions/the_amuns/units/Tank.tscn":
	{
		"unit_name": "amuns_Tank",
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
		"projectile_type": Enums.Projectile.CANNON,
		"can_reverse_move": true,
		"rotation_speed": 1,
		"attack_domains":
		[
			Enums.MovementTypes.LAND,
		],
		"armor":
		{
			"laser": 0.5,
		},
		"costs": {"credits": 3},
		"build_time": 6.0,
	},
	"res://source/factions/the_amuns/structures/CommandCenter.tscn":
	{
		"unit_name": "amuns_CommandCenter",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F4,
		"produces": [Enums.ProductionTabType.STRUCTURE, Enums.ProductionTabType.DEFENCES],
		"structure_production_type": Enums.StructureProductionType.CONSTRUCT_ON_FIELD_AND_TRICKLE,
		"max_concurrent_structures": 1,
		"sight_range": 10.0,
		"hp": 20,
		"hp_max": 20,
		"costs": {"credits": 8},
		"build_time": 10.0,
	},
	"res://source/factions/the_amuns/structures/VehicleFactory.tscn":
	{
		"unit_name": "amuns_VehicleFactory",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"produces": [Enums.ProductionTabType.VEHICLE],
		"sight_range": 8.0,
		"hp": 16,
		"hp_max": 16,
		"costs": {"credits": 6},
		"build_time": 8.0,
	},
	"res://source/factions/the_amuns/structures/AircraftFactory.tscn":
	{
		"unit_name": "amuns_AircraftFactory",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F2,
		"produces": [Enums.ProductionTabType.AIR],
		"sight_range": 8.0,
		"hp": 16,
		"hp_max": 16,
		"costs": {"credits": 4},
		"build_time": 8.0,
	},
	"res://source/factions/the_amuns/structures/AntiGroundTurret.tscn":
	{
		"unit_name": "amuns_AntiGroundTurret",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.DEFENCES,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 8.0,
		"hp": 8,
		"hp_max": 8,
		"attack_damage": 2,
		"attack_interval": 1.0,
		"attack_range": 8.0,
		"projectile_type": Enums.Projectile.CANNON,
		"attack_domains":
		[
			Enums.MovementTypes.LAND,
		],
		"costs": {"credits": 2},
		"build_time": 5.0,
	},
	"res://source/factions/the_amuns/structures/AntiAirTurret.tscn":
	{
		"unit_name": "amuns_AntiAirTurret",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.DEFENCES,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F2,
		"sight_range": 8.0,
		"hp": 8,
		"hp_max": 8,
		"attack_damage": 2,
		"attack_interval": 0.75,
		"attack_range": 8.0,
		"projectile_type": Enums.Projectile.ROCKET,
		"attack_domains":
		[
			Enums.MovementTypes.AIR,
		],
		"costs": {"credits": 2},
		"build_time": 5.0,
	},
	"res://source/factions/the_amuns/structures/Shipyard.tscn":
	{
		"unit_name": "amuns_Shipyard",
		"faction": Enums.Faction.AMUNS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F3,
		"produces": [Enums.ProductionTabType.WATER],
		"sight_range": 8.0,
		"hp": 16,
		"hp_max": 16,
		"costs": {"credits": 5},
		"build_time": 8.0,
	},
	# the Legion
	"res://source/factions/the_legion/structures/CommandCenter.tscn":
	{
		"unit_name": "legion_CommandCenter",
		"faction": Enums.Faction.LEGION,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F3,
		"produces": [Enums.ProductionTabType.STRUCTURE, Enums.ProductionTabType.DEFENCES],
		"structure_production_type": Enums.StructureProductionType.CONSTRUCT_OFF_FIELD_AND_TRICKLE,
		"max_concurrent_structures": 1,
		"sight_range": 10.0,
		"hp": 20,
		"hp_max": 20,
		"costs": {"credits": 8},
		"energy_required": 0,
		"build_time": 10.0,
	},
	"res://source/factions/the_legion/structures/PowerPlant.tscn":
	{
		"unit_name": "legion_PowerPlant",
		"faction": Enums.Faction.LEGION,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 6.0,
		"hp": 8,
		"hp_max": 8,
		"costs": {"credits": 4},
		"energy_provided": 5,
		"build_time": 5.0,
	},
	"res://source/factions/the_legion/structures/Barracks.tscn":
	{
		"unit_name": "legion_Barracks",
		"faction": Enums.Faction.LEGION,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F2,
		"sight_range": 8.0,
		"hp": 10,
		"hp_max": 10,
		"produces": [Enums.ProductionTabType.INFANTRY],
		"costs": {"credits": 4},
		"energy_required": 5,
		"structure_requirements":
		[
			"res://source/factions/the_legion/structures/CommandCenter.tscn",
			"res://source/factions/the_legion/structures/PowerPlant.tscn",
		],
		"build_time": 6.0,
	},
	"res://source/factions/the_legion/units/Worker.tscn":
	{
		"unit_name": "legion_Worker",
		"faction": Enums.Faction.LEGION,
		"production_tab_type": Enums.ProductionTabType.VEHICLE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 5.0,
		"hp": 6,
		"hp_max": 6,
		"resources_max": 500,
		"resources_gather_rate": 250,
		"costs": {"credits": 2},
		"build_time": 3.0,
	},
	"res://source/factions/the_legion/units/Soldier.tscn":
	{
		"unit_name": "legion_Soldier",
		"faction": Enums.Faction.LEGION,
		"production_tab_type": Enums.ProductionTabType.INFANTRY,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 8.0,
		"hp": 5,
		"hp_max": 5,
		"attack_damage": 1,
		"attack_type": "laser",
		"attack_interval": 0.55,
		"attack_range": 4.0,
		"projectile_type": Enums.Projectile.LASER,
		"projectile_origin": Vector3(0.0, 0.35, -0.4),
		"projectile_config":
		{
			"color": Color("1034a6ff"),
			"laser_count": 2,
			"laser_width": 0.03,
			"laser_duration": 0.25,
		},
		"rotation_speed": 1,
		"attack_domains":
		[
			Enums.MovementTypes.LAND,
		],
		"armor":
		{
			"laser": 0.5,
		},
		"costs": {"credits": 2},
		"build_time": 3.0,
	},
	# the Radix
	"res://source/factions/the_radix/structures/CommandCenter.tscn":
	{
		"unit_name": "radix_CommandCenter",
		"faction": Enums.Faction.RADIX,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"produces": [Enums.ProductionTabType.STRUCTURE, Enums.ProductionTabType.DEFENCES],
		"max_concurrent_structures": 1,
		"sight_range": 10.0,
		"hp": 20,
		"hp_max": 20,
		"costs": {"credits": 8},
		"build_time": 10.0,
	},
	"res://source/factions/the_radix/units/Worker.tscn":
	{
		"unit_name": "radix_Worker",
		"faction": Enums.Faction.RADIX,
		"production_tab_type": Enums.ProductionTabType.VEHICLE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 5.0,
		"hp": 6,
		"hp_max": 6,
		"resources_max": 500,
		"resources_gather_rate": 250,
		"costs": {"credits": 2},
		"build_time": 3.0,
	},
	# the Remnants
	"res://source/factions/the_remnants/structures/CommandCenter.tscn":
	{
		"unit_name": "remnants_CommandCenter",
		"faction": Enums.Faction.REMNANTS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"produces": [Enums.ProductionTabType.STRUCTURE, Enums.ProductionTabType.DEFENCES],
		"max_concurrent_structures": 1,
		"sight_range": 10.0,
		"hp": 20,
		"hp_max": 20,
		"costs": {"credits": 8},
		"build_time": 10.0,
	},
	"res://source/factions/the_remnants/units/Worker.tscn":
	{
		"unit_name": "remnants_Worker",
		"faction": Enums.Faction.REMNANTS,
		"production_tab_type": Enums.ProductionTabType.STRUCTURE,
		"production_tab_grid_slot": Enums.ProductionTabGridSlots.F1,
		"sight_range": 5.0,
		"hp": 6,
		"hp_max": 6,
		"resources_max": 500,
		"resources_gather_rate": 250,
		"costs": {"credits": 2},
		"build_time": 3.0,
	},
}

const ADHERENCE_MARGIN_M = 0.3  # TODO: try lowering while fixing a 'push' problem
const NEW_RESOURCE_SEARCH_RADIUS_M = 30
const MOVING_UNIT_RADIUS_MAX_M = 1.0
const EMPTY_SPACE_RADIUS_SURROUNDING_STRUCTURE_M = MOVING_UNIT_RADIUS_MAX_M * 2.5
const STRUCTURE_CONSTRUCTING_SPEED = 0.3  # progress [0.0..1.0] per second
