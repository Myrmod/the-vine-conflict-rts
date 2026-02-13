extends GridHotkeys

const TankUnit = preload("res://source/match/units/Tank.tscn")

var unit = null

@onready var _tank_button = find_child("ProduceTankButton")


func _ready():
	super._ready()
	var tank_properties = UnitConstants.DEFAULT_PROPERTIES[TankUnit.resource_path]
	_tank_button.tooltip_text = ("{0} - {1}\n{2} HP, {3} DPS\n{4}: {5}, {6}: {7}".format(
		[
			tr("TANK"),
			tr("TANK_DESCRIPTION"),
			tank_properties["hp_max"],
			tank_properties["attack_damage"] * tank_properties["attack_interval"],
			tr("RESOURCE_A"),
			UnitConstants.PRODUCTION_COSTS[TankUnit.resource_path]["resource_a"],
			tr("RESOURCE_B"),
			UnitConstants.PRODUCTION_COSTS[TankUnit.resource_path]["resource_b"]
		]
	))


func _on_produce_tank_button_pressed():
	ProductionQueue._generate_unit_production_command(
		unit.id,
		TankUnit.resource_path,
		unit.player.id,
	)
