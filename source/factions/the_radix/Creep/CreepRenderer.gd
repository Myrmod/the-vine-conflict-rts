class_name CreepRenderer

extends Node3D

## Uploads creep data to the TerrainSystem shader as an overlay.
## No separate mesh — creep is rendered inside the terrain fragment().
## Uses bilinear-filtered cell texture + noise for organic procedural edges.

const _GROUND_PATH: String = "res://assets_overide/Radix/Creep/creep_terrain.png"
const _NORMAL_PATH: String = "res://assets_overide/Radix/Creep/creep_terrain_normal.png"
const _GRASS_PARTIAL_PATH: String = "res://assets_overide/Radix/Partials/GrassPartials.glb"
const _PARTIALS_DIR: String = "res://source/factions/the_radix/Creep/partials"
const _GRASS_SHADER_PATH: String = "res://source/factions/the_radix/Creep/partials/grass_material.gdshader"

var _cell_texture: ImageTexture = null
var _terrain_materials: Array[ShaderMaterial] = []
## One entry per mesh found in the GLB: {mesh, base_basis, y_offset, count_per_cell, scale_factor}
var _variants: Array[Dictionary] = []
var _variant_mmis: Array[MultiMeshInstance3D] = []
var _grass_material: ShaderMaterial = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 42
	_grass_material = _create_grass_material()
	_load_grass_variants()
	MatchSignals.creep_map_changed.connect(_on_creep_map_changed)
	_setup_terrain_materials()


func _create_grass_material() -> ShaderMaterial:
	var shader: Shader = load(_GRASS_SHADER_PATH) as Shader
	if shader == null:
		return null
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	return mat


func _load_grass_variants() -> void:
	# Step 1: load all meshes from the GLB keyed by node name.
	var mesh_by_name: Dictionary = _load_glb_meshes()
	if mesh_by_name.is_empty():
		return
	# Step 2: scan the partials folder for .tscn config scenes.
	var files: PackedStringArray = DirAccess.get_files_at(_PARTIALS_DIR)
	for fname: String in files:
		if not fname.ends_with(".tscn"):
			continue
		var packed: PackedScene = load(_PARTIALS_DIR + "/" + fname) as PackedScene
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		var scene: CreepPartialScene = inst as CreepPartialScene
		if scene == null:
			inst.free()
			continue
		var mesh_name: String = scene.mesh_node_name
		var count_per_cell: int = scene.count_per_cell
		var scale_factor: float = scene.scale_factor
		inst.free()
		if mesh_name == "" or not mesh_by_name.has(mesh_name):
			continue
		var entry: Dictionary = mesh_by_name[mesh_name]
		(
			_variants
			. append(
				{
					"mesh": entry["mesh"],
					"base_basis": entry["base_basis"],
					"y_offset": entry["y_offset"],
					"count_per_cell": count_per_cell,
					"scale_factor": scale_factor,
				}
			)
		)


## Loads every MeshInstance3D from the GLB and returns a dictionary keyed by node name.
func _load_glb_meshes() -> Dictionary:
	var packed: PackedScene = load(_GRASS_PARTIAL_PATH) as PackedScene
	if packed == null:
		return {}
	var root: Node = packed.instantiate()
	var result: Dictionary = {}
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var accumulated: Transform3D = Transform3D.IDENTITY
		var node: Node = mi
		while node != root and node != null:
			if node is Node3D:
				accumulated = (node as Node3D).transform * accumulated
			node = node.get_parent()
		var basis: Basis = accumulated.basis
		var aabb: AABB = mi.mesh.get_aabb()
		result[mi.name] = {
			"mesh": mi.mesh,
			"base_basis": basis,
			"y_offset": _aabb_min_y_after_basis(aabb, basis),
		}
	root.queue_free()
	return result


## Returns how far to shift up so the mesh bottom is at y=0.
func _aabb_min_y_after_basis(aabb: AABB, basis: Basis) -> float:
	var min_y: float = INF
	for xi: int in [0, 1]:
		for yi: int in [0, 1]:
			for zi: int in [0, 1]:
				var corner: Vector3 = (
					aabb.position + Vector3(aabb.size.x * xi, aabb.size.y * yi, aabb.size.z * zi)
				)
				min_y = minf(min_y, (basis * corner).y)
	return -min_y


func _exit_tree() -> void:
	if MatchSignals.creep_map_changed.is_connected(_on_creep_map_changed):
		MatchSignals.creep_map_changed.disconnect(_on_creep_map_changed)
	for mat: ShaderMaterial in _terrain_materials:
		mat.set_shader_parameter("creep_enabled", false)


