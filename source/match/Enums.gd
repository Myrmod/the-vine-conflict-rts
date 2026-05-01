class_name Enums

# COMMAND TYPES: Every game-changing action that can occur in a match.
#
# ALL state mutations (human input, AI decisions, structure placement, production, etc.)
# MUST flow through CommandBus.push_command() as one of these types. Match._execute_command()
# is the SINGLE POINT OF AUTHORITY that applies them. This guarantees:
#   - Deterministic replay: same commands in same tick order = identical game
#   - Future multiplayer: all clients execute the same command stream
#   - Auditability: every game state change is traceable to a command
#
# NO game state (unit actions, resources, spawns) may be modified outside this pipeline.
# If you need a new kind of action, add an enum here and handle it in Match._execute_command().
enum CommandType {
	MOVE,  # Move unit(s) to terrain position
	MOVING_TO_UNIT,  # Move unit to another unit's position
	FOLLOWING,  # Follow a unit continuously
	COLLECTING_RESOURCES_SEQUENTIALLY,  # Worker harvests from resource node
	AUTO_ATTACKING,  # Attack a specific enemy unit
	CONSTRUCTING,  # Assign worker(s) to construct a structure
	ENTITY_IS_QUEUED,  # Queue unit production at a structure
	STRUCTURE_PLACED,  # Place a new structure on the map (deducts resources)
	ENTITY_PRODUCTION_CANCELED,  # Cancel a queued unit in production queue
	ENTITY_PRODUCTION_PAUSED,  # Pause/unpause production of a unit type
	PRODUCTION_CANCEL_ALL,  # Cancel ALL queued units at a structure
	ACTION_CANCEL,  # Cancel current unit action (set action = null)
	CANCEL_CONSTRUCTION,  # Cancel an under-construction structure (refund + free)
	PAUSE_CONSTRUCTION,  # Pause/unpause an under-construction structure
	SET_RALLY_POINT,  # Set a structure's rally point to a terrain position
	SET_RALLY_POINT_TO_UNIT,  # Set a structure's rally point to follow a unit
	REPAIR_ENTITY,
	SELL_ENTITY,
	DISABLE_ENTITY,
	CAST_SUPPORT_POWER,
	ATTACK_MOVE,  # Move to position, attacking enemies encountered en route
	STOP,  # Cancel all actions + clear queue, become truly idle
	HOLD_POSITION,  # Stay put, attack enemies in range only (no chase)
	MOVE_NO_ATTACK,  # Move to position, ignore enemies entirely
	PATROL,  # Move between two points repeatedly, engaging enemies
	REVERSE_MOVE,  # Move to position backwards (no rotation)
	SPREAD,  # Radix Seedling: walk to position, build+grow into a Sapling creep source
}

## starts at 1 to avoid falsy 0 value
enum OccupationType {
	STRUCTURE = 1,
	RESOURCE = 2,
	RESOURCE_SPAWNER = 3,
	FOREST = 4,
}

## Command mode for unit orders. NORMAL is the default (right-click = move/attack).
## Other modes are activated by hotkey and consume the next left-click.
enum UnitCommandMode {
	NORMAL,
	ATTACK_MOVE,
	MOVE,
	PATROL,
	REVERSE_MOVE,
	HARVEST,
	SPREAD,
}

enum MovementTypes {
	LAND,
	AIR,
	WATER,
}

enum PlacementTypes {
	LAND,
	WATER,
	SLOPE,
}

enum HeightLevel { WATER = -1, GROUND = 0, HIGH_GROUND = 1, AIR = 2 }

enum Faction {
	AMUNS,
	LEGION,
	RADIX,
	REMNANTS,
}

enum ProductionTabType {
	STRUCTURE,
	DEFENCES,
	INFANTRY,
	VEHICLE,
	AIR,
	WATER,
}

enum StructureProductionType {
	## allows placement on the map, while required resources get used as the building is being constructed
	CONSTRUCT_ON_FIELD_AND_TRICKLE,
	## allows placement on the map, while required resources get used fully before the construction begins
	CONSTRUCT_ON_FIELD_AND_DONT_TRICKLE,
	## allows placement on the map after construction finishes, while required resources get used as the building is being constructed
	CONSTRUCT_OFF_FIELD_AND_TRICKLE,
	## allows placement on the map after construction finishes, while required resources get used fully before the construction begins
	CONSTRUCT_OFF_FIELD_AND_DONT_TRICKLE,
}

enum ProductionTabGridSlots {
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,
}

enum ResourceType {
	CREDITS,
	ENERGY,
}

enum Projectile {
	LASER,
	CANNON,
	ROCKET,
	BULLETS,
}

enum DamageTypes {
	TRUE,  # this will not be affected by armor
	CANNON,
	CORROSIVE,
	CRUSH,
	EXPLOSIVE,
	FIRE,
	LASER,
	MELEE,
	PLASMA,
	PRISM,
	RIFLE,
	ROCKET,
	TESLA,
}

enum SceneId {
	INVALID = -1,
	AMUNS_BEKHENET,
	AMUNS_NAUCRATIS,
	AMUNS_NEMET,
	AMUNS_MNI,
	AMUNS_KISLAGH,
	AMUNS_PYLON,
	AMUNS_ALTAR,
	AMUNS_WALL_PILLAR,
	AMUNS_ANTI_GROUND_TURRET,
	AMUNS_ANTI_AIR_TURRET,
	AMUNS_SOLDIER,
	AMUNS_WORKER,
	AMUNS_TANK,
	AMUNS_HELICOPTER,
	AMUNS_DRONE,
	AMUNS_SYPHON_DRONE,
	LEGION_COMMAND_CENTER,
	LEGION_POWER_PLANT,
	LEGION_BARRACKS,
	LEGION_SOLDIER,
	RADIX_HEART,
	RADIX_SPIRE,
	RADIX_THORN_FORGE,
	RADIX_SKY_BLOOM,
	RADIX_LINKER,
	RADIX_SEEDLING,
	RADIX_SAPLING,
	REMNANTS_COMMAND_CENTER,
	REMNANTS_CASERN,
	REMNANTS_FACTORY,
	REMNANTS_DRONE_TOWER,
	REMNANTS_INCINERATOR,
	REMNANTS_FLAME_TANK,
	NEUTRAL_FOREST_VINE_2_1,
	NEUTRAL_RESOURCE_VINE,
	NEUTRAL_RESOURCE_SPAWNER,
	LEGION_REFINERY,
	LEGION_HARVESTER,
	LEGION_FACTORY,
	LEGION_AIRFIELD,
}
