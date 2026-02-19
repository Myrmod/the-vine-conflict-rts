class_name VineSpawner

extends ResourceUnit

# res://source/factions/neutral/structures/ResourceA.tscn
const VineScene = preload("uid://bf3jjdafqvh0w")

@export var search_radius_cells := 8


func _ready() -> void:
	MatchSignals.tick_advanced.connect(_on_tick_advanced)


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
		print("No free cell for vine")
		return

	var vine = VineScene.instantiate()
	vine.global_position = MatchGlobal.map.cell_to_world(free_cell)
	get_tree().current_scene.add_child(vine)

	# mark occupied in map data
	MatchGlobal.map.occupy_area(free_cell, Vector2i(1, 1))

	print("Vine spawned at ", free_cell)
