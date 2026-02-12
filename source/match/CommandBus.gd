# CommandBus: Central command queue and execution manager
# 
# This system ensures deterministic game behavior by routing all game-changing actions
# through a single command queue. This enables:
# - Perfect replay functionality (record and replay identical command sequences)
# - Future multiplayer support (all clients execute same commands in same order)
# - Save/load capability (resume from checkpoint)
#
# Both human players and AI must push commands here instead of directly modifying
# game state. Match._execute_command() then applies these commands each tick.

extends Node

# Command queue indexed by tick number
# Structure: { tick: [command_dict, command_dict, ...] }
var commands := {} # tick -> Array[Command]

# Clear all queued commands - used when starting a fresh live match
func clear():
	# Clear all stored commands
	commands.clear()

func push_command(cmd: Dictionary):
	var t: int = cmd.tick
	if not commands.has(t):
		commands[t] = []
	commands[t].append(cmd)
	# Record command for replay capability
	ReplayRecorder.record_command(cmd)

func get_commands_for_tick(tick: int) -> Array:
	# During replay playback, retrieve commands from loaded replay data
	# During live play, retrieve commands from the local queue
	if ReplayRecorder.mode == ReplayRecorder.Mode.PLAY:
		return _replay_commands_for_tick(tick)
	else:
		return _live_commands_for_tick(tick)

func _replay_commands_for_tick(tick: int) -> Array:
	# Extract all commands recorded for this tick from the replay file
	var result := []
	for cmd in ReplayRecorder.replay.commands:
		if cmd.tick == tick:
			result.append(cmd)
	return result

func _live_commands_for_tick(tick: int) -> Array:
	# Get commands queued for this tick during live gameplay
	if not commands.has(tick):
		return []
	return commands[tick]

func load_from_replay_array(arr: Array):
	# Load replay commands into the queue for playback
	# Called when user selects a replay from the menu
	commands.clear()

	for entry in arr:
		var tick = entry.tick
		var cmd = entry

		if not commands.has(tick):
			commands[tick] = []

		commands[tick].append(cmd)
