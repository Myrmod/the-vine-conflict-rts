# Map Editor Quick Reference

## Keyboard Shortcuts
- **Ctrl+Z**: Undo
- **Ctrl+Y** or **Ctrl+Shift+Z**: Redo
- **V**: Toggle View Mode (Game ↔ Collision)

## Brush Types
1. **Paint Collision** - Paint blocked/walkable tiles (Red = blocked, Green = walkable)
2. **Erase** - Remove entities at position
3. **Structure** - Place buildings (requires selection from palette)
4. **Unit** - Place units (requires selection from palette)

## Symmetry Modes
- **None**: No symmetry
- **Mirror X**: Reflects across vertical center line
- **Mirror Y**: Reflects across horizontal center line  
- **Diagonal**: Swaps X and Y coordinates (requires square map)
- **Quad**: All four quadrants mirrored

## File Operations (File Menu)
- **New Map**: Creates new 50x50 map
- **Load Map**: Opens .tres map file
- **Save Map**: Saves to .tres editor format
- **Export for Runtime**: Exports to runtime format

## Available Entities (from palette)

### Structures
- Command Center
- Vehicle Factory
- Aircraft Factory
- Anti-Ground Turret
- Anti-Air Turret

### Units
- Worker
- Drone
- Tank
- Helicopter

### Resources
(Automatically placed as resource nodes)

## Map Data Format

### Grid Coordinates
```
(0,0) at top-left
X increases → right
Y increases ↓ down

Grid index = Y * width + X
```

### Collision Values
- `0` = Walkable (Green in collision view)
- `1` = Blocked (Red in collision view)

## Workflow

### Creating a New Map
1. Click "Map Editor" from main menu
2. Select brush from left palette
3. Choose symmetry mode (optional)
4. Click/drag in viewport to paint
5. File > Save Map when done

### Editing Existing Map
1. File > Load Map
2. Select .tres file
3. Edit as needed
4. File > Save Map

### Exporting for Game
1. Complete your map
2. File > Export for Runtime
3. Choose filename with .tres extension
4. Map is now ready for Match scene

## Tips

### For Balanced Maps
- Use Quad symmetry for 4-player maps
- Use Mirror X or Y for 2-player maps
- Start with structure placement, then add resources

### Best Practices
- Save frequently (no autosave yet)
- Test different symmetry modes
- Use undo liberally while experimenting
- Name your maps descriptively
- Keep maps between 30x30 and 100x100 for performance

### Common Issues
- **Can't paint**: Check that a brush is selected
- **Entities not appearing**: Ensure proper entity selected in palette
- **Symmetry not working**: Diagonal mode requires square maps
- **Map too small/large**: Edit size programmatically or create new

## Map Validation

Maps are validated on save/export for:
- Size bounds (10x10 minimum, 200x200 maximum)
- Entity positions within map bounds
- Valid scene paths

Validation errors appear in status bar.

## Technical Details

### File Formats
- **MapResource.tres**: Editor format with all metadata
- **MapRuntimeResource.tres**: Optimized for game loading

### Scene Paths
All entities reference their .tscn files:
```
res://source/factions/the_amuns/units/Tank.tscn
res://source/factions/the_amuns/structures/CommandCenter.tscn
```

### Player IDs
- Player 0: First player (usually human)
- Player 1-7: Additional players
- Used for faction-based placement

## Architecture Overview

```
MapEditor (Control)
├── MapResource (data)
│   ├── collision_grid: PackedByteArray
│   ├── placed_entities: Array[Dict]
│
├── SymmetrySystem
│   └── Coordinate transformations
│
├── Brushes
│   ├── EditorBrush (base)
│   ├── PaintCollisionBrush
│   ├── EraseBrush
│   ├── StructureBrush
│
├── Commands (Undo/Redo)
│   ├── EditorCommand (base)
│   ├── CommandStack
│   ├── PaintCollisionCommand
│   └── PlaceEntityCommand
│
└── Rendering
    ├── GridRenderer (MultiMesh)
    ├── CollisionRenderer (MultiMesh)
    └── EditorCursor
```

## Extending the Editor

### Adding New Brushes
1. Create new class extending `EditorBrush`
2. Override `apply(cell_pos)` method
3. Add to `BrushType` enum
4. Add to `_create_brush()` switch

### Adding New Commands
1. Create class extending `EditorCommand`
2. Implement `execute()` and `undo()` methods
3. Store old state in constructor
4. Push to command_stack when executing

### Adding New Entity Types
1. Add scene to UnitConstants
2. EntityPalette auto-updates
3. Use EntityBrush

## Support

For issues or questions:
- Check README.md for detailed documentation
- See IMPLEMENTATION_SUMMARY.md for technical details
- Review source code comments for specific implementations
