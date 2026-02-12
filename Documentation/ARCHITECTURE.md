# The Vine Conflict RTS - Architecture Overview

## Overview

This document explains the core architectural patterns and systems that new developers should understand.

## 1. The Unified Command System (Deterministic Replay & Future Multiplayer)

**Problem:** Traditional RTS games execute player inputs directly (e.g., `unit.action = Moving...`). This makes replays impossible because physics/RNG runs differently each playthrough, and multiplayer requires clients to exchange state.

**Solution:** All game-changing actions become **Commands** that are:
1. Queued through **CommandBus**
2. Recorded by **ReplayRecorder**
3. Executed in order at specific game **ticks**
4. Deterministic (same tick + same command = same outcome)

### Command Flow

```
Human Input (click)
    ↓
UnitActionsController._try_navigating_selected_units_towards_position()
    ↓
CommandBus.push_command({type: MOVE, tick: 42, data: {...}})
    ↓
ReplayRecorder.record_command()  [saved to disk]
    ↓
Queued in CommandBus._queue
    ↓
[When tick 42 arrives in game loop...]
    ↓
CommandBus.get_commands_for_tick(42)
    ↓
Match._process_commands_for_tick()
    ↓
Match._execute_command()  [applies action to unit]
    ↓
Unit receives Actions.Moving and executes in _process()
```

**Same flow for AI:**
- AI (AutoAttackingBattlegroup) → CommandBus.push_command() → same pipeline
- → Deterministic: human and AI take same code path ✓

**Replay magic:**
- User selects replay → Play.gd calls CommandBus.load_from_replay_array()
- Instead of queuing new commands, CommandBus serves pre-recorded commands
- Same ticks, same commands → same game (perfect replay) ✓

### Key Classes

| Class | File | Purpose |
|-------|------|---------|
| **CommandBus** | `source/match/CommandBus.gd` | Central queue & router for all commands |
| **Match** | `source/match/Match.gd` | Main game loop + command execution |
| **ReplayRecorder** | `source/match/ReplayRecorder.gd` | Records commands to disk |
| **UnitActionsController** | `source/match/players/human/UnitActionsController.gd` | Converts human input to commands |
| **AutoAttackingBattlegroup** | `source/match/players/simple-clairvoyant-ai/AutoAttackingBattlegroup.gd` | AI generates commands |
| **EntityRegistry** | `source/match/units/EntityRegistry.gd` | Maps stable unit IDs to objects |

---

## 2. Team-Based Gameplay

**Goal:** Units on the same team cannot attack each other; teams share vision.

### How Attack Prevention Works

**File:** `source/match/units/actions/AutoAttacking.gd`

```gdscript
static func is_applicable(source_unit, target_unit):
    # ... other checks ...
    and source_unit.player.team != target_unit.player.team  # ← CORE CHECK
```

This validates that a unit can attack a target **before** any action is assigned. If same team, the action simply isn't created.

**Where it's checked:**
1. **UnitActionsController** - Human can't click to attack teammate
2. **AutoAttackingBattlegroup** - AI can't target teammate
3. **Match._execute_command()** - Extra validation layer (defensive)

### How Vision Sharing Works

**File:** `source/match/Match.gd`, function `_setup_unit_groups()`

```gdscript
# Add unit to revealed_units if player visible OR on same team
if player in visible_players:
    unit.add_to_group("revealed_units")
else:
    for visible_player in visible_players:
        if visible_player != null and visible_player.team == player.team:
            unit.add_to_group("revealed_units")
            break
```

**How it cascades:**
- When a teammate's unit spawns, it's added to "revealed_units" group
- FogOfWar constantly syncs visibility of "revealed_units" group
- Teammate units are automatically visible on the map
- Units not in "revealed_units" group are hidden by fog

### Team Assignment

**Default:** Players auto-assigned to different teams to ensure playable matches.
- File: `source/main-menu/Play.gd`
- First player → team 0
- Second player → team 1
- Custom assignments via MatchSettings override this

