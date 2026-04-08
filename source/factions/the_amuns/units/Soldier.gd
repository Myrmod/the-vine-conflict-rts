extends "res://source/match/units/Unit.gd"

const WaitingForTargets = preload("res://source/match/units/actions/WaitingForTargets.gd")


func _ready():
	await super()
	default_idle_action_scene = WaitingForTargets
	action = WaitingForTargets.new()
