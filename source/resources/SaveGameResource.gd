class_name SaveGameResource
extends Resource

## Schema version for forward compatibility.
const SAVE_VERSION: int = 1

@export var version: int = SAVE_VERSION
@export var timestamp: String = ""
@export var map_source_path: String = ""
@export var match_tick: int = 0
@export var rng_state: int = 0
@export var rng_seed: int = 0
@export var match_settings_data: Dictionary = {}
@export var players_data: Array[Dictionary] = []
@export var entities_data: Array[Dictionary] = []
@export var entity_registry_next_id: int = 1
@export var pending_commands: Array[Dictionary] = []
