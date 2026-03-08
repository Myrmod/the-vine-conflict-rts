class_name Player

extends Node3D

signal changed

# Maybe PlayerData.gd should be incorporated into this, feels duplicate?

@export var credits = 10:
	set(value):
		credits = value
		emit_changed()
		MatchSignals.player_resource_changed.emit(credits, Enums.ResourceType.CREDITS)
@export var energy = 0:
	set(value):
		energy = value
		MatchSignals.player_resource_changed.emit(energy, Enums.ResourceType.ENERGY)

@export var color = Color.WHITE

var id: int
# TEAM SYSTEM: Integer team identifier for team-based gameplay.
# Units with the same team ID cannot attack each other. Teams also share vision - all units
# of teammates are automatically revealed to a player (see Match._setup_unit_groups()).
# Default (0) is assigned by Play.gd: first player=team 0, second player=team 1, etc.
# Custom team values can be set to create alliances or custom match configurations.
var team: int = 0
var faction: Enums.Faction:
	set(_faction):
		faction = _faction

var _color_material = null


func _ready():
	id = PlayerManager.add_player()


func add_resources(resources):
	for resource in resources:
		var current = get(resource)
		if current == null:
			current = 0
		set(resource, current + resources[resource])


func has_resources(resources):
	if FeatureFlags.allow_resources_deficit_spending:
		return true
	for resource in resources:
		var current = get(resource)
		if current == null:
			current = 0
		if current < resources[resource]:
			return false
	return true


func subtract_resources(resources):
	for resource in resources:
		var current = get(resource)
		if current == null:
			current = 0
		set(resource, current - resources[resource])


func get_color_material():
	if _color_material == null:
		_color_material = StandardMaterial3D.new()
		_color_material.vertex_color_use_as_albedo = true
		_color_material.albedo_color = color
		_color_material.metallic = 1
	return _color_material


func emit_changed():
	changed.emit()


func initialize_resources(resources):
	credits = resources["credits"]
	energy = resources["energy"]
