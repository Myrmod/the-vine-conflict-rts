class_name LegionFaction extends Factions

@export var spawn_unit = preload("res://source/factions/the_legion/structures/CommandCenter.tscn")


static func init() -> void:
	_init_production_grid_values_by_identifier("the_legion")
	set_starting_resource(10000, 0)
