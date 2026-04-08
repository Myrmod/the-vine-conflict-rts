class_name SupportPower extends Node3D


## this function should be overwritten by the actual
## support powers, which are located in the factions
## directory
func cast(_target: Vector2i):
	print("casting support power at", _target)
