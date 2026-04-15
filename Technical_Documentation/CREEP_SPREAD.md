# Creep System — Implementation

## Overview

Radix creep is a per-tile ground coverage that:
- Spreads slowly from `CreepSource` structures outward (circular, tile-by-tile)
- Visually covers the terrain with a tiled texture using Wang 2-corner tiles, rendered inside the terrain shader as a top-most overlay
- Grants HP regeneration to allied Radix units standing on it
- Retracts gradually when the owning `CreepSource` is destroyed
- Does not overlap — a cell already claimed by any creep source blocks all others

---

## Data Layer — `CreepMap.gd`

A plain data object (not a Node), held in `MatchGlobal.creep_map`.

**Storage:** `var cells` (untyped) — type chosen once at `initialize()` time based on Radix player count in the match, never changed after that:
- ≤ 8 Radix players → `PackedByteArray` (1 byte/cell)
- ≤ 32 Radix players → `PackedInt32Array` (4 bytes/cell)

Size: `map.width * map.height`, row-major (`y * w + x`).

**Per-cell bitmask:** Each bit K represents `player.id % N` where N is the bit-width of the chosen type.
A value of `0` = no creep.

> **Why not dynamic?** GDScript typed arrays cannot change type at runtime. Since player
> count is fixed for the entire match, a one-time decision at `initialize()` is sufficient.
> All bit access is encapsulated in `CreepMap.gd` — callers never touch the array directly.

**Key methods:**
- `initialize(w, h, radix_player_count)` — allocate and zero, choose storage type
- `is_any_creep(cell)` → bool
- `is_player_bit(cell, bit)` → bool
- `set_player_bit(cell, bit, value)`
- `wang_index(cell)` → int 0–15 (based on 4 diagonal neighbours)
- `world_to_cell(pos)` → Vector2i (floor of X and Z, matches Map)

---

## Spread Logic — `CreepSource.gd`

`CreepSource` extends `RadixStructure` (which extends `Structure`). `Heart` extends `CreepSource` directly.

**Player bit:** `player.id % bit_width` (IDs start at 0).

**Frontier optimisation:** Instead of scanning all owned cells each tick, a `_frontier` array tracks only cells that still have at least one unowned, in-range neighbour. The frontier is updated incrementally:
- When a new cell is claimed, it is added to the frontier if it has expandable neighbours.
- After each spread tick, `_prune_frontier` removes cells that are fully surrounded.

