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
	MOVE,                                # Move unit(s) to terrain position
	MOVING_TO_UNIT,                     # Move unit to another unit's position
	FOLLOWING,                           # Follow a unit continuously
	COLLECTING_RESOURCES_SEQUENTIALLY,  # Worker harvests from resource node
	AUTO_ATTACKING,                     # Attack a specific enemy unit
	CONSTRUCTING,                       # Assign worker(s) to construct a structure
	ENTITY_IS_QUEUED,                   # Queue unit production at a structure
	STRUCTURE_PLACED,                   # Place a new structure on the map (deducts resources)
	ENTITY_PRODUCTION_CANCELED,         # Cancel a queued unit in production queue
	PRODUCTION_CANCEL_ALL,              # Cancel ALL queued units at a structure
	ACTION_CANCEL,                      # Cancel current unit action (set action = null)
	CANCEL_CONSTRUCTION,                # Cancel an under-construction structure (refund + free)
	SET_RALLY_POINT,                    # Set a structure's rally point to a terrain position
	SET_RALLY_POINT_TO_UNIT,            # Set a structure's rally point to follow a unit
}