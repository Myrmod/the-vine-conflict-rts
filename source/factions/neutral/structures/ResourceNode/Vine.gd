class_name Vine

extends ResourceUnit

signal resource_changed

## Current harvestable resources. Emits resource_changed when updated.
var resource: int = 0:
	set(value):
		var old = resource
		resource = max(0, value)
		if old != resource:
			if resource < old:
				_restock_delay_counter = 0
			resource_changed.emit()
			_update_electricity_intensity()

## Maximum resources this vine can hold (tiles * resources_per_tile).
var resource_max: int = 0

## Resources restored per restock event.
var restock_rate: int = 1

## Ticks between each restock event.
var restock_interval: int = 10

## Ticks to wait after last harvest before restocking begins.
var restock_delay: int = 100

## Number of tiles this vine occupies (parsed from scene name).
var tile_count: int = 1

## Resources granted per tile.
var resources_per_tile: int = 500

var color: Color = Color.GREEN
var armor: Dictionary = {}

var hp: int = 0:
	set(value):
		hp = max(0, value)
		hp_changed.emit()
		if hp <= 0 and _alive:
			_die()
var hp_max: int = 0

signal hp_changed

var _alive: bool = true
var _restock_counter: int = 0
var _restock_delay_counter: int = 0
var _cached_materials: Array[StandardMaterial3D] = []
var _electricity_material: ShaderMaterial = null


func _ready():
	_type = Enums.OccupationType.RESOURCE
	_parse_vine_properties()
	super._ready()
	_setup_electricity_shader()
	_cache_materials()
	_randomize_model_rotation()
	MatchSignals.tick_advanced.connect(_on_tick_advanced)
	_update_electricity_intensity()


func _randomize_model_rotation():
	var model := get_node_or_null("Geometry/Model")
	if model:
		model.rotation.y = randf() * TAU


func _parse_vine_properties():
	var scene_path: String = scene_file_path
	var props: Dictionary = UnitConstants.get_default_properties(scene_path)
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


func is_harvestable() -> bool:
	return resource > 0 and _alive


func _on_tick_advanced():
	if not _alive:
		return
	if resource < resource_max:
		if _restock_delay_counter < restock_delay:
			_restock_delay_counter += 1
			return
		_restock_counter += 1
		if _restock_counter >= restock_interval:
			_restock_counter = 0
			resource = min(resource + restock_rate, resource_max)


func _setup_electricity_shader():
	var shader := load("res://source/shaders/3d/electricity.gdshader") as Shader
	if shader == null:
		return
	_electricity_material = ShaderMaterial.new()
	_electricity_material.shader = shader
	# Create noise images synchronously so the shader works immediately
	var noise_img1 := _generate_noise_image(128, 42)
	var noise_img2 := _generate_noise_image(128, 137)
	_electricity_material.set_shader_parameter("noise", noise_img1)
	_electricity_material.set_shader_parameter("noise2", noise_img2)
	_electricity_material.set_shader_parameter("electricity_color", Color(0.746, 0.904, 1.0, 1.0))
	_electricity_material.set_shader_parameter("intensity", 0.0)


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
	var tex := ImageTexture.create_from_image(img)
	return tex


func _cache_materials():
	var geometry = find_child("Geometry")
	if geometry == null:
		return
	_collect_materials_recursive(geometry)


func _collect_materials_recursive(node: Node):
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node
		for surface_idx in range(mesh_inst.get_surface_override_material_count()):
			var mat = mesh_inst.get_surface_override_material(surface_idx)
			if mat == null:
				mat = mesh_inst.mesh.surface_get_material(surface_idx)
			if mat is StandardMaterial3D:
				var unique_mat: StandardMaterial3D = mat.duplicate()
				if _electricity_material != null:
					unique_mat.next_pass = _electricity_material
				mesh_inst.set_surface_override_material(surface_idx, unique_mat)
				_cached_materials.append(unique_mat)
	for child in node.get_children():
		_collect_materials_recursive(child)


func _update_electricity_intensity():
	if resource_max <= 0:
		return
	var ratio: float = float(resource) / float(resource_max)
	# Electricity: off below 10%, scales up from 10% to 100%
	if _electricity_material != null:
		var elec_intensity: float = 0.0
		if ratio >= 0.1:
			elec_intensity = (ratio - 0.1) / 0.9
		_electricity_material.set_shader_parameter("intensity", elec_intensity)


func _die():
	_alive = false
	_update_electricity_intensity()
	EntityRegistry.unregister(self)
	queue_free()
