# Feature 2: Save/Load UI

## Overview
Add functional Save and Load buttons to both the main menu and in-game menu, replacing the existing `print("TODO")` stubs.

## Main Menu — Load Button

### Current State
- `Main.gd` has `_on_Load_button_pressed()` → `print("TODO")`
- Button already exists in Main.tscn

### Target Behavior
1. Player clicks "Load Game"
2. Check if `user://saves/savegame.tres` exists
   - If not: show popup "No save file found"
   - If exists: transition to Loading scene with save resource
3. Loading.gd handles loading from save (Feature 1 deserialization flow)
4. Match starts at saved state

### Implementation
- `Main.gd._on_Load_button_pressed()`: check file existence, load resource, pass to Loading scene
- No file browser needed (single save slot)
- Show confirmation dialog: "Load saved game? (Map: X, Tick: Y)"

## In-Game Menu — Save & Load Buttons

### Current State
- `Menu.gd` has `_on_save_button_pressed()` → `print("TODO")`
- `Menu.gd` has `_on_load_button_pressed()` → `print("TODO")`
- Buttons already exist in Menu scene

### Save Button (In-Game)
1. Player presses Save
2. `SaveSystem.save_game()` called
3. Brief "Game Saved" notification (use MatchOverlay or toast)
4. Game remains paused (menu stays open)

### Load Button (In-Game)
1. Player presses Load
2. Confirmation dialog: "Load last save? Current progress will be lost."
3. On confirm: tear down current match, transition to Loading with save resource
4. Match resumes from saved state

### Multiplayer Considerations
- **Save**: In multiplayer, only the host can save (button hidden/disabled for clients)
  - Save includes all players' states and UUIDs for rehosting
- **Load**: In multiplayer, load is only available from the Lobby (rehost flow, Feature 3)
  - In-game Load button is hidden/disabled in multiplayer matches

## Files to Modify

| File | Change |
|------|--------|
| `source/Main.gd` | Replace `_on_Load_button_pressed()` TODO with load logic |
| `source/match/Menu.gd` | Replace save/load TODOs with SaveSystem calls |
| `source/match/Menu.gd` | Add multiplayer visibility logic for save/load buttons |
| `source/match/hud/MatchOverlay.gd` | Add "Game Saved" toast notification (optional) |

## Files to Create

| File | Purpose |
|------|---------|
| (none — uses SaveSystem from Feature 1) | |

## UI Flow Diagrams

### Main Menu Load
```
Main Menu
  └─ [Load Game]
       ├─ No save file → "No save file found" popup
       └─ Save exists → Confirmation dialog
            ├─ Cancel → back to menu
            └─ OK → Loading.tscn (save_resource mode)
                 └─ Match starts at saved tick
```

### In-Game Save
```
In-Game Menu (ESC)
  └─ [Save Game]
       └─ SaveSystem.save_game()
            └─ "Game Saved" toast → menu stays open
```

### In-Game Load (Singleplayer only)
```
In-Game Menu (ESC)
  └─ [Load Game]
       └─ "Load last save?" confirmation
            ├─ Cancel → back to menu
            └─ OK → Tear down match
                 └─ Loading.tscn (save_resource mode)
                      └─ Match starts at saved tick
```
