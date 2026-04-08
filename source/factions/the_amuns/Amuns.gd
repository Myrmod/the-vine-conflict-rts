class_name AmunsFaction extends Factions

@export var spawn_unit = preload("res://source/factions/the_amuns/structures/Bekhenet.tscn")


static func init() -> void:
	_init_production_grid_values_by_identifier("the_amuns")
	set_starting_resource(10000, 0)
