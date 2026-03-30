extends Node

func _ready():
	var mesh1 = load("res://assets_overide/RockPack1/CliffPartials/CliffCorner_1.res")
	var mesh2 = load("res://assets_overide/RockPack1/CliffPartials/CliffStraigth_1.res")
	print("Corner AABB: ", mesh1.get_aabb())
	print("Straight AABB: ", mesh2.get_aabb())
	get_tree().quit()
