class_name ResourceSpawner

extends Area3D

## Ticks between each spawn attempt (200 ticks = 20s at 10Hz).
const SPAWN_INTERVAL_TICKS: int = 200
## Maximum world-unit radius to search for a free cell.
const SPAWN_RADIUS: float = 5.0
const ResourceVineScene: PackedScene = preload(
	"res://source/factions/neutral/structures/ResourceNode/ResourceVine.tscn"
)
## ModelHolder paths (relative to assets_overide/ or assets/) for each vine variant.
## Add entries here as new GLB variants are created in Blender.
## The spawner picks one at random and sets it as the model on the spawned tile.
const TILE_MODEL_PATHS: Array[String] = [
	"Resources/VineTile.glb",
]

var id: int
var radius: float:
	get:
		var obs: Node = find_child("MovementObstacle")
		if obs != null:
			return obs.get("radius") as float
		return 0.0
var global_position_yless:
	get:
		return global_position * Vector3(1, 0, 1)
var in_player_vision: bool = false

var _saved_id: int = -1
var _occupied_cell: Vector2i
var _footprint: Vector2i = Vector2i(3, 3)
var _spawn_counter: int = 0
var resource_capacity_bonus: int = 0

var _energy_material: ShaderMaterial = null


func _ready():
	if _saved_id >= 0:
		id = _saved_id
		EntityRegistry.entities[id] = self
		if EntityRegistry._next_id <= id:
			EntityRegistry._next_id = id + 1
	else:
		id = EntityRegistry.register(self)

	var map: Node = MatchGlobal.map
	if is_instance_valid(map):
		_occupied_cell = map.world_to_cell(global_position)
		map.occupy_area(_occupied_cell, _footprint, Enums.OccupationType.RESOURCE_SPAWNER)
		if is_instance_valid(map.terrain_system):
			map.terrain_system.refresh_hole_mask()

	MatchSignals.tick_advanced.connect(_on_tick_advanced)
	_setup_energy_shader()


func _exit_tree():
	if is_instance_valid(MatchGlobal.map):
		MatchGlobal.map.clear_area(_occupied_cell, _footprint)
		if is_instance_valid(MatchGlobal.map.terrain_system):
			MatchGlobal.map.terrain_system.refresh_hole_mask()


func _on_tick_advanced():
	_spawn_counter += 1
	if _spawn_counter < SPAWN_INTERVAL_TICKS:
		return
	_spawn_counter = 0
	_try_spawn_vine()


func _try_spawn_vine():
	var map: Node = MatchGlobal.map
	if map == null:
		return
	var center_cell: Vector2i = map.world_to_cell(global_position)
	var max_cells: int = int(SPAWN_RADIUS / Terrain.CELL_SIZE)
	var best_cell: Vector2i = Vector2i(-1, -1)
	var best_dist_sq: float = INF

	# Spiral search outward from center for closest free cell.
	for ring: int in range(1, max_cells + 1):
		for dx: int in range(-ring, ring + 1):
			for dz: int in range(-ring, ring + 1):
				if abs(dx) != ring and abs(dz) != ring:
					continue
				var candidate: Vector2i = Vector2i(center_cell.x + dx, center_cell.y + dz)
				if not map.is_area_free(candidate, Vector2i(1, 1)):
					continue
				if map.get_cell_type_at_cell(candidate) != MapResource.CELL_GROUND:
					continue
				var world_pos: Vector3 = map.cell_to_world(candidate)
				var dist_sq: float = (world_pos * Vector3(1, 0, 1)).distance_squared_to(
					global_position * Vector3(1, 0, 1)
				)
				if dist_sq > SPAWN_RADIUS * SPAWN_RADIUS:
					continue
				if dist_sq < best_dist_sq:
					best_dist_sq = dist_sq
					best_cell = candidate
		if best_cell != Vector2i(-1, -1):
			break

	if best_cell == Vector2i(-1, -1):
		return

	var vine: ResourceVine = ResourceVineScene.instantiate() as ResourceVine
	var model_path: String = TILE_MODEL_PATHS[randi() % TILE_MODEL_PATHS.size()]
	var model_holder: ModelHolder = vine.get_node_or_null("Geometry/ModelHolder") as ModelHolder
	if model_holder != null:
		model_holder.model_path = model_path
	var spawn_pos: Vector3 = map.cell_to_world(best_cell)
	spawn_pos.y = map.get_height_at_cell(best_cell)
	vine.position = spawn_pos
	get_parent().add_child(vine)
	if resource_capacity_bonus > 0:
		vine.resource_max += resource_capacity_bonus
		vine.resource += resource_capacity_bonus


func _setup_energy_shader() -> void:
	var shader: Shader = load("res://source/shaders/3d/vine_energy_radial.gdshader") as Shader
	if shader == null:
		return
	_energy_material = ShaderMaterial.new()
	_energy_material.shader = shader
	_energy_material.set_shader_parameter("noise", _generate_noise_image(128, 42))
	_energy_material.set_shader_parameter("energy_color", Color(0.2, 0.9, 0.15, 1.0))
	_energy_material.set_shader_parameter("intensity", 0.5)
	_energy_material.set_shader_parameter("brightness", 2.0)
	_energy_material.set_shader_parameter("max_radius", 7.0)
	_energy_material.set_shader_parameter("pulse_speed", 0.5)
	_energy_material.set_shader_parameter("pulse_width", 0.12)
	_energy_material.set_shader_parameter("pulse_count", 1)
	_energy_material.set_shader_parameter("noise_strength", 0.5)
	_apply_energy_to_geometry()


func _generate_noise_image(size: int, seed_val: int) -> ImageTexture:
	var fnl := FastNoiseLite.new()
	fnl.seed = seed_val
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.01
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var val: float = (fnl.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			img.set_pixel(x, y, Color(val, val, val, val))
	return ImageTexture.create_from_image(img)


func _apply_energy_to_geometry() -> void:
	var geometry: Node = find_child("Geometry")
	if geometry == null:
		return
	_apply_energy_recursive(geometry)


func _apply_energy_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		for surf_idx: int in range(mesh_inst.get_surface_override_material_count()):
			var mat: Material = mesh_inst.get_surface_override_material(surf_idx)
			if mat == null:
				mat = mesh_inst.mesh.surface_get_material(surf_idx)
			if mat is StandardMaterial3D:
				var unique_mat: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
				unique_mat.next_pass = _energy_material
				mesh_inst.set_surface_override_material(surf_idx, unique_mat)
	for child: Node in node.get_children():
		_apply_energy_recursive(child)
