class_name CreepRenderer

extends Node3D

## Uploads creep data to the TerrainSystem shader as an overlay.
## No separate mesh — creep is rendered inside the terrain fragment().
## Uses bilinear-filtered cell texture + noise for organic procedural edges.

const _GROUND_PATH: String = "res://assets_overide/Radix/Creep/creep_terrain.png"
const _NORMAL_PATH: String = "res://assets_overide/Radix/Creep/creep_terrain_normal.png"

var _cell_texture: ImageTexture = null
var _terrain_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	MatchSignals.creep_map_changed.connect(_on_creep_map_changed)
	_setup_terrain_materials()


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
