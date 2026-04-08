class_name RadixFaction extends Factions

@export var spawn_unit = preload("res://source/factions/the_radix/structures/Heart.tscn")


static func init() -> void:
	_init_production_grid_values_by_identifier("the_radix")
	set_starting_resource(10000, 0)