func _setup_terrain_materials() -> void:
	var map = MatchGlobal.map
	if map == null:
		return
	var ts: TerrainSystem = map.terrain_system as TerrainSystem
	if ts == null:
		return

	var creep_map: CreepMap = MatchGlobal.creep_map
	if creep_map == null:
		return

	var ground_tex: Texture2D = load(_GROUND_PATH) as Texture2D
	var normal_tex: Texture2D = load(_NORMAL_PATH) as Texture2D
	var map_size: Vector2 = Vector2(float(creep_map.width), float(creep_map.height))

	_build_cell_texture(creep_map)

	# Apply to both base and high-ground terrain meshes.
	for mesh_name: String in ["TerrainMesh", "HighGroundMesh"]:
		var mesh_node: Node = ts.get_node_or_null(mesh_name)
		if mesh_node == null:
			continue
		var mat: ShaderMaterial = mesh_node.get("material_override") as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter("creep_tex", _cell_texture)
		mat.set_shader_parameter("creep_ground_tex", ground_tex)
		mat.set_shader_parameter("creep_normal_tex", normal_tex)
		mat.set_shader_parameter("creep_map_size", map_size)
		mat.set_shader_parameter("creep_enabled", true)
		_terrain_materials.append(mat)


func _on_creep_map_changed() -> void:
	var creep_map: CreepMap = MatchGlobal.creep_map
	if creep_map == null:
		return
	if _terrain_materials.is_empty():
		_setup_terrain_materials()
		return
	_upload_cell_texture(creep_map)
	_rebuild_grass_multimesh(creep_map)


func _rebuild_grass_multimesh(creep_map: CreepMap) -> void:
	if _variants.is_empty():
		return
	var map = MatchGlobal.map
	if map == null:
		return
	var num_variants: int = _variants.size()
	# Ensure one MultiMeshInstance3D per variant.
	while _variant_mmis.size() < num_variants:
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		add_child(mmi)
		_variant_mmis.append(mmi)
	for vi: int in range(num_variants):
		var variant: Dictionary = _variants[vi]
		var count_per_cell: int = variant["count_per_cell"]
		var base_basis: Basis = variant["base_basis"]
		var y_offset: float = variant["y_offset"]
		var sf: float = variant["scale_factor"]
		var positions: Array[Vector3] = []
		var cell_idx: int = 0
		for cy: int in range(creep_map.height):
			for cx: int in range(creep_map.width):
				if creep_map.cells[cell_idx] != 0:
					for k: int in range(count_per_cell):
						_rng.seed = (cell_idx * num_variants + vi) * count_per_cell + k
						var ox: float = _rng.randf()
						var oz: float = _rng.randf()
						var h: float = map.get_height_at_cell(Vector2i(cx, cy))
						positions.append(Vector3(float(cx) + ox, h, float(cy) + oz))
				cell_idx += 1
		var mm: MultiMesh = MultiMesh.new()
		mm.mesh = variant["mesh"]
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = positions.size()
		for i: int in range(positions.size()):
			_rng.seed = vi * 999983 + i
			var angle: float = _rng.randf() * TAU
			var basis: Basis = (Basis(Vector3.UP, angle) * base_basis).scaled(Vector3(sf, sf, sf))
			var pos: Vector3 = positions[i] + Vector3(0.0, y_offset * sf, 0.0)
			mm.set_instance_transform(i, Transform3D(basis, pos))
		_variant_mmis[vi].multimesh = mm
		_variant_mmis[vi].material_override = _grass_material


func _build_cell_texture(creep_map: CreepMap) -> void:
	var img: Image = _cells_to_image(creep_map)
	_cell_texture = ImageTexture.create_from_image(img)


func _upload_cell_texture(creep_map: CreepMap) -> void:
	var img: Image = _cells_to_image(creep_map)
	if _cell_texture == null:
		_cell_texture = ImageTexture.create_from_image(img)
	else:
		_cell_texture.update(img)


func _cells_to_image(creep_map: CreepMap) -> Image:
	var data: PackedByteArray = PackedByteArray()
	data.resize(creep_map.width * creep_map.height)
	for i: int in range(data.size()):
		data[i] = 255 if creep_map.cells[i] != 0 else 0
	var img: Image = Image.create_from_data(
		creep_map.width, creep_map.height, false, Image.FORMAT_R8, data
	)
	return img
