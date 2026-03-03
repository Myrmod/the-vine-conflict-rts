extends GridHotkeys

const CommandCenterUnit = preload("res://source/factions/the_amuns/structures/CommandCenter.tscn")
const VehicleFactoryUnit = preload("res://source/factions/the_amuns/structures/VehicleFactory.tscn")
const AircraftFactoryUnit = preload(
	"res://source/factions/the_amuns/structures/AircraftFactory.tscn"
)
const AntiGroundTurretUnit = preload(
	"res://source/factions/the_amuns/structures/AntiGroundTurret.tscn"
)
const AntiAirTurretUnit = preload("res://source/factions/the_amuns/structures/AntiAirTurret.tscn")
const ShipyardUnit = preload("res://source/factions/the_amuns/structures/Shipyard.tscn")

@onready var _ag_turret_button = find_child("PlaceAntiGroundTurretButton")
@onready var _aa_turret_button = find_child("PlaceAntiAirTurretButton")
@onready var _cc_button = find_child("PlaceCommandCenterButton")
@onready var _vehicle_factory_button = find_child("PlaceVehicleFactoryButton")
@onready var _aircraft_factory_button = find_child("PlaceAircraftFactoryButton")
@onready var _shipyard_button = find_child("PlaceShipyardButton")

var unit = null


func _ready():
	super._ready()
	var ag_turret_properties = UnitConstants.DEFAULT_PROPERTIES[AntiGroundTurretUnit.resource_path]
	_ag_turret_button.tooltip_text = (
		"{0} - {1}\n{2} HP, {3} DPS\n{4}: {5}"
		. format(
			[
				tr("AG_TURRET"),
				tr("AG_TURRET_DESCRIPTION"),
				ag_turret_properties["hp_max"],
				ag_turret_properties["attack_damage"] * ag_turret_properties["attack_interval"],
				tr("RESOURCE"),
				(
					UnitConstants
					. DEFAULT_PROPERTIES[AntiGroundTurretUnit.resource_path]["costs"]["resource"]
				),
			]
		)
	)
	var aa_turret_properties = UnitConstants.DEFAULT_PROPERTIES[AntiAirTurretUnit.resource_path]
	_aa_turret_button.tooltip_text = (
		"{0} - {1}\n{2} HP, {3} DPS\n{4}: {5}"
		. format(
			[
				tr("AA_TURRET"),
				tr("AA_TURRET_DESCRIPTION"),
				aa_turret_properties["hp_max"],
				aa_turret_properties["attack_damage"] * aa_turret_properties["attack_interval"],
				tr("RESOURCE"),
				(
					UnitConstants
					. DEFAULT_PROPERTIES[AntiAirTurretUnit.resource_path]["costs"]["resource"]
				),
			]
		)
	)
	_cc_button.tooltip_text = (
		"{0} - {1}\n{2} HP\n{3}: {4}"
		. format(
			[
				tr("CC"),
				tr("CC_DESCRIPTION"),
				UnitConstants.DEFAULT_PROPERTIES[CommandCenterUnit.resource_path]["hp_max"],
				tr("RESOURCE"),
				(
					UnitConstants
					. DEFAULT_PROPERTIES[CommandCenterUnit.resource_path]["costs"]["resource"]
				),
			]
		)
	)
	_vehicle_factory_button.tooltip_text = (
		"{0} - {1}\n{2} HP\n{3}: {4}"
		. format(
			[
				tr("VEHICLE_FACTORY"),
				tr("VEHICLE_FACTORY_DESCRIPTION"),
				UnitConstants.DEFAULT_PROPERTIES[VehicleFactoryUnit.resource_path]["hp_max"],
				tr("RESOURCE"),
				(
					UnitConstants
					. DEFAULT_PROPERTIES[VehicleFactoryUnit.resource_path]["costs"]["resource"]
				),
			]
		)
	)
	_aircraft_factory_button.tooltip_text = (
		"{0} - {1}\n{2} HP\n{3}: {4}"
		. format(
			[
				tr("AIRCRAFT_FACTORY"),
				tr("AIRCRAFT_FACTORY_DESCRIPTION"),
				UnitConstants.DEFAULT_PROPERTIES[AircraftFactoryUnit.resource_path]["hp_max"],
				tr("RESOURCE"),
				(
					UnitConstants
					. DEFAULT_PROPERTIES[AircraftFactoryUnit.resource_path]["costs"]["resource"]
				),
			]
		)
	)
	_shipyard_button.tooltip_text = (
		"{0} - {1}\n{2} HP\n{3}: {4}"
		. format(
			[
				tr("SHIPYARD"),
				tr("SHIPYARD_DESCRIPTION"),
				UnitConstants.DEFAULT_PROPERTIES[ShipyardUnit.resource_path]["hp_max"],
				tr("RESOURCE"),
				(
					UnitConstants
					. DEFAULT_PROPERTIES[ShipyardUnit.resource_path]["costs"]["resource"]
				),
			]
		)
	)


func _on_place_command_center_button_pressed():
	MatchSignals.place_structure.emit(CommandCenterUnit)


func _on_place_vehicle_factory_button_pressed():
	MatchSignals.place_structure.emit(VehicleFactoryUnit)


func _on_place_aircraft_factory_button_pressed():
	MatchSignals.place_structure.emit(AircraftFactoryUnit)


func _on_place_anti_ground_turret_button_pressed():
	MatchSignals.place_structure.emit(AntiGroundTurretUnit)


func _on_place_anti_air_turret_button_pressed():
	MatchSignals.place_structure.emit(AntiAirTurretUnit)
	
	
func _on_place_shipyard_button_pressed():
	MatchSignals.place_structure.emit(ShipyardUnit)
