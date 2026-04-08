class_name RemnantsFaction extends Factions

@export var spawn_unit = preload("res://source/factions/the_remnants/structures/CommandCenter.tscn")


static func init() -> void:
	_init_production_grid_values_by_identifier("the_remnants")
	set_starting_resource(10000, 0)
