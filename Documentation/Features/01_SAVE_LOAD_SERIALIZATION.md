# Feature 1: Game State Serialization & Save/Load System

## Overview
Serialize and deserialize the full match state so a game can be saved to disk and loaded back to resume play. This is the foundation for both save/load UI and multiplayer reconnection/rehosting.

## Format
- **Primary**: Godot `.tres` (Resource) format for compactness and native integration
- **Debug mode**: JSON export when `FeatureFlags.debug_save_json` is enabled (human-readable for debugging)
- **Location**: `user://saves/savegame.tres` (single slot, overwritten)

## Save File Resource Structure

```
SaveGameResource (.tres)
├── version: int                          # schema version for forward compat
├── timestamp: String                     # ISO 8601 save time
├── map_source_path: String               # path to the MapResource or .tscn
├── match_tick: int                       # Match.tick at save time
├── rng_state: int                        # Match.rng.state (for deterministic resume)
├── rng_seed: int                         # Match.rng.seed (original seed)
├── match_settings: MatchSettings         # full settings (players, visibility, etc.)
│
├── players: Array[PlayerSaveData]
│   └── PlayerSaveData
│       ├── id: int
│       ├── uuid: String                  # persistent player UUID (for reconnection)
│       ├── credits: int
│       ├── energy: int
│       ├── color: Color
│       ├── team: int
│       ├── faction: Enums.Faction
│       ├── controller: Constants.PlayerType
│       └── support_powers: Dictionary
│
├── entities: Array[EntitySaveData]
│   └── EntitySaveData
│       ├── entity_id: int                # EntityRegistry ID
│       ├── player_id: int                # owning player
│       ├── scene_path: String            # res:// path to unit/structure .tscn
│       ├── position: Vector3             # global_position
│       ├── rotation: Vector3             # rotation euler
│       ├── hp: float
│       ├── hp_max: float
│       ├── is_structure: bool
│       │
│       │  # Unit-specific
│       ├── action_type: String           # current action script name (or "idle")
│       ├── action_data: Dictionary       # action-specific state (target id, etc.)
│       ├── command_queue: Array[Dict]    # queued commands
│       ├── stopped: bool
│       │
│       │  # Structure-specific
│       ├── construction_progress: float
│       ├── is_selling: bool
│       ├── is_repairing: bool
│       ├── is_construction_paused: bool
│       ├── sell_ticks_remaining: int
│       ├── occupied_cell: Vector2i
│       ├── is_disabled: bool
│       ├── energy_provided: int
│       ├── energy_required: int
│       │
│       │  # Production queue (if applicable)
│       └── production_queue: Array[ProductionQueueSaveData]
│           └── ProductionQueueSaveData
│               ├── unit_scene_path: String
│               ├── time_total: float
│               ├── time_left: float
│               ├── paused: bool
│               ├── completed: bool
│               ├── trickle_cost: Dictionary
│               └── trickle_deducted: float
│
├── entity_registry_next_id: int          # EntityRegistry._next_id
│
└── command_bus_pending: Array[Dict]      # commands scheduled for future ticks
```

## Files to Create

| File | Purpose |
|------|---------|
| `source/resources/SaveGameResource.gd` | Resource class with all save data properties |
| `source/resources/PlayerSaveData.gd` | Sub-resource for player state |
| `source/resources/EntitySaveData.gd` | Sub-resource for unit/structure state |
| `source/resources/ProductionQueueSaveData.gd` | Sub-resource for production queue entries |
| `source/match/SaveSystem.gd` | Autoload singleton: `save_game()`, `load_game()` |

## Files to Modify

| File | Change |
|------|--------|
| `source/match/Match.gd` | Add `serialize_state() -> SaveGameResource` and `deserialize_state(save: SaveGameResource)` methods |
| `source/match/units/Unit.gd` | Add `serialize() -> EntitySaveData` and static `deserialize()` |
| `source/match/units/Structure.gd` | Override `serialize()` to include structure-specific data |
| `source/match/units/traits/ProductionQueue.gd` | Add `serialize() -> Array` and `deserialize(data: Array)` |
| `source/match/players/Player.gd` | Add `serialize() -> PlayerSaveData` |
| `source/match/units/EntityRegistry.gd` | Expose `_next_id` for save/restore |
| `source/match/CommandBus.gd` | Add method to export/import pending commands |
| `source/main-menu/Loading.gd` | Add path to load from `SaveGameResource` instead of fresh match |
| `source/FeatureFlags.gd` | Add `debug_save_json: bool` flag |
| `project.godot` | Register SaveSystem autoload |

## Serialization Flow (Save)

```
1. Match.serialize_state() called
2. Create SaveGameResource
3. Set tick, rng state, map path, match_settings
4. For each Player: player.serialize() → PlayerSaveData
5. For each entity in EntityRegistry:
   a. unit.serialize() → EntitySaveData
   b. If Structure: add construction/production data
   c. If has ProductionQueue: production_queue.serialize()
6. Save pending commands from CommandBus
7. Save entity_registry_next_id
8. ResourceSaver.save(resource, "user://saves/savegame.tres")
   OR if debug: JSON.stringify() → FileAccess.store_string()
```

## Deserialization Flow (Load)

```
1. Load SaveGameResource from disk
2. Loading.gd receives save resource (new loading mode)
3. Load map from save.map_source_path (same as normal)
4. Instantiate Match.tscn (same as normal)
5. Set Match.rng.seed = save.rng_seed, Match.rng.state = save.rng_state
6. Set Match.tick = save.match_tick
7. EntityRegistry.reset(), set _next_id = save.entity_registry_next_id
8. Create Players from save.players (same flow, but with saved resources)
9. For each EntitySaveData:
   a. Instantiate scene from scene_path
   b. Set position, rotation, hp, etc.
   c. Register with EntityRegistry using saved entity_id
   d. If Structure: restore construction/production state
   e. If has production_queue data: restore queue
   f. Restore action + command queue
10. Inject pending commands into CommandBus
11. Resume tick timer
```

## Edge Cases
- **Actions referencing other entities by ID**: Action data stores target entity IDs — these must be valid after load. Since we restore all entities with their original IDs, references remain valid.
- **Movement paths**: Cached paths can be recomputed on next tick — no need to serialize.
- **Visual interpolation state**: Will snap on load (acceptable one-frame glitch).
- **Fog of war**: Recomputed from unit positions — no serialization needed.
- **Build grid occupation**: Rebuilt from structure positions on load.

## Testing Strategy
- Save at tick N, load, verify tick resumes at N
- Save with units in combat, load, verify HP and targets restored
- Save with production in progress, load, verify queue resumes
- Compare checksum before save and after load (should match)
- Verify .tres and JSON debug output both produce valid loads
