# ENTITY REGISTRY: Maps stable integer IDs to unit objects for the command system.
#
# Problem: Commands and replays cannot store object references (they get serialized to disk
# and replayed in a different scene tree). We need a stable way to identify units.
#
# Solution: Every unit gets a unique integer ID on spawn. Commands reference units by ID.
# Match._execute_command() resolves IDs back to objects via get_unit().
#
# Lifecycle:
#   1. Unit spawns → register(unit) → assigns next available ID, stores mapping
#   2. Commands use unit.id (int) in their data dictionaries
#   3. Match._execute_command() → EntityRegistry.get_unit(id) → resolves to object
#   4. Unit dies → unregister(unit) → removes mapping
#   5. New match → reset() → clears all mappings, restarts IDs from 1
#
# Determinism guarantee: IDs are assigned sequentially (1, 2, 3...) in spawn order.
# Same spawn order during replay = same IDs = commands resolve to same units.
extends Node

var _next_id := 1
var entities := {} # int → Unit

func reset():
	## Called by Loading.gd before each match to clear stale mappings from previous matches.
	## Resets ID counter to 1 so replay IDs line up with freshly spawned units.
	entities.clear()
	_next_id = 1

func register(unit) -> int:
	## Assign a unique stable ID to a newly spawned unit.
	## This ID persists throughout the unit's lifetime and is referenced in commands.
	var id := _next_id
	_next_id += 1
	entities[id] = unit
	return id

func get_unit(id: int):
	## Look up a unit by its stable ID. Returns null if the unit was never registered
	## or has already been unregistered (died). Used by Match._execute_command().
	return entities.get(id, null)

func unregister(unit):
	## Remove a unit's mapping when it dies or is freed.
	## After this, get_unit(unit.id) will return null.
	entities.erase(unit.id)
