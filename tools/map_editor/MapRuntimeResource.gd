extends Resource
class_name MapRuntimeResource

## Runtime map data format
## This is the optimized format used by the Match scene at runtime
## Converted from MapResource during export

@export var size: Vector2i = Vector2i(50, 50)

# Navigation data (baked from collision grid)
@export var navigation_mesh_data: Dictionary = {}

# Runtime entity spawns (converted from editor placements)
@export var structure_spawns: Array[Dictionary] = []
@export var unit_spawns: Array[Dictionary] = []
@export var resource_spawns: Array[Dictionary] = []

# Visual data (optional, for cosmetic rendering)
@export var cosmetic_data: Array[Dictionary] = []


func instantiate_runtime() -> Node3D:
	"""Create a runtime map instance that can be used by Match"""
	# This will be implemented to create the actual map node
	# For now, return a placeholder
	var map_instance = Node3D.new()
	map_instance.name = "RuntimeMap"
	return map_instance


static func from_editor_map(editor_map: MapResource) -> MapRuntimeResource:
	"""Convert an editor MapResource to runtime format"""
	var runtime_map = MapRuntimeResource.new()
	runtime_map.size = editor_map.size
	
	# Copy entity spawns (these are already in the right format)
	runtime_map.structure_spawns = editor_map.placed_structures.duplicate(true)
	runtime_map.unit_spawns = editor_map.placed_units.duplicate(true)
	runtime_map.resource_spawns = editor_map.resource_nodes.duplicate(true)
	runtime_map.cosmetic_data = editor_map.cosmetic_tiles.duplicate(true)
	
	# Navigation baking would happen here in a full implementation
	# For now, we'll just store the collision grid data
	runtime_map.navigation_mesh_data = {
		"collision_grid": editor_map.collision_grid,
		"size": editor_map.size
	}
	
	return runtime_map


func validate() -> Array[String]:
	"""Validate runtime map data"""
	var errors: Array[String] = []
	
	if size.x < 10 or size.y < 10:
		errors.append("Map size is too small")
	
	return errors
