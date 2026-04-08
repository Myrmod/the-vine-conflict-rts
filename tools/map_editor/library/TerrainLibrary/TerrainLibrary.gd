class_name TerrainLibrary

extends Resource

const TERRAIN_LIBRARY = preload("uid://wobncmqv0prv")

## to get each id we can use
## ResourceLoader.get_resource_uid(terrain.resource_path)
@export var terrain_types: Array[TerrainType] = []
