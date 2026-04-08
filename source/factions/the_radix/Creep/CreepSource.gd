class_name CreepSource

var radius: float


func apply_creep(_center, _radius):
	for x in range(-_radius, _radius):
		for y in range(-_radius, _radius):
			if Vector2(x, y).length() <= _radius:
				set_cell(_center + Vector2i(x, y), 1)
