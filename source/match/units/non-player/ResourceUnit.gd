class_name ResourceUnit

extends Area3D

const ResourceDecayAnimation = preload("res://source/match/utils/ResourceDecayAnimation.tscn")

var radius:
	get:
		if find_child("MovementObstacle"):
			return find_child("MovementObstacle").radius
		return 0
var global_position_yless:
	get:
		return global_position * Vector3(1, 0, 1)
var id: int

var in_player_vision: bool = false

var _saved_id: int = -1
var _occupied_cell: Vector2i
var _footprint: Vector2i = Vector2i(1, 1)
var _type: Enums.OccupationType = Enums.OccupationType.RESOURCE


func _ready():
	if _saved_id >= 0:
		id = _saved_id
		EntityRegistry.entities[id] = self
		if EntityRegistry._next_id <= id:
			EntityRegistry._next_id = id + 1
	else:
		id = EntityRegistry.register(self)

	var map = MatchGlobal.map
	if map == null:
		return

	_occupied_cell = map.world_to_cell(global_position)
	map.occupy_area(_occupied_cell, _footprint, _type)


func _enter_tree():
	tree_exiting.connect(_animate_decay)


func _exit_tree():
	if MatchGlobal.map != null:
		MatchGlobal.map.clear_area(_occupied_cell, _footprint)


func _animate_decay():
	if not in_player_vision:
		return
	var decay_animation = ResourceDecayAnimation.instantiate()
	decay_animation.global_transform = global_transform
	get_parent().add_child.call_deferred(decay_animation)