---

## 3. Game Loop & Tick System

**Tick rate:** 10 ticks per second (100 ms per tick)

### Frame vs Tick

| Concept | Frame | Tick |
|---------|-------|------|
| Runs at | Variable (60+ FPS) | Fixed (10/sec) |
| Purpose | Render, physics, animations | Game logic, commands |
| When | Every `_process()` call | Timer triggers `_on_tick()` |

### Game Loop (Match._on_tick)

Each tick:

1. **Increment tick counter**
2. **Retrieve commands for this tick** via `CommandBus.get_commands_for_tick(tick)`
3. **Execute each command** via `Match._execute_command(cmd)`
4. **Each unit's _process()** runs actions during frame renders
5. **Repeat** next tick

Example: Command queued for tick 42, lands on tick 42, executes deterministically.

### Why Ticks Matter for Replays

- Human plays match, generates 500 commands over 2 minutes
- Each command knows its tick: `{tick: 10, ...}, {tick: 15, ...}, {tick: 42, ...}`
- Replay file saves all commands with their ticks
- Replay playback: execute commands at exact same ticks
- Result: perfect replay ✓

---

## 4. Action System

Actions are state machines that units execute when assigned.

### Action Hierarchy

```
Action (base state machine)
  ├─ Moving
  ├─ MovingToUnit
  ├─ AutoAttacking
  │   ├─ AttackingWhileInRange (sub-action)
  │   └─ FollowingToReachDistance (sub-action)
  ├─ Constructing
  ├─ COLLECTING_RESOURCES_SEQUENTIALLY
  └─ ...
```

### Action Lifecycle

```godscript
# 1. Match._execute_command() creates action
unit.action = Actions.AutoAttacking.new(target_unit)

# 2. Action added to unit (extends Node, added to scene tree)
# 3. Action._ready() called
# 4. Unit._process() loop activates action
# 5. Action updates unit state (position, rotation, etc.)
# 6. When complete, action emits signal or calls queue_free()
```

### Key Action Validation Point

**File:** `source/match/units/actions/AutoAttacking.gd`

```godscript
static func is_applicable(source_unit, target_unit):
    # Called BEFORE action created to validate it's legal
    # Returns true/false, not throwing exceptions
```

This pattern isolates validation from execution.

---

## 5. EntityRegistry: Stable Unit IDs

**Problem:** Commands reference units, but unit objects are created/destroyed each frame. How do you reference "unit 5" in a replay file?

**Solution:** EntityRegistry assigns stable IDs.

```gdscript
# At spawn time
var id = EntityRegistry.register(unit)
unit.id = id  # Never changes during unit lifetime

# In commands
{type: MOVE, data: {targets: [{unit: 5, pos: ...}]}}
         # unit ID (int) not reference (object)

# When executing
var unit = EntityRegistry.get_unit(5)  # Look up by ID
unit.action = Actions.Moving.new(pos)   # Apply action
```

