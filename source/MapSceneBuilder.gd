class_name MapSceneBuilder

extends RefCounted

## Converts a MapResource (editor format) into a runtime Map scene tree
## that is compatible with Match.gd's expectations.
##
## The generated scene has the same structure as Map.tscn:
##   Map (Node3D, Map.gd)
##     ├─ DirectionalLight3D
##     ├─ WorldEnvironment
##     ├─ Geometry
##     │    ├─ BlackBackgroundFixingAntiAliasingBug
##     │    ├─ Terrain (MeshInstance3D — collision reference)
##     │    └─ TerrainSystem (splatmap rendering)
##     ├─ SpawnPoints
##     │    └─ Marker3D × N
##     ├─ Resources
##     │    └─ entity instances …
##     └─ Decorations
##          └─ entity instances …

const MAP_SCENE_PATH = "res://source/match/Map.tscn"


static func build(map_resource: MapResource) -> Node3D:
	"""Build a runtime Map node tree from a MapResource.
	The returned node can be assigned to Match.map just like a loaded .tscn map."""

	# 1. Instantiate the base Map scene (includes light, environment, fog, etc.)
	var map_scene = load(MAP_SCENE_PATH)
	if map_scene == null:
		push_error("MapSceneBuilder: Cannot load base Map scene at %s" % MAP_SCENE_PATH)
		return null

	var map_node: Node3D = map_scene.instantiate()

	# 2. Set map size — this triggers Map.gd's setter which resizes the Terrain mesh
	map_node.size = Vector2(map_resource.size.x, map_resource.size.y)

	# 3. Add spawn points as Marker3D nodes under SpawnPoints
	var spawn_points_parent = map_node.find_child("SpawnPoints")
	if spawn_points_parent:
		_add_spawn_points(map_resource, spawn_points_parent, map_node)

	# 4. Add placed entities (resources and decorations)
	var resources_parent = map_node.find_child("Resources")
	var decorations_parent = map_node.find_child("Decorations")
	if resources_parent and decorations_parent:
		_add_entities(map_resource, resources_parent, decorations_parent, map_node)

	# 5. Initialize TerrainSystem with splatmap data
	# This must happen after the node enters the tree, so we store
	# the MapResource as metadata for deferred initialization.
	map_node.set_meta("map_resource", map_resource)

	# 6. Copy height and cell-type grids to the runtime Map so units
	#    can query terrain height and movement restrictions.
	if not map_resource.height_grid.is_empty():
		map_node.height_grid = map_resource.height_grid.duplicate()
	if not map_resource.cell_type_grid.is_empty():
		map_node.cell_type_grid = map_resource.cell_type_grid.duplicate()

	# 7. Build cliff collision walls so the navmesh is carved at cliff edges
	#    and units physically cannot clip through.
	map_node.build_cliff_collision()

	# 8. Build slope side walls so units cannot bypass ramps from the sides.
	map_node.build_slope_side_walls()

	# 9. Apply lighting & environment from the MapResource so the game
	#    reproduces the exact same look as the map editor.
	_apply_lighting(map_resource, map_node)

	return map_node


static func _add_spawn_points(map_resource: MapResource, parent: Node3D, owner_node: Node3D):
	var map_center = Vector2(map_resource.size) / 2.0

	for i in range(map_resource.spawn_points.size()):
		var pos = map_resource.spawn_points[i]
		var marker = Marker3D.new()
		marker.name = "SpawnPoint%d" % (i + 1)

		# Compute rotation: face toward map center
		var dir = map_center - Vector2(pos)
		var angle = atan2(dir.x, dir.y)

		marker.transform = Transform3D(Basis(Vector3.UP, angle), Vector3(pos.x, 0, pos.y))

		parent.add_child(marker)
		marker.owner = owner_node


static func _add_entities(
	map_resource: MapResource,
	resources_parent: Node3D,
	decorations_parent: Node3D,
	owner_node: Node3D
):
	for entity in map_resource.placed_entities:
		var scene_path: String = entity.get("scene_path", "")
		if scene_path.is_empty():
			continue

		var scene = load(scene_path)
		if scene == null:
			push_warning("MapSceneBuilder: Cannot load entity scene: %s" % scene_path)
			continue

		var inst = scene.instantiate()
		var pos = entity.get("pos", Vector2i.ZERO)
		var rot: float = entity.get("rotation", 0.0)
		var scl: float = entity.get("entity_scale", 1.0)
		var grid_cell: Vector2 = Vector2i(floor(pos.x), floor(pos.y)) if pos is Vector2 else pos
		var height_y: float = entity.get("y_offset", map_resource.get_height_at(grid_cell))
		var basis := Basis(Vector3.UP, rot)
		if not is_equal_approx(scl, 1.0):
			basis = basis.scaled(Vector3(scl, absf(scl), absf(scl)))
		inst.transform = Transform3D(basis, Vector3(pos.x, height_y, pos.y))

		var mat_path: String = entity.get("material_path", "")
		if not mat_path.is_empty():
			_apply_material_to_model_holders(inst, mat_path)

		# Decide parent: resource nodes go under Resources, everything else under Decorations
		if "ResourceNode" in scene_path or "resource" in scene_path.to_lower():
			resources_parent.add_child(inst)
		else:
			decorations_parent.add_child(inst)
		inst.owner = owner_node


static func _apply_material_to_model_holders(node: Node, mat_path: String) -> void:
	"""Set material_path on all ModelHolder children before they enter the tree."""
	if node is ModelHolder:
		node.material_path = mat_path
	for child in node.get_children():
		_apply_material_to_model_holders(child, mat_path)


static func initialize_terrain_from_meta(map_node: Node3D):
	"""Call this after the Map node has entered the tree to set up
	TerrainSystem splatmaps from the stored MapResource.
	Typically called from Loading.gd after add_child(map)."""
	if not map_node.has_meta("map_resource"):
		return

	var map_resource: MapResource = map_node.get_meta("map_resource")
	var terrain_system = map_node.find_child("TerrainSystem")
	if terrain_system and terrain_system.has_method("set_map"):
		terrain_system.set_map(map_resource)

		# _build_slope_meshes() (called by set_map) writes corrected per-cell
		# heights back to map_resource.height_grid.  Re-sync them to the
		# runtime Map node so units read the right slope heights.
		if not map_resource.height_grid.is_empty():
			map_node.height_grid = map_resource.height_grid.duplicate()


static func _apply_lighting(map_resource: MapResource, map_node: Node3D):
	"""Override the Map scene's DirectionalLight3D and WorldEnvironment
	with the values stored in the MapResource (captured from the editor)."""

	# --- Sun (DirectionalLight3D) ---
	if map_resource.sun_transform != Transform3D.IDENTITY:
		var sun = map_node.find_child("DirectionalLight3D") as DirectionalLight3D
		if sun:
			sun.transform = map_resource.sun_transform
			sun.light_color = map_resource.sun_color
			sun.light_energy = map_resource.sun_energy
			sun.light_specular = map_resource.sun_specular
			sun.shadow_enabled = map_resource.sun_shadow_enabled
			# shadow_bias is intentionally NOT applied from the map resource;
			# Map.tscn's DirectionalLight3D.shadow_bias is authoritative.
			sun.shadow_blur = map_resource.sun_shadow_blur

	# --- Environment ---
	if map_resource.environment:
		var world_env = map_node.find_child("WorldEnvironment") as WorldEnvironment
		if world_env:
			world_env.environment = map_resource.environment.duplicate()
