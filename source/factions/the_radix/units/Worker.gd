extends "res://source/match/units/Unit.gd"

var resource = 0
var resources_max = null
var resources_gather_rate = null


func is_full():
	assert(resource <= resources_max, "worker capacity was exceeded somehow")
	return resource == resources_max
