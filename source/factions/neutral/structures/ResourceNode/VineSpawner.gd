class_name VineSpawner

extends Area3D

@export var search_radius_cells := 5

@onready var vine_scene = preload("uid://dwihfgr811wiv")

var id: int

var global_position_yless:
	get:
		return global_position * Vector3(1, 0, 1)

var radius:
	get:
		if find_child("MovementObstacle"):
			return find_child("MovementObstacle").radius
		return 0

var _occupied_cell: Vector2i
var _footprint: Vector2i = Vector2i(1, 1)
var _type = Enums.OccupationType.RESOURCE_SPAWNER


func _ready() -> void:
	MatchSignals.tick_advanced.connect(_on_tick_advanced)
	id = EntityRegistry.register(self)

	var map = MatchGlobal.map
	if map == null:
		return
	_occupied_cell = map.world_to_cell(global_position)
	map.occupy_area(_occupied_cell, _footprint, _type)


func _on_tick_advanced():
	# 10 tick = 1s
	if Match.tick % (MatchConstants.TICK_RATE * MatchConstants.VINE_SPAWN_RATE_IN_S) == 0:
		_spawn_vine()


func _spawn_vine():
	if MatchGlobal.map == null:
		print("No map found")
		return

	var origin_cell: Vector2i = MatchGlobal.map.world_to_cell(global_position)

	var free_cell: Vector2i = MatchGlobal.map.find_nearest_free_area(
		origin_cell, Vector2i(1, 1), search_radius_cells
	)
	if free_cell == null:
		return

	var vine = vine_scene.instantiate()
	get_tree().current_scene.add_child(vine)
	vine.global_position = MatchGlobal.map.cell_to_world(free_cell)

	# mark occupied in map data
	MatchGlobal.map.occupy_area(free_cell, Vector2i(1, 1), _type)
