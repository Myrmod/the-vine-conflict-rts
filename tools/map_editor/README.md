# RTS Map Editor

The Map Editor is an in-game tool for creating, editing, and exporting maps for the Overgrowth RTS game.

## Features

### Core Functionality
- **Grid-based editing**: Paint collision tiles on a grid
- **Symmetry modes**: Create balanced maps with mirror X, mirror Y, diagonal, or quad symmetry
- **Entity placement**: Place units, structures, and resource nodes
- **Undo/Redo**: Full undo/redo support with Ctrl+Z / Ctrl+Y
- **View modes**: Toggle between game view and collision view (Press V)
- **Save/Export**: Save editable maps and export to runtime format

### Brushes
- **Paint Collision**: Paint walkable/blocked tiles
- **Erase**: Remove entities from the map
- **Place Structure**: Place buildings (Command Centers, Factories, Turrets)
- **Place Unit**: Place units (Workers, Drones, Tanks, Helicopters)

### Symmetry Modes
- **None**: No symmetry
- **Mirror X**: Mirror across vertical axis
- **Mirror Y**: Mirror across horizontal axis
- **Diagonal**: Mirror diagonally (swap X/Y)
- **Quad**: Four-way symmetry for balanced maps

## Usage

### Accessing the Map Editor
From the main menu, click "Map Editor" button.

### Creating a New Map
The editor starts with a default 50x50 map. You can:
1. Select a brush from the left palette
2. Choose a symmetry mode from the toolbar
3. Click/drag on the viewport to paint

### Keyboard Shortcuts
- **Ctrl+Z**: Undo
- **Ctrl+Shift+Z** or **Ctrl+Y**: Redo
- **V**: Toggle collision view

### Saving Maps
Maps are saved in two formats:
- **Editor format** (`MapResource.tres`): Editable format with all data
- **Runtime format** (`MapRuntimeResource.tres`): Optimized for game loading

Use `save_map(path)` for editor format and `export_map(path)` for runtime format.

## Architecture

### Core Classes

#### MapResource
Stores all editable map data:
- Grid size
- Collision grid (walkable/blocked)
- Entity placements (structures, units, resources)
- Cosmetic data

#### MapRuntimeResource
Runtime-optimized format converted from MapResource:
- Streamlined entity spawns
- Baked navigation data
- No editor-specific data

#### SymmetrySystem
Handles coordinate transformations for symmetrical editing:
- Supports 5 modes (None, Mirror X/Y, Diagonal, Quad)
- Automatically applies symmetry to brush operations

#### Brush System
All editing operations use brushes:
- `EditorBrush`: Base class for all brushes
- `PaintCollisionBrush`: Paint collision tiles
- `EraseBrush`: Erase entities
- `EntityBrush`: Place entities

#### Command Pattern (Undo/Redo)
All operations are commands:
- `EditorCommand`: Base command interface
- `PaintCollisionCommand`: Undo/redo collision painting
- `PlaceEntityCommand`: Undo/redo entity placement
- `CommandStack`: Manages history

### Visual Layers
The editor uses separate 3D layers:
- **VisualLayer**: Shows game view
- **CollisionLayer**: Shows collision visualization (red=blocked, green=walkable)
- **GridLayer**: Shows the grid overlay

## Map Data Format

### Grid Indexing
Grid cells are stored in a PackedByteArray using row-major order:
```
index = y * width + x
```

### Entity Placement Format
Entities are stored as dictionaries:
```gdscript
{
    "scene_path": "res://source/factions/the_amuns/units/Tank.tscn",
    "pos": Vector2i(10, 15),
    "player": 0,  # Player/faction ID
    "rotation": 0.0
}
```

### Validation
Maps are validated before export:
- Check size bounds (10x10 to 200x200)
- Verify entity positions are in bounds
- Ensure valid scene paths

## Integration with Match System

The map editor is designed to work with the existing Match system:
1. Editor creates `MapResource` files
2. Export converts to `MapRuntimeResource`
3. Match scene loads `MapRuntimeResource.instantiate_runtime()`
4. Runtime map spawns entities and sets up navigation

## Future Enhancements

Planned features:
- [ ] Navigation baking integration
- [ ] Preview play mode
- [ ] Structure footprint overlay
- [ ] Resource balance checker
- [ ] Fairness validator (symmetry + reachability)
- [ ] Terrain height editing
- [ ] Cosmetic tile painting
- [ ] Copy/paste regions
- [ ] Map templates

## File Locations

- **Editor scene**: `res://tools/map_editor/MapEditor.tscn`
- **Core scripts**: `res://tools/map_editor/*.gd`
- **Brushes**: `res://tools/map_editor/brushes/*.gd`
- **Commands**: `res://tools/map_editor/commands/*.gd`
- **UI components**: `res://tools/map_editor/ui/*.gd`

## Development Notes

### Adding New Brushes
1. Extend `EditorBrush` class
2. Override `apply(cell_pos)` method
3. Use `get_affected_positions()` to apply symmetry
4. Emit `brush_applied` signal when done
5. Add to `BrushType` enum and `_create_brush()` in MapEditor.gd

### Adding New Commands
1. Extend `EditorCommand` class
2. Implement `execute()` and `undo()` methods
3. Store old state in `_init()` for undo
4. Use `command_stack.push_command()` to execute with history

### Renderer Optimization
For large maps:
- `GridRenderer` and `CollisionRenderer` use MultiMesh for performance
- Can add frustum culling or level-of-detail if needed
- Consider viewport size optimization for very large grids
