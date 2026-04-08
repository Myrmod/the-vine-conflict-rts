class_name PlaceSpawnCommand

extends EditorCommand

## Command for placing / removing player spawn points with undo support

var map_resource: MapResource
var position: Vector2i
var is_remove: bool

# For undo
var _previous_spawn_points: Array[Vector2i]


func _init(map_res: MapResource, pos: Vector2i, remove: bool = false):
	map_resource = map_res
	position = pos
	is_remove = remove

	# Snapshot for undo
	_previous_spawn_points = map_res.spawn_points.duplicate()

	if remove:
		description = "Remove spawn point at %s" % pos
	else:
		description = "Place spawn point at %s" % pos


func execute():
	if is_remove:
		map_resource.remove_spawn_point(position)
	else:
		map_resource.add_spawn_point(position)


func undo():
	map_resource.spawn_points = _previous_spawn_points.duplicate()
