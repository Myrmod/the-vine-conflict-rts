extends GridHotkeys

const WorkerUnit = preload("res://source/match/units/Worker.tscn")

var unit = null

@onready var _worker_button = find_child("ProduceWorkerButton")


func _ready():
	super._ready()
	_worker_button.tooltip_text = ("{0} - {1}\n{2} HP\n{3}: {4}, {5}: {6}".format(
		[
			tr("WORKER"),
			tr("WORKER_DESCRIPTION"),
			UnitConstants.DEFAULT_PROPERTIES[WorkerUnit.resource_path]["hp_max"],
			tr("RESOURCE_A"),
			UnitConstants.PRODUCTION_COSTS[WorkerUnit.resource_path]["resource_a"],
			tr("RESOURCE_B"),
			UnitConstants.PRODUCTION_COSTS[WorkerUnit.resource_path]["resource_b"]
		]
	))


func _on_produce_worker_button_pressed():
	ProductionQueue._generate_unit_production_command(
		unit.id,
		WorkerUnit.resource_path,
		unit.player.id,
	)
