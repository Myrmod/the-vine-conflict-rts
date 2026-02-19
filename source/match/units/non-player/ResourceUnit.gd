class_name ResourceUnit

extends Area3D

const ResourceDecayAnimation = preload("res://source/match/utils/ResourceDecayAnimation.tscn")

var radius:
	get:
		return find_child("MovementObstacle").radius
var global_position_yless:
	get:
		return global_position * Vector3(1, 0, 1)
var id: int

var _occupied_cell: Vector2i
var _footprint: Vector2i = Vector2i(1, 1)


func _ready():
	id = EntityRegistry.register(self)

	var map = MatchGlobal.map
	if map == null:
		push_error("ResourceUnit: MatchGlobal.map is null")
		return

	_occupied_cell = map.world_to_cell(global_position)
	map.occupy_area(_occupied_cell, _footprint)


func _enter_tree():
	tree_exiting.connect(_animate_decay)


func _exit_tree():
	if MatchGlobal.map != null:
		MatchGlobal.map.free_area(_occupied_cell, _footprint)


func _animate_decay():
	var decay_animation = ResourceDecayAnimation.instantiate()
	decay_animation.global_transform = global_transform
	get_parent().add_child.call_deferred(decay_animation)
