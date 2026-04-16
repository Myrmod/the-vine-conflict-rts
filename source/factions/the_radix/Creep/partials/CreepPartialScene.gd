class_name CreepPartialScene extends Node3D

## Name of the MeshInstance3D node inside GrassPartials.glb whose mesh to use.
@export var mesh_node_name: String = ""

## How many instances to place per creep cell.
@export var count_per_cell: int = 1

## Uniform scale applied to all instances of this partial.
@export var scale_factor: float = 0.4
