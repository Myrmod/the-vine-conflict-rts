extends GridHotkeys

const DroneUnit = preload("res://source/factions/the_amuns/units/Drone.tscn")

var unit = null

@onready var _drone_button = find_child("ProduceDroneButton")


func _ready():
	super._ready()
	_drone_button.tooltip_text = (
		"{0} - {1}\n{2} HP\n{3}: {4}"
		. format(
			[
				tr("DRONE"),
				tr("DRONE_DESCRIPTION"),
				UnitConstants.DEFAULT_PROPERTIES[DroneUnit.resource_path]["hp_max"],
				tr("RESOURCE"),
				UnitConstants.DEFAULT_PROPERTIES[DroneUnit.resource_path]["costs"]["resource"],
			]
		)
	)


func _on_produce_drone_button_pressed():
	(
		ProductionQueue
		. _generate_unit_production_command(
			unit.id,
			DroneUnit.resource_path,
			unit.player.id,
		)
	)
