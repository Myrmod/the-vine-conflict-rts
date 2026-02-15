extends EditorCommand
class_name PaintCollisionCommand

## Command for painting collision tiles with undo support

var map_resource: MapResource
var positions: Array[Vector2i]
var new_value: int
var old_values: Array[int]


func _init(map_res: MapResource, affected_positions: Array[Vector2i], value: int):
	map_resource = map_res
	positions = affected_positions.duplicate()
	new_value = value
	old_values = []
	
	# Store old values for undo
	for pos in positions:
		old_values.append(map_res.get_collision_at(pos))
	
	description = "Paint Collision (%d cells)" % positions.size()


func execute():
	for pos in positions:
		map_resource.set_collision_at(pos, new_value)


func undo():
	for i in range(positions.size()):
		map_resource.set_collision_at(positions[i], old_values[i])
