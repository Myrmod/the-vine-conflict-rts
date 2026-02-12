class_name Enums

# COMMAND TYPES: All possible game-changing actions that can be queued and recorded.
# Every time a human player clicks or an AI makes a decision, a command of one of these types
# is created and queued through CommandBus.push_command(). Commands are recorded by ReplayRecorder
# and executed by Match._execute_command() at the appropriate tick.
enum CommandType {
	MOVE,                                # Move unit to a position (terrain or air-based)
	MOVING_TO_UNIT,                     # Move unit to another specific unit's location
	FOLLOWING,                           # Follow a unit continuously (stay in range)
	COLLECTING_RESOURCES_SEQUENTIALLY,  # Unit harvests resources from resource node
	AUTO_ATTACKING,                     # Unit attacks a specific enemy (with pursuit/range mgmt)
	CONSTRUCTING,                       # Worker unit constructs a structure
	ENTITY_IS_QUEUED,                   # Queue unit production at structure
	STRUCTURE_PLACED,                   # Place new structure at position (human/AI decision)
	ENTITY_PRODUCTION_CANCELED,         # Cancel queued unit production
}