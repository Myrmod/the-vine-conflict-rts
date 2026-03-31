extends Node

const RESOURCES := [
	preload("res://assets_overide/RockPack1/CliffPartials/CliffCorner_1.res"),
	preload("res://assets_overide/RockPack1/CliffPartials/CliffCorner_2.res"),
	preload("res://assets_overide/RockPack1/CliffPartials/CliffStraight_1.res"),
	preload("res://assets_overide/RockPack1/CliffPartials/CliffStraight_2.res"),
	preload("res://assets_overide/RockPack1/CliffPartials/CliffStraight_3.res"),
	preload("res://assets_overide/RockPack1/CliffPartials/CliffStraight_4.res"),
]


func _ready():
	for resource in RESOURCES:
		if resource is Mesh:
			var mesh: Mesh = resource
			print(mesh.resource_path, " AABB: ", mesh.get_aabb())
		else:
			push_warning(resource.resource_path + " is not a Mesh")

	get_tree().quit()
