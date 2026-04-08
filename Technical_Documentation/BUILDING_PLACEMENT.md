# Building Placement System

## Overview
The game now features a grid-based building placement system by default, with the option to toggle to free placement mode during construction.

## Features

### Grid-Based Placement (Default)
- Buildings snap to a grid with configurable cell size (default: 2.0 units)
- Rotation is restricted to 4 cardinal directions (0°, 90°, 180°, 270°)
- Provides consistent, aligned building placement for strategic base layouts

### Free Placement Mode
- Press **Ctrl+G** during building placement to toggle free placement mode
- Allows placing buildings at any position and any rotation angle
- Useful for custom layouts or terrain adaptation

## Controls

### Building Placement
- Click a building button in the Command Center menu to start placement
- Move mouse to position the building blueprint
- The blueprint will snap to the grid unless free placement mode is active

### Rotation
- Press **R** to rotate the building by 90° in grid mode or 45° in free placement mode
- Or hold **Left Mouse Button** and drag to rotate towards mouse cursor
- Rotation automatically snaps to 90° increments in grid mode

### Placement Mode Toggle
- Press **Ctrl+G** to toggle between grid and free placement modes
- The blueprint position updates immediately when toggling

### Confirm/Cancel
- **Left Mouse Button** (release) - Place the building
- **Right Mouse Button** - Cancel placement

## Configuration

The system can be configured via FeatureFlags autoload:

### `use_grid_based_placement` (bool, default: true)
- When `true`, buildings snap to grid by default
- When `false`, buildings use free placement by default
- Can still toggle modes with Ctrl+G regardless of this setting

### `grid_cell_size` (float, default: 2.0)
- Size of each grid cell in world units
- Determines the spacing between grid snap points
- Larger values create coarser grids, smaller values create finer grids

## Examples

### Example 1: Standard Grid Placement
1. Click "Vehicle Factory" in Command Center menu
2. Move mouse over map - blueprint snaps to grid
3. Press R to rotate 90° if needed
4. Left-click to place

### Example 2: Free Placement for Terrain Adaptation
1. Click "Anti-Air Turret" in Command Center menu
2. Press Ctrl+G to enable free placement mode
3. Position turret at exact desired location on hillside
4. Hold LMB and drag to rotate to exact angle
5. Release LMB to place

### Example 3: Using Free Placement for Specific Buildings
1. Place several buildings on grid for main base (standard grid placement)
2. Click next building and press Ctrl+G to enable free placement
3. Position building at strategic angle using free placement
4. Place building - mode automatically resets to grid for next building
5. Continue placing remaining buildings on grid

## Technical Details

- Grid snapping rounds X and Z coordinates to nearest grid cell center
- Rotation snapping rounds to nearest 90° increment
- Free placement mode resets to grid mode after each building is placed or canceled
- Collision detection and resource checking remain the same in both modes
