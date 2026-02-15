extends RefCounted
class_name EditorBrush

## Base class for all editor brushes
## Brushes handle painting/placing operations on the map

signal brush_applied(positions: Array[Vector2i])

var map_resource: MapResource
var symmetry_system: SymmetrySystem


func _init(map_res: MapResource = null, symmetry_sys: SymmetrySystem = null):
	map_resource = map_res
	symmetry_system = symmetry_sys


func apply(cell_pos: Vector2i):
	"""Apply brush at the given cell position. Override in subclasses."""
	push_error("EditorBrush.apply() must be overridden")


func can_apply(cell_pos: Vector2i) -> bool:
	"""Check if brush can be applied at position. Override for custom logic."""
	return map_resource != null and _is_in_bounds(cell_pos)


func _is_in_bounds(pos: Vector2i) -> bool:
	if map_resource == null:
		return false
	return pos.x >= 0 and pos.x < map_resource.size.x and pos.y >= 0 and pos.y < map_resource.size.y


func get_affected_positions(cell_pos: Vector2i) -> Array[Vector2i]:
	"""Get all positions that will be affected by this brush (includes symmetry)"""
	var positions: Array[Vector2i] = []
	if symmetry_system:
		positions = symmetry_system.get_symmetric_positions(cell_pos)
	else:
		positions = [cell_pos]
	
	# Filter to only in-bounds positions
	return positions.filter(func(p): return _is_in_bounds(p))


func get_brush_name() -> String:
	"""Get display name for this brush"""
	return "Base Brush"


func get_cursor_color() -> Color:
	"""Get color for brush cursor preview"""
	return Color.WHITE