**Why this matters:**
- Commands serialize to disk (can't save object references)
- Replays work (same IDs = same units)
- Future multiplayer (send IDs over network, not objects)

---

## 6. Key Systems by File

### Match.gd - The Orchestrator
- Initializes game state (players, units, map)
- Main game loop (`_on_tick()`)
- Command execution (`_execute_command()`)
- Team-aware unit grouping (`_setup_unit_groups()`)

### CommandBus.gd - The Command Router
- Central queue for all commands
- Records commands to ReplayRecorder
- Switches between live queue and replay playback
- Helper methods for common command types

### UnitActionsController.gd - Human Input Bridge
- Listens to UI signals (terrain_targeted, unit_targeted, etc.)
- Filters selected units (only controlled, only capable)
- Creates Command objects with proper structure
- Queues through CommandBus

### AutoAttackingBattlegroup.gd - AI Decision Maker
- Groups units into attack formations
- Selects targets (closest distance strategy)
- Queues attack/movement commands through CommandBus
- Switches targets when current eliminated

### ReplayRecorder.gd - Persistence
- Records all commands as they're queued
- Saves replay metadata (players, map, tick_rate)
- Saves replay file to disk
- Provides loading interface for Play.gd

### FogOfWar.gd - Vision System
- Queries "revealed_units" group each frame
- Renders vision circles for each unit
- Updates fog/shroud texture
- Team vision happens automatically via group membership

### Enums.gd - Command Type Definitions
- Defines all possible CommandTypes
- Used in command.type field
- Matched in Match._execute_command()

---

## 7. Determinism Checklist

For replays to work perfectly, all game state changes must be:

✓ **Command-based:** Every action is a command (no direct state changes)
✓ **Tick-stamped:** Commands know their execution tick
✓ **Idempotent:** Running same command twice = running once (no state accumulation)
✓ **Deterministic:** Same inputs → same outputs (no RNG on critical paths)
✓ **Recorded:** ReplayRecorder captures every command
✓ **Indexed:** EntityRegistry provides stable unit references
✓ **Serializable:** Command data is pure dicts, not object references

---

## 8. Example: How a Human Attack Works

**Act 1: Human clicks enemy**

1. UI detects click on enemy unit
2. Emits `MatchSignals.unit_targeted.emit(target_unit)`
3. UnitActionsController receives signal
4. Filters selected units: only controlled, only can attack (AutoAttacking.is_applicable)
5. Creates command: `{type: AUTO_ATTACKING, tick: 42, data: {targets: [7], target_unit: 5}}`
6. Calls `CommandBus.push_command()`
7. CommandBus calls `ReplayRecorder.record_command()` (saved!)

**Act 2: Game executes command at tick 42**

1. `_on_tick()` fires
2. `CommandBus.get_commands_for_tick(42)` returns the command
3. `Match._execute_command(cmd)` receives it
4. Validates unit 7 exists and is not queued for deletion
5. Validates unit 5 (target) exists  
6. Creates `Actions.AutoAttacking.new(unit5)`
7. Assigns to unit 7: `unit7.action = ...`

**Act 3: Action executes in frame loop**

1. Unit7._process() checks if action exists
2. Calls action._process()
3. AutoAttacking calculates distance to target
4. If in range: attacks; if not: moves closer
5. Continues until target dies or action cancelled

**Act 4: Replay playback**

1. User selects replay file
2. Play.gd loads it: `CommandBus.load_from_replay_array(replay.commands)`
3. CommandBus now serves commands from loaded array instead of queue
4. At tick 42, same command executes automatically
5. Same unit attacks, same target, same outcome → identical game

---

## 9. Future Extensions

This architecture was designed to support:

### Multiplayer
- Instead of having all players local, each client queues their commands
- Commands sent over network at certain ticks
- All clients execute same commands in same tick order
- Result: synchronized multiplayer without constant state synchronization

### AI Improvements
- Current: AutoAttackingBattlegroup (coordinated melee attacks)
- Future: IntelligenceController (strategy), more command types (build orders, etc.)
- Same pattern: generate commands, queue through CommandBus

### Replay Features
- Fast forward / slow motion (vary tick rate)
- Bookmarks (jump to tick)
- Export (save to video)
- Analytics (analyze command stream)

---

## 10. Debugging Tips

**Commands not executing?**
- Check CommandBus is calling get_commands_for_tick() correctly
- Check tick counter is incrementing
- Check Match._on_tick() is being called

**Units doing wrong thing?**
- Check EntityRegistry.get_unit(id) is finding correct unit
- Check Match._execute_command() is reaching right case statement
- Check unit.action assignment happened

**Replay not working?**
- Check CommandBus.load_from_replay_array() was called
- Check ReplayRecorder recorded all commands
- Check Match is in replay mode (is_replay_mode flag)

**Teams not working?**
- Check player.team is set (should auto-assign in Play.gd)
- Check AutoAttacking.is_applicable() team check is passing
- Check unit is NOT added to "revealed_units" group for enemy units
