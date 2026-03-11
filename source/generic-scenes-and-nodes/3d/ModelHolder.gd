class_name ModelHolder extends Node3D

## Usage
## Via export in the inspector:
## model_path = "models/kenney-spacekit/rock_largeA.glb"
##
## Or via code:
## var holder = preload("res://source/generic-scenes-and-nodes/3d/ModelHolder.tscn").instantiate()
## holder.model_path = "RockPack1/Models/Cliff_models.gltf"
## add_child(holder)
##
## A Node3D that manages model loading with override/fallback support.
##
## Resolution order:
## 1. res://assets_overide/<model_path>  (private, git-ignored assets)
## 2. res://assets/<model_path>          (repository default assets)
## 3. A generated fallback cube mesh

const OVERRIDE_PREFIX := "res://assets_overide/"
const DEFAULT_PREFIX := "res://assets/"
const SIZE_CACHE_PATH := "res://data/model_sizes.json"

static var _size_cache: Dictionary = {}
static var _cache_loaded: bool = false

## Relative path to the model inside assets/ (e.g. "models/kenney-spacekit/rock_largeA.glb")
@export var model_path: String = ""

## Optional relative path to a material inside assets/ to apply as material_override
@export var material_path: String = ""

## Size of the fallback cube when no model is found
@export var fallback_cube_size: Vector3 = Vector3(1, 1, 1)

## Color of the fallback cube
@export var fallback_cube_color: Color = Color.MAGENTA

var _loaded_source: String = ""


func _ready() -> void:
	if not model_path.is_empty():
		load_model(model_path)


func load_model(path: String) -> void:
	model_path = path
	_clear_children()

	var mat: Material = _resolve_material()

	# 1. Try override path
	var override_path := OVERRIDE_PREFIX + path
	if ResourceLoader.exists(override_path):
		if _try_instantiate(override_path, mat):
			_loaded_source = override_path
			_update_size_cache(path)
			return

	# 2. Try default path
	var default_path := DEFAULT_PREFIX + path
	if ResourceLoader.exists(default_path):
		if _try_instantiate(default_path, mat):
			_loaded_source = default_path
			_update_size_cache(path)
			return

	# 3. Fallback cube
	push_warning("ModelHolder: No model found for '%s', using fallback cube." % path)
	_create_fallback_cube(_get_cached_size(path))
	_loaded_source = "fallback"


func get_loaded_source() -> String:
	return _loaded_source


func _resolve_material() -> Material:
	if material_path.is_empty():
		return null
	for prefix in [OVERRIDE_PREFIX, DEFAULT_PREFIX]:
		var full_path: String = prefix + material_path
		if ResourceLoader.exists(full_path):
			var res = load(full_path)
			if res is Material:
				return res
	return null


func _try_instantiate(resource_path: String, mat: Material = null) -> bool:
	var res = load(resource_path)
	if res == null:
		return false

	if res is PackedScene:
		var instance: Node = res.instantiate()
		add_child(instance)
		if mat:
			_apply_material_override(instance, mat)
		return true

	if res is Mesh:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = res
		if mat:
			mesh_instance.material_override = mat
		add_child(mesh_instance)
		return true

	push_warning("ModelHolder: Resource at '%s' is not a PackedScene or Mesh." % resource_path)
	return false


func _apply_material_override(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_apply_material_override(child, mat)


func _create_fallback_cube(size: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = fallback_cube_color
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.name = "FallbackCube"
	add_child(mesh_instance)


func _clear_children() -> void:
	for child in get_children():
		child.queue_free()


# region Size cache


func _compute_children_size() -> Vector3:
	var points: PackedVector3Array = PackedVector3Array()
	_gather_aabb_points(self, points)
	if points.is_empty():
		return fallback_cube_size
	var min_pt := points[0]
	var max_pt := points[0]
	for p in points:
		min_pt = Vector3(minf(min_pt.x, p.x), minf(min_pt.y, p.y), minf(min_pt.z, p.z))
		max_pt = Vector3(maxf(max_pt.x, p.x), maxf(max_pt.y, p.y), maxf(max_pt.z, p.z))
	return max_pt - min_pt


func _gather_aabb_points(node: Node, points: PackedVector3Array) -> void:
	if node is MeshInstance3D and node.mesh:
		var aabb: AABB = node.mesh.get_aabb()
		var xform := _get_transform_relative_to_self(node)
		for i in 8:
			points.append(xform * aabb.get_endpoint(i))
	for child in node.get_children():
		_gather_aabb_points(child, points)


func _get_transform_relative_to_self(node: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current := node
	while current != self and current != null:
		if current is Node3D:
			xform = current.transform * xform
		current = current.get_parent()
	return xform


func _update_size_cache(path: String) -> void:
	var size := _compute_children_size()
	var arr := [snappedf(size.x, 0.001), snappedf(size.y, 0.001), snappedf(size.z, 0.001)]
	_load_size_cache()
	if _size_cache.get(path) != arr:
		_size_cache[path] = arr
		_save_size_cache()


func _get_cached_size(path: String) -> Vector3:
	_load_size_cache()
	if _size_cache.has(path):
		var arr: Array = _size_cache[path]
		return Vector3(arr[0], arr[1], arr[2])
	return fallback_cube_size


static func _load_size_cache() -> void:
	if _cache_loaded:
		return
	_cache_loaded = true
	if not FileAccess.file_exists(SIZE_CACHE_PATH):
		return
	var file := FileAccess.open(SIZE_CACHE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		_size_cache = json.data


static func _save_size_cache() -> void:
	if not OS.has_feature("editor"):
		return
	var file := FileAccess.open(SIZE_CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_size_cache, "\t"))

# endregion
