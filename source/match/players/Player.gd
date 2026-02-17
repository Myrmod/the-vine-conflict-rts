class_name Player

extends Node3D

signal changed

@export var resource_a = 10:
	set(value):
		resource_a = value
		emit_changed()
@export var resource_b = 0:
	set(value):
		resource_b = value
		emit_changed()
@export var color = Color.WHITE

var _color_material = null
var id: int
# TEAM SYSTEM: Integer team identifier for team-based gameplay.
# Units with the same team ID cannot attack each other. Teams also share vision - all units
# of teammates are automatically revealed to a player (see Match._setup_unit_groups()).
# Default (0) is assigned by Play.gd: first player=team 0, second player=team 1, etc.
# Custom team values can be set to create alliances or custom match configurations.
var team: int = 0


func _ready():
	id = PlayerManager.add_player()


func add_resources(resources):
	for resource in resources:
		set(resource, get(resource) + resources[resource])


func has_resources(resources):
	if FeatureFlags.allow_resources_deficit_spending:
		return true
	for resource in resources:
		if get(resource) < resources[resource]:
			return false
	return true


func subtract_resources(resources):
	for resource in resources:
		set(resource, get(resource) - resources[resource])


func get_color_material():
	if _color_material == null:
		_color_material = StandardMaterial3D.new()
		_color_material.vertex_color_use_as_albedo = true
		_color_material.albedo_color = color
		_color_material.metallic = 1
	return _color_material


func emit_changed():
	changed.emit()
