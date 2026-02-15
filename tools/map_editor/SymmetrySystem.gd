extends Object
class_name SymmetrySystem

## Handles coordinate transformations for symmetrical map editing

enum Mode {
	NONE,      # No symmetry
	MIRROR_X,  # Mirror across X axis
	MIRROR_Y,  # Mirror across Y axis
	DIAGONAL,  # Mirror diagonally
	QUAD       # Quadrant symmetry (all four)
}

var current_mode: Mode = Mode.NONE
var map_size: Vector2i = Vector2i(50, 50)


func _init(size: Vector2i = Vector2i(50, 50)):
	map_size = size


func set_mode(mode: Mode):
	current_mode = mode


func set_map_size(size: Vector2i):
	map_size = size


func mirror_x(p: Vector2i) -> Vector2i:
	"""Mirror position across X axis (vertical line through center)"""
	return Vector2i(map_size.x - 1 - p.x, p.y)


func mirror_y(p: Vector2i) -> Vector2i:
	"""Mirror position across Y axis (horizontal line through center)"""
	return Vector2i(p.x, map_size.y - 1 - p.y)


func mirror_diagonal(p: Vector2i) -> Vector2i:
	"""Mirror position diagonally (swap x and y)"""
	# Only works for square maps or within bounds
	if p.x < map_size.y and p.y < map_size.x:
		return Vector2i(p.y, p.x)
	return p


func get_symmetric_positions(p: Vector2i) -> Array[Vector2i]:
	"""Get all symmetric positions for the given point based on current mode"""
	var positions: Array[Vector2i] = [p]
	
	match current_mode:
		Mode.NONE:
			pass  # Only the original position
		
		Mode.MIRROR_X:
			var mirrored = mirror_x(p)
			if mirrored != p:  # Don't duplicate center positions
				positions.append(mirrored)
		
		Mode.MIRROR_Y:
			var mirrored = mirror_y(p)
			if mirrored != p:
				positions.append(mirrored)
		
		Mode.DIAGONAL:
			var mirrored = mirror_diagonal(p)
			if mirrored != p:
				positions.append(mirrored)
		
		Mode.QUAD:
			# Apply all four quadrant symmetries
			var mx = mirror_x(p)
			var my = mirror_y(p)
			var mxy = mirror_x(mirror_y(p))
			
			# Add unique positions only
			for pos in [mx, my, mxy]:
				if pos != p and not positions.has(pos):
					positions.append(pos)
	
	return positions


func is_position_in_bounds(p: Vector2i) -> bool:
	"""Check if position is within map bounds"""
	return p.x >= 0 and p.x < map_size.x and p.y >= 0 and p.y < map_size.y


func get_mode_name(mode: Mode) -> String:
	"""Get human-readable name for symmetry mode"""
	match mode:
		Mode.NONE:
			return "None"
		Mode.MIRROR_X:
			return "Mirror X"
		Mode.MIRROR_Y:
			return "Mirror Y"
		Mode.DIAGONAL:
			return "Diagonal"
		Mode.QUAD:
			return "Quad"
		_:
			return "Unknown"
