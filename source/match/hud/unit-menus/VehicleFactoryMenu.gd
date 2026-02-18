extends GridHotkeys

const WorkerUnit = preload("res://source/factions/the_amuns/units/Worker.tscn")
const TankUnit = preload("res://source/factions/the_amuns/units/Tank.tscn")

var unit = null

@onready var _worker_button = find_child("ProduceWorkerButton")
@onready var _tank_button = find_child("ProduceTankButton")


func _ready():
	super._ready()
	_worker_button.tooltip_text = (
		"{0} - {1}\n{2} HP\n{3}: {4}, {5}: {6}"
		. format(
			[
				tr("WORKER"),
				tr("WORKER_DESCRIPTION"),
				UnitConstants.DEFAULT_PROPERTIES[WorkerUnit.resource_path]["hp_max"],
				tr("RESOURCE_A"),
				UnitConstants.DEFAULT_PROPERTIES[WorkerUnit.resource_path]["costs"]["resource_a"],
			]
		)
	)
	var tank_properties = UnitConstants.DEFAULT_PROPERTIES[TankUnit.resource_path]
	_tank_button.tooltip_text = (
		"{0} - {1}\n{2} HP, {3} DPS\n{4}: {5}, {6}: {7}"
		. format(
			[
				tr("TANK"),
				tr("TANK_DESCRIPTION"),
				tank_properties["hp_max"],
				tank_properties["attack_damage"] * tank_properties["attack_interval"],
				tr("RESOURCE_A"),
			]
		)
	)


func _on_produce_worker_button_pressed():
	(
		ProductionQueue
		. _generate_unit_production_command(
			unit.id,
			WorkerUnit.resource_path,
			unit.player.id,
		)
	)


func _on_produce_tank_button_pressed():
	(
		ProductionQueue
		. _generate_unit_production_command(
			unit.id,
			TankUnit.resource_path,
			unit.player.id,
		)
	)
