class_name VineSpawner 

extends Area3D

# res://source/factions/neutral/structures/ResourceA.tscn
const VineScene = preload("uid://bf3jjdafqvh0w")

@export var search_radius_cells := 8

func _ready() -> void:
	MatchSignals.tick_advanced.connect(_on_tick_advanced)
	
func _on_tick_advanced():
	# 10 tick = 1s
	if Match.tick % 10 == 0:
		_spawn_vine()
	
func _spawn_vine():
	if Match.map == null:
		print("No map found")
		return

	var origin_cell: Vector2i = Match.map.world_to_cell(global_position)

	var free_cell: Vector2i = _find_nearest_free_cell(origin_cell)
	if free_cell == null:
		print("No free cell for vine")
		return

	var vine = VineScene.instantiate()
	vine.global_position = Match.map.cell_to_world(free_cell)
	get_tree().current_scene.add_child(vine)

	# mark occupied in map data
	Match.map.set_cell_occupied(free_cell, true)

	print("Vine spawned at ", free_cell)
		
func _find_nearest_free_cell(center: Vector2i):
	if Match.map.is_cell_free(center):
		return center

	for r in range(1, search_radius_cells + 1):

		for x in range(-r, r + 1):
			for y in [-r, r]:
				var c = center + Vector2i(x, y)
				if Match.map.is_cell_free(c):
					return c

		for y in range(-r + 1, r):
			for x in [-r, r]:
				var c = center + Vector2i(x, y)
				if Match.map.is_cell_free(c):
					return c

	return null
