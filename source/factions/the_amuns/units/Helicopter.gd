extends "res://source/match/units/Unit.gd"

const ROTOR_SPEED = 800.0  # degrees/s

const WaitingForTargets = preload("res://source/match/units/actions/WaitingForTargets.gd")


func _ready():
	await super()
	default_idle_action_scene = WaitingForTargets
	action = WaitingForTargets.new()


func _physics_process(delta):
	find_child("Rotor").rotation_degrees.y += ROTOR_SPEED * delta
