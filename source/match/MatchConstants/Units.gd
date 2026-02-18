class_name UnitConstants

const PRODUCTION_QUEUE_LIMIT = 5
const STRUCTURE_BLUEPRINTS = {
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
}
const DEFAULT_PROPERTIES = {
	"res://source/factions/the_amuns/units/Drone.tscn":
	{
		"sight_range": 10.0,
		"hp": 6,
		"hp_max": 6,
		"costs": {"resource_a": 2},
		"build_time": 3.0,
	},
	"res://source/factions/the_amuns/units/Worker.tscn":
	{
		"sight_range": 5.0,
		"hp": 6,
		"hp_max": 6,
		"resources_max": 2,
		"costs": {"resource_a": 2},
		"build_time": 3.0,
	},
	"res://source/factions/the_amuns/units/Helicopter.tscn":
	{
		"sight_range": 8.0,
		"hp": 10,
		"hp_max": 10,
		"attack_damage": 1,
		"attack_interval": 1.0,
		"attack_range": 5.0,
		"attack_domains":
		[
			NavigationConstants.Domain.TERRAIN,
			NavigationConstants.Domain.AIR,
		],
		"costs": {"resource_a": 1},
		"build_time": 6.0,
	},
	"res://source/factions/the_amuns/units/Tank.tscn":
	{
		"sight_range": 8.0,
		"hp": 10,
		"hp_max": 10,
		"attack_damage": 2,
		"attack_interval": 0.75,
		"attack_range": 5.0,
		"attack_domains":
		[
			NavigationConstants.Domain.TERRAIN,
		],
		"costs": {"resource_a": 3},
		"build_time": 6.0,
	},
	"res://source/factions/the_amuns/structures/CommandCenter.tscn":
	{
		"sight_range": 10.0,
		"hp": 20,
		"hp_max": 20,
		"costs": {"resource_a": 8},
		"build_time": 10.0,
	},
	"res://source/factions/the_amuns/structures/VehicleFactory.tscn":
	{
		"sight_range": 8.0,
		"hp": 16,
		"hp_max": 16,
		"costs": {"resource_a": 6},
		"build_time": 8.0,
	},
	"res://source/factions/the_amuns/structures/AircraftFactory.tscn":
	{
		"sight_range": 8.0,
		"hp": 16,
		"hp_max": 16,
		"costs": {"resource_a": 4},
		"build_time": 8.0,
	},
	"res://source/factions/the_amuns/structures/AntiGroundTurret.tscn":
	{
		"sight_range": 8.0,
		"hp": 8,
		"hp_max": 8,
		"attack_damage": 2,
		"attack_interval": 1.0,
		"attack_range": 8.0,
		"attack_domains":
		[
			NavigationConstants.Domain.TERRAIN,
		],
		"costs": {"resource_a": 2},
		"build_time": 5.0,
	},
	"res://source/factions/the_amuns/structures/AntiAirTurret.tscn":
	{
		"sight_range": 8.0,
		"hp": 8,
		"hp_max": 8,
		"attack_damage": 2,
		"attack_interval": 0.75,
		"attack_range": 8.0,
		"attack_domains":
		[
			NavigationConstants.Domain.AIR,
		],
		"costs": {"resource_a": 2},
		"build_time": 5.0,
	},
}
const PROJECTILES = {
	"res://source/factions/the_amuns/units/Helicopter.tscn":
	"res://source/match/units/projectiles/Rocket.tscn",
	"res://source/factions/the_amuns/units/Tank.tscn":
	"res://source/match/units/projectiles/CannonShell.tscn",
	"res://source/factions/the_amuns/structures/AntiGroundTurret.tscn":
	"res://source/match/units/projectiles/CannonShell.tscn",
	"res://source/factions/the_amuns/structures/AntiAirTurret.tscn":
	"res://source/match/units/projectiles/Rocket.tscn"
}
const ADHERENCE_MARGIN_M = 0.3  # TODO: try lowering while fixing a 'push' problem
const NEW_RESOURCE_SEARCH_RADIUS_M = 30
const MOVING_UNIT_RADIUS_MAX_M = 1.0
const EMPTY_SPACE_RADIUS_SURROUNDING_STRUCTURE_M = MOVING_UNIT_RADIUS_MAX_M * 2.5
const STRUCTURE_CONSTRUCTING_SPEED = 0.3  # progress [0.0..1.0] per second