**Spread:** On `MatchSignals.tick_advanced`, counter increments.
Every `RadixConstants.CREEP_SPREAD_INTERVAL_TICKS` (default 10) ticks:
- Bootstrap: if no cells owned yet, claim the center cell (skipped if any creep already there)
- Candidates = 8-neighbours of frontier cells that are within `spread_radius`, in-bounds, and have `is_any_creep() == false` (no overlap with any player's creep)
- Pick `RadixConstants.CREEP_SPREAD_TILES_PER_INTERVAL` (default 1) deterministically using `Match.rng`
- Call `MatchGlobal.creep_map.set_player_bit(cell, player_bit, true)`
- Track owned cells in `_owned_cells: Array[Vector2i]`
- Emit `MatchSignals.creep_map_changed`

**On death / `_exit_tree`:** Pass owned cell list to `MatchGlobal.creep_system.queue_retraction(player_bit, cells)`.

**Lazy init:** The first `CreepSource._ready()` initialises `MatchGlobal.creep_map` (if null) and instantiates `CreepSystem` as a child of Match's parent node.

---

## Retraction + Regen — `CreepSystem.gd`

A `Node3D` added as a child of Match, created lazily by the first `CreepSource` to enter the tree.
Spawns `CreepRenderer` as a child in `_ready()`.

**Retraction:**
- Holds a queue of `{ player_bit: int, cells: Array[Vector2i] }` entries
- Every `RadixConstants.CREEP_RETRACT_INTERVAL_TICKS` (default 10) ticks:
  - For each queued entry, remove `RadixConstants.CREEP_RETRACT_TILES_PER_INTERVAL` (default 5) random cells using `Match.rng`
  - Call `set_player_bit(cell, bit, false)`
  - Emit `creep_map_changed`
  - Discard entry when empty

**HP Regen:**
- Every `RadixConstants.CREEP_REGEN_INTERVAL_TICKS` (default 10) ticks:
  - Iterate all nodes in group `"units"`
  - Skip non-Radix, skip units not on creep, skip full-HP units
  - Allied check: any bit set on the cell must belong to a player with the same `team` as the unit
  - Add `RadixConstants.CREEP_REGEN_HP_PER_INTERVAL` HP (clamped to hp_max)
  - Player lookup is cached in `_player_cache: Dictionary` (built once on first regen tick)

---

## Visual Layer — `CreepRenderer.gd`

A `Node3D` child of `CreepSystem`. No separate mesh — creep is rendered **inside the terrain shader** (`TerrainSystemTerrainMesh.gdshader`) as a post-blend overlay applied to both `TerrainMesh` and `HighGroundMesh`.

**Approach: creep uniforms injected into terrain shader**
- When `creep_map_changed` fires, rebuild an `R8` `ImageTexture` from `CreepMap.cells` using a bulk `PackedByteArray` → `Image.create_from_data()` call (255 = any creep, 0 = none)
- The texture is set on the `creep_tex` uniform of both terrain mesh materials
- No Z-fighting is possible since creep pixels are drawn in the same shader pass as the terrain

**Terrain shader additions (`TerrainSystemTerrainMesh.gdshader`):**
- `uniform sampler2D creep_tex` — R8 presence mask (filter_nearest)
- `uniform sampler2D creep_atlas_tex` — `radix_creep.png`, 16-column Wang atlas (1024×256, first row used)
- `uniform bool creep_enabled`
- `uniform vec2 creep_map_size`
- In `fragment()`, after all terrain blending: sample `creep_tex` → if present, compute Wang index from 4 diagonal neighbours → look up atlas column (V clamped to first row: `cell_frac.y * 0.25`) → alpha-blend and **fully replace** ALBEDO, NORMAL_MAP, ROUGHNESS, and AO, making creep the unconditional top layer

**Atlas layout:** `radix_creep.png` is 1024×256. Row 0 (V 0–0.25) is the tile variant used. 16 columns × 64px each.

---

## Constants — `RadixConstants.gd`

```gdscript
const CREEP_SPREAD_INTERVAL_TICKS: int = 10
const CREEP_SPREAD_TILES_PER_INTERVAL: int = 1
const CREEP_RETRACT_INTERVAL_TICKS: int = 10
const CREEP_RETRACT_TILES_PER_INTERVAL: int = 5
const CREEP_REGEN_INTERVAL_TICKS: int = 10
const CREEP_REGEN_HP_PER_INTERVAL: int = 1
```

---

## Global Access — Patches Applied

**`MatchGlobal.gd`:**
```gdscript
var creep_map: CreepMap = null
var creep_system: CreepSystem = null
```

**`MatchSignals.gd`:**
```gdscript
signal creep_map_changed
```

**`Match.tscn` / `Match.gd`** — no changes needed. `CreepSystem` is instantiated lazily by the first `CreepSource._ready()`.

---

## File Summary

| File | Role |
|---|---|
| `source/factions/the_radix/Creep/CreepMap.gd` | Data: bitmask grid, player bit access, Wang index |
| `source/factions/the_radix/Creep/CreepSource.gd` | Structure: frontier-based spread, lazy init, retraction on death |
| `source/factions/the_radix/Creep/CreepSystem.gd` | Tick handler: retraction queue + HP regen with cached player lookup |
| `source/factions/the_radix/Creep/CreepRenderer.gd` | Visual: uploads R8 cell texture to terrain shader materials |
| `source/factions/the_radix/Creep/radix_creep.png` | Atlas: 1024×256, 16-column Wang 2-corner tiles (row 0 used) |
| `source/factions/the_radix/Constants.gd` | Creep tuning constants |
| `source/factions/the_radix/structures/Heart.gd` | Extends `CreepSource` directly — no extra code needed |
| `source/match/MatchGlobal.gd` | `creep_map`, `creep_system` vars |
| `source/match/MatchSignals.gd` | `creep_map_changed` signal |
| `source/shaders/3d/TerrainSystemTerrainMesh.gdshader` | Creep overlay uniforms + fragment blending (topmost layer) |