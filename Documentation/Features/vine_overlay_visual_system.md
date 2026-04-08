# Vine Overlay Visual System

## Problem
Vine resources are rendered as individual 1×1m plane tiles placed on a grid. This creates a visible repeating pattern with hard rectangular edges — it looks artificial rather than like organic vine growth spreading from a tree.

## Solution: Occupancy Mask Overlay (Option 2)
Replace per-tile rendering with a single overlay quad + shader that visualizes vine coverage using a dynamically-updated mask texture.

### Architecture

```
┌─────────────────────────────────────────────────────┐
│  AncientTreeResourceNode (VineSpawner)              │
│  ├── Tree Model (visual)                            │
│  ├── VineOverlay (MeshInstance3D + shader)   ← NEW  │
│  │     └── Reads occupancy mask texture             │
│  └── VineTiles (Area3D, invisible mesh)             │
│        └── Gameplay: selection, targeting, harvest   │
└─────────────────────────────────────────────────────┘
```

**Two-layer separation:**
- **Gameplay layer** (unchanged): VineTile nodes handle harvesting, selection, targeting, collision, and map occupancy. Their `MeshInstance3D` is hidden.
- **Visual layer** (new): A single overlay quad covers the full vine area. A shader reads a mask texture to know which cells have vines, tiles the vine PBR textures, and applies soft organic edges.

### Components

#### 1. Occupancy Mask Texture
- Small `Image` / `ImageTexture`, one pixel per grid cell
- Dimensions: `(search_radius * 2 + 1)` × `(search_radius * 2 + 1)` → 11×11 pixels for radius 5
- White pixel = vine present, black = empty
- Bilinear filtering interpolates between occupied/empty → automatic soft edges
- Updated in real-time as vines spawn or are harvested

#### 2. VineOverlay Shader (`vine_overlay.gdshader`)
- **Mask sampling**: Reads the occupancy mask with bilinear filtering for soft alpha transitions
- **Noise edge distortion**: A noise texture offsets the mask threshold at boundaries, creating irregular organic edges instead of smooth gradients
- **PBR vine textures**: Tiles albedo, normal, roughness, metallic across the quad using world-space UVs
- **Tiling variation**: Applies UV rotation/offset noise to break the repeating texture pattern
- **Alpha cutoff**: Discards fully transparent pixels to avoid overdraw

#### 3. VineOverlay Manager (`VineOverlay.gd`)
Script attached to the overlay MeshInstance3D:
- Creates the mask `Image` and `ImageTexture` at startup
- `mark_cell(world_pos: Vector3)` — sets a mask pixel to white when a vine spawns
- `clear_cell(world_pos: Vector3)` — sets a mask pixel to black when a vine is harvested
- Converts world positions to mask UV coordinates relative to the tree center
- Updates the ImageTexture when the mask changes

#### 4. VineSpawner Changes
After spawning a vine, calls `vine_overlay.mark_cell(vine.global_position)` to update the visual.

#### 5. Resource.gd / ResourceUnit.gd Changes
On harvest (resource depletion / `_exit_tree`), notifies the overlay to clear the cell.

#### 6. VineTile Changes
`MeshInstance3D.visible = false` — the per-tile visual mesh is hidden since the overlay handles rendering.

### Visual Features

| Feature | Mechanism |
|---|---|
| Soft edges at vine boundary | Bilinear-filtered mask texture |
| Organic/irregular edge shapes | Noise-based threshold distortion on mask |
| No repeating tile pattern | World-space UV with noise-based rotation |
| Handles any irregular shape | Mask reflects actual occupancy — crescents, blobs, etc. |
| Growth animation | Mask pixel set when vine spawns → visual updates immediately |
| Harvest feedback | Mask pixel cleared on depletion → area becomes transparent |
| PBR rendering | Same vine textures (albedo, normal, roughness, metallic) |

### Data Flow

```
Vine Spawns:
  VineSpawner._spawn_vine()
    → instantiate VineTile (gameplay, hidden mesh)
    → VineOverlay.mark_cell(world_pos)
      → mask pixel → white
      → ImageTexture updated
      → shader renders vine at that cell

Vine Harvested:
  Resource.resource = 0
    → queue_free()
    → ResourceUnit._exit_tree()
      → Map.clear_area() (gameplay)
      → VineOverlay.clear_cell(world_pos)
        → mask pixel → black
        → ImageTexture updated
        → shader stops rendering vine at that cell
```

### File Inventory

| File | Type | Status |
|---|---|---|
| `ResourceNode/vine_overlay.gdshader` | Shader | New |
| `ResourceNode/VineOverlay.gd` | Script | New |
| `ResourceNode/VineSpawner.gd` | Script | Modified |
| `ResourceNode/Resource.gd` | Script | Modified |
| `ResourceNode/AncientTreeResourceNode.tscn` | Scene | Modified |
| `ResourceNode/VineTile.tscn` | Scene | Modified |
