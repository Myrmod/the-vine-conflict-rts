extends Node3D

const MovementLineIndicatorScript = preload("res://source/match/handlers/MovementLineIndicator.gd")

var _movement_line_indicator: Node3D = null


func _ready():
	_movement_line_indicator = Node3D.new()
	_movement_line_indicator.set_script(MovementLineIndicatorScript)
	_movement_line_indicator.name = "MovementLineIndicator"
	add_child(_movement_line_indicator)
	MatchSignals.movement_targets_assigned.connect(_on_movement_targets_assigned)


func _on_movement_targets_assigned(unit_target_pairs: Array) -> void:
	_movement_line_indicator.show_indicators(unit_target_pairs)
