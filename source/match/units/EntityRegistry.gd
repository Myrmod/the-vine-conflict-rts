# ENTITY REGISTRY: Maps stable unit IDs to unit objects.
# This solves a critical problem for commands and replays: unit references change every frame
# (objects destroyed/created), but we need a way to identify "the same unit" across time.
#
# How it works:
# 1. When a unit spawns: EntityRegistry.register(unit) assigns a unique stable ID
# 2. That ID is stored in unit.id and never changes
# 3. Commands reference units by ID, not by reference (e.g., {"unit": 5} not {unit: <obj>})
# 4. When executing commands: Match._execute_command() converts IDs to objects via EntityRegistry.get_unit(id)
# 5. When unit dies: EntityRegistry.unregister(unit) cleans up the mapping
#
# This allows commands to be:
# - Recorded and serialized to disk (can't serialize object references)
# - Replayed perfectly (same IDs in replay file = same units every time)
# - Sent over network (for future multiplayer)
extends Node

var _next_id := 1
var entities := {} # int -> Unit
var entity_id: int

func register(unit) -> int:
	# Assign a unique stable ID to a newly spawned unit.
	# This ID persists throughout the unit's lifetime and is used in commands.
	var id := _next_id
	_next_id += 1
	entities[id] = unit
	return id

func get_unit(id: int):
	# Look up a unit by its ID. Used by Match._execute_command() to convert
	# command data (which references units by ID) into actual unit objects.
	return entities.get(id, null)

## Called when a unit dies to clean up the mapping
func unregister(_unit):
	entities.erase(_unit.id)
