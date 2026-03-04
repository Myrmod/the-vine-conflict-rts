extends Hotkeys

const HelicopterUnit = preload("res://source/factions/the_amuns/units/Helicopter.tscn")

var unit = null

@onready var _helicopter_button = find_child("ProduceHelicopterButton")

func _ready():
	super._ready()
	var helicopter_properties = UnitConstants.DEFAULT_PROPERTIES[HelicopterUnit.resource_path]
	_helicopter_button.tooltip_text = (
		"{0} - {1}\n{2} HP, {3} DPS\n{4}: {5}"
		. format(
			[
				tr("HELICOPTER"),
				tr("HELICOPTER_DESCRIPTION"),
				helicopter_properties["hp_max"],
				helicopter_properties["attack_damage"] * helicopter_properties["attack_interval"],
				tr("RESOURCE"),
				UnitConstants.DEFAULT_PROPERTIES[HelicopterUnit.resource_path]["costs"]["resource"],
			]
		)
	)


func _on_produce_helicopter_button_pressed():
	(
		ProductionQueue
		. _generate_unit_production_command(
			unit.id,
			HelicopterUnit.resource_path,
			unit.player.id,
		)
	)
