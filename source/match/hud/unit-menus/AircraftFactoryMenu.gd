extends GridHotkeys

const HelicopterUnit = preload("res://source/match/units/Helicopter.tscn")
const DroneUnit = preload("res://source/match/units/Drone.tscn")

var unit = null

@onready var _helicopter_button = find_child("ProduceHelicopterButton")
@onready var _drone_button = find_child("ProduceDroneButton")


func _ready():
	super._ready()
	var helicopter_properties = UnitConstants.DEFAULT_PROPERTIES[
		HelicopterUnit.resource_path
	]
	_helicopter_button.tooltip_text = ("{0} - {1}\n{2} HP, {3} DPS\n{4}: {5}, {6}: {7}".format(
		[
			tr("HELICOPTER"),
			tr("HELICOPTER_DESCRIPTION"),
			helicopter_properties["hp_max"],
			helicopter_properties["attack_damage"] * helicopter_properties["attack_interval"],
			tr("RESOURCE_A"),
			UnitConstants.DEFAULT_PROPERTIES[HelicopterUnit.resource_path]["costs"]["resource_a"],
			tr("RESOURCE_B"),
			UnitConstants.DEFAULT_PROPERTIES[HelicopterUnit.resource_path]["costs"]["resource_b"]
		]
	))
	_drone_button.tooltip_text = ("{0} - {1}\n{2} HP\n{3}: {4}, {5}: {6}".format(
		[
			tr("DRONE"),
			tr("DRONE_DESCRIPTION"),
			UnitConstants.DEFAULT_PROPERTIES[DroneUnit.resource_path]["hp_max"],
			tr("RESOURCE_A"),
			UnitConstants.DEFAULT_PROPERTIES[DroneUnit.resource_path]["costs"]["resource_a"],
			tr("RESOURCE_B"),
			UnitConstants.DEFAULT_PROPERTIES[DroneUnit.resource_path]["costs"]["resource_b"]
		]
	))


func _on_produce_helicopter_button_pressed():
	ProductionQueue._generate_unit_production_command(
		unit.id,
		DroneUnit.resource_path,
		unit.player.id,
	)


func _on_produce_drone_button_pressed():
	ProductionQueue._generate_unit_production_command(
		unit.id,
		DroneUnit.resource_path,
		unit.player.id,
	)