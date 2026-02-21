class_name PlaceTextureCommand

extends EditorCommand

## Command for placing entities (structures, units, resources) with undo support

var map_resource: MapResource
var positions: Array[Vector2i]
var terrain: TerrainType
var rotation: float

# For undo: store what was at these positions before
var removed_textures: Array[Dictionary] = []


func _init(
	map_res: MapResource,
	affected_positions: Array[Vector2i],
	terrain: TerrainType,
	rot: float = 0.0
):
	map_resource = map_res
	positions = affected_positions.duplicate()
	terrain = terrain
	rotation = rot

	# Store what will be removed for undo
	_store_removed_textures()

	description = "Place texture (%d positions)" % [positions.size()]


func _store_removed_textures():
	"""Store textures that will be removed for undo"""
	for pos in positions:
		var removed_at_pos = []

		removed_textures.append({"pos": pos, "textures": removed_at_pos})


func execute():
	for pos in positions:
		# Remove existing textures at position
		map_resource.placed_textures = map_resource.placed_textures.filter(
			func(u): return u.pos != pos
		)

		# Place new texture
		map_resource.add_texture(terrain, pos, rotation)


func undo():
	# Remove placed textures
	for pos in positions:
		map_resource.placed_textures = map_resource.placed_textures.filter(
			func(u): return u.pos != pos
		)

	# Restore removed textures
	for item in removed_textures:
		for texture in item.textures:
			map_resource.placed_textures.append(texture.data)
