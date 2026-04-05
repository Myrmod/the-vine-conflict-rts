class_name ResourceVine

extends Vine

# No procedural generation here — visuals live in pre-built tile scenes under
# source/factions/neutral/structures/ResourceNode/tiles/.
# Each tile scene has this script attached and uses the Leafs.glb as a child node.

## The scene path registered in NeutralConstants for property lookups.
## All tile variants (A, B, C…) share these stats.
const _CONSTANTS_SCENE_PATH: String = "res://source/factions/neutral/structures/ResourceNode/ResourceVine.tscn"


func _randomize_model_rotation():
	pass  # Tile scenes position their own geometry.


func _parse_vine_properties():
	# Tile variants have their own scene_file_path which is not registered in
	# NeutralConstants, so look up the shared entry by the base scene path.
	var props: Dictionary = UnitConstants.get_default_properties(_CONSTANTS_SCENE_PATH)
	tile_count = props.get("tile_count", tile_count)
	resources_per_tile = props.get("resources_per_tile", resources_per_tile)
	resource_max = tile_count * resources_per_tile
	resource = resource_max
	restock_rate = props.get("restock_rate", restock_rate)
	restock_interval = props.get("restock_interval", restock_interval)
	restock_delay = props.get("restock_delay", restock_delay)
	hp_max = props.get("hp_max", 0)
	hp = props.get("hp", hp_max)
	armor = props.get("armor", {})
	_footprint = props.get("footprint", Vector2i(tile_count, 1))
