extends Node

## Trait to configure how the UnitPortrait camera frames this unit.
## Add as a child of any unit scene and adjust exports in the inspector.

## Orthographic camera size override (0 = use default auto-sizing)
@export var camera_size: float = 0.0

## Vertical offset for the camera look target
@export var camera_height: float = 0.15

## Distance multiplier from the unit
@export var camera_distance: float = 1.0
