class_name TeleporterEffect
extends Node3D
## Teleporter build/sell effect for Amun faction structures.
## Spawns a rotating Teleporter ring that scales up, then a pixelated
## bottom-to-top reveal plays on the model, and finally the ring collapses.
##
## API mirrors AssemblyEffect:
##   progress = 0.0 → model fully visible  (assembled)
##   progress = 1.0 → model fully hidden   (disassembled)

const TELEPORTER_SCENE = preload("res://assets_overide/Amuns/Other/Teleporter.glb")
const RING_SHADER = preload("res://source/shaders/3d/teleporter_ring.gdshader")
const REVEAL_SHADER = preload("res://source/shaders/3d/teleporter_reveal.gdshader")

var teleporter_rotation_speed: float = 1.0
var teleporter_scale_duration: float = 0.4  # seconds for expand/collapse

## When true the animation plays as build (reveal). When false it plays as
## sell (dissolve). Set this before calling set_progress().
var assembling: bool = true

enum Phase { IDLE, EXPAND, REVEAL, COLLAPSE, DONE }
var _phase: int = Phase.IDLE

var _teleporter: Node3D = null
var _start_scale: float = 0.1
var _full_scale: float = 1.0
var _target_scale: float = 0.0
var _y_scale: float = 1.0  # fixed Y scale so teleporter height matches structure
var _player_color: Color = Color(0.2, 0.8, 1.0)

# Duration for each mode (seconds).
var _build_duration: float = 5.0
var _sell_duration: float = 5.0

# Triangle animation durations (seconds) – computed from scale & speed.
var _expand_time: float = 1.0
var _collapse_time: float = 1.0

# Phase boundaries (fraction of total duration, 0‥1).
var _expand_end: float = 0.2
var _collapse_start: float = 0.8

# Reveal / dissolve shader state.
var _reveal_mats: Array[ShaderMaterial] = []
var _reveal_refs: Array = []  # [{mesh: MeshInstance3D, surface_id: int, original: Material}]
var _model_y_min: float = 0.0
var _model_y_max: float = 1.0
var _geometry_node: Node3D = null  # cached Geometry node for visibility control

var _is_setup: bool = false


func _ready() -> void:
	call_deferred("_deferred_setup")


func _deferred_setup() -> void:
	var target := get_parent() as Node3D
	if target == null:
		return

	# Player colour.
	if target.get("player") != null and "color" in target.player:
		_player_color = target.player.color

	# Build time from unit constants.
	if target.get_script() != null:
		var scene_path: String = target.get_script().resource_path.replace(".gd", ".tscn")
		_build_duration = UnitConstants.get_default_properties(scene_path).get("build_time", 5.0)

	# Sell duration.
	if "SELL_DURATION_SEC" in target:
		_sell_duration = target.SELL_DURATION_SEC
	elif "SELL_DURATION_TICKS" in target:
		_sell_duration = target.SELL_DURATION_TICKS * 0.1

	# Collect model meshes (exclude future teleporter child).
	var meshes := _collect_model_meshes(target)
	if meshes.is_empty():
		return

	# Cache Geometry node for visibility toggling.
	_geometry_node = target.find_child("Geometry", true, false) as Node3D

	# Compute bounds.
	var model_center := _compute_xz_center(meshes)
	var xz_radius := _compute_xz_radius(meshes, model_center) * 0.5
	_compute_y_bounds(meshes)

	# Spawn & configure the teleporter ring.
	_teleporter = TELEPORTER_SCENE.instantiate()
	_teleporter.name = "TeleporterRing"
	target.add_child(_teleporter)
	_apply_ring_materials(_teleporter)
	_setup_teleporter_transform(model_center, xz_radius)
	_compute_y_scale()
	_teleporter.visible = false

	# Compute animation durations & phase boundaries.
	_expand_time = teleporter_scale_duration
	_collapse_time = teleporter_scale_duration
	recompute_boundaries()

	_is_setup = true

	# If the parent is already under construction, snap to the right state.
	if target.has_method("is_under_construction") and target.is_under_construction():
		assembling = true
		_teleporter.visible = true
		_hide_model()
		if "construction_progress" in target:
			set_progress(1.0 - target.construction_progress)


func _process(delta: float) -> void:
	if _teleporter == null or not _is_setup:
		return
	_teleporter.rotate_y(teleporter_rotation_speed * delta)
	var cur := _teleporter.scale.x
	var speed := (
		maxf(absf(_full_scale - _start_scale), 0.001) / maxf(teleporter_scale_duration, 0.001)
	)
	var new_xz := move_toward(cur, _target_scale, speed * delta)
	_teleporter.scale = Vector3(new_xz, _y_scale, new_xz)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


## Set the effect progress (mirrors AssemblyEffect convention).
## 0 = assembled / visible,  1 = disassembled / invisible.
func set_progress(p: float) -> void:
	if not _is_setup:
		return
	# Normalise so 0 = animation-start, 1 = animation-end.
	var norm_p: float
	if assembling:
		norm_p = 1.0 - p  # build: p goes 1→0
	else:
		norm_p = p  # sell: p goes 0→1
	_apply_animation(clampf(norm_p, 0.0, 1.0))


## Remove all shader overrides and hide teleporter.
## Call when construction finishes or when freeing the effect.
func clear() -> void:
	_remove_reveal_shaders()
	_show_model()
	if _teleporter != null:
		_teleporter.visible = false
	_target_scale = 0.0
	_phase = Phase.DONE
	_is_setup = false


## Restore normal appearance without disabling the effect (sell cancel).
func reset() -> void:
	_remove_reveal_shaders()
	_show_model()
	if _teleporter != null:
		_teleporter.visible = false
		_teleporter.scale = Vector3(_start_scale, _y_scale, _start_scale)
	_target_scale = _start_scale
	_phase = Phase.IDLE


## Recompute phase boundaries for the current mode.
func recompute_boundaries() -> void:
	var total := _build_duration if assembling else _sell_duration
	_expand_end = clampf(_expand_time / total, 0.01, 0.4)
	_collapse_start = clampf(1.0 - _collapse_time / total, 0.6, 0.99)


# ---------------------------------------------------------------------------
# Animation state machine
# ---------------------------------------------------------------------------


func _apply_animation(norm_p: float) -> void:
	if norm_p < _expand_end:
		# Teleporter expanding.
		if _phase != Phase.EXPAND:
			_enter_expand()
		_target_scale = lerpf(_start_scale, _full_scale, norm_p / _expand_end)

	elif norm_p < _collapse_start:
		# Pixel reveal / dissolve.
		if _phase != Phase.REVEAL:
			_enter_reveal()
		var t := (norm_p - _expand_end) / (_collapse_start - _expand_end)
		_set_reveal_progress(clampf(t, 0.0, 1.0))

	else:
		# Teleporter collapsing.
		if _phase != Phase.COLLAPSE:
			_enter_collapse()
		var t := (norm_p - _collapse_start) / (1.0 - _collapse_start)
		_target_scale = lerpf(_full_scale, 0.0, clampf(t, 0.0, 1.0))
		if norm_p >= 0.99:
			_teleporter.visible = false
			_phase = Phase.DONE


func _enter_expand() -> void:
	_phase = Phase.EXPAND
	_teleporter.visible = true
	_hide_model()
	if _teleporter.scale.x < _start_scale + 0.001:
		_teleporter.scale = Vector3(_start_scale, _y_scale, _start_scale)


func _enter_reveal() -> void:
	_phase = Phase.REVEAL
	_target_scale = _full_scale
	_teleporter.scale = Vector3(_full_scale, _y_scale, _full_scale)
	_show_model()
	var target := get_parent() as Node3D
	if target == null:
		return
	_remove_reveal_shaders()
	var dissolve := not assembling
	_apply_model_reveal_shader(_collect_model_meshes(target), dissolve)


func _enter_collapse() -> void:
	_phase = Phase.COLLAPSE
	_remove_reveal_shaders()
	_target_scale = 0.0


# ---------------------------------------------------------------------------
# Teleporter ring setup
# ---------------------------------------------------------------------------


func _setup_teleporter_transform(model_center: Vector2, xz_radius: float) -> void:
	var parent_world_scale := 1.0
	if _teleporter.get_parent() is Node3D:
		parent_world_scale = maxf(
			(_teleporter.get_parent() as Node3D).global_transform.basis.get_scale().x, 0.0001
		)
	_full_scale = xz_radius / parent_world_scale
	_start_scale = 0.05
	_target_scale = _start_scale
	_teleporter.scale = Vector3(_start_scale, _start_scale, _start_scale)
	_teleporter.global_position = Vector3(
		model_center.x, _teleporter.global_position.y, model_center.y
	)


func _compute_y_scale() -> void:
	# Compute a fixed Y scale so the teleporter height = model height * 1.05.
	var model_height := _model_y_max - _model_y_min
	if model_height <= 0.001:
		return
	# Measure the teleporter's native height from its meshes.
	var native_h := 0.0
	for mesh: MeshInstance3D in _collect_meshes(_teleporter):
		var aabb := mesh.get_aabb()
		native_h = maxf(native_h, aabb.size.y)
	if native_h <= 0.001:
		return
	var parent_world_scale := 1.0
	if _teleporter.get_parent() is Node3D:
		parent_world_scale = maxf(
			(_teleporter.get_parent() as Node3D).global_transform.basis.get_scale().y, 0.0001
		)
	_y_scale = (model_height * 1.05) / (native_h * parent_world_scale)
	_teleporter.scale.y = _y_scale


func _apply_ring_materials(teleporter_node: Node) -> void:
	var meshes := _collect_meshes(teleporter_node as Node3D)
	for mesh: MeshInstance3D in meshes:
		for surface_id in range(mesh.mesh.get_surface_count()):
			var source_mat := mesh.get_active_material(surface_id)
			var mat_name: String = mesh.mesh.surface_get_name(surface_id)
			if mat_name.is_empty() and source_mat != null:
				mat_name = source_mat.resource_name

			var smat := ShaderMaterial.new()
			smat.shader = RING_SHADER
			smat.set_shader_parameter("player_color", _player_color)

			if mat_name == "PlayerColor":
				smat.set_shader_parameter("alpha", 1.0)
				smat.set_shader_parameter("emission_strength", 3.0)
			else:
				smat.set_shader_parameter("alpha", 0.15)
				smat.set_shader_parameter("emission_strength", 0.0)

			mesh.set_surface_override_material(surface_id, smat)


# ---------------------------------------------------------------------------
# Reveal / dissolve shader
# ---------------------------------------------------------------------------


func _apply_model_reveal_shader(meshes: Array, dissolve: bool) -> void:
	for mesh: MeshInstance3D in meshes:
		for surface_id in range(mesh.mesh.get_surface_count()):
			var existing := mesh.get_surface_override_material(surface_id)
			var source := mesh.get_active_material(surface_id)

			var smat := ShaderMaterial.new()
			smat.shader = REVEAL_SHADER
			smat.set_shader_parameter("reveal_progress", 0.0)
			smat.set_shader_parameter("dissolve_mode", dissolve)
			smat.set_shader_parameter("y_min", _model_y_min)
			smat.set_shader_parameter("y_max", _model_y_max)
			smat.set_shader_parameter("player_color", _player_color)
			_copy_material_to_shader(smat, source)

			mesh.set_surface_override_material(surface_id, smat)
			_reveal_mats.append(smat)
			(
				_reveal_refs
				. append(
					{
						"mesh": mesh,
						"surface_id": surface_id,
						"original": existing,
					}
				)
			)


func _remove_reveal_shaders() -> void:
	for ref in _reveal_refs:
		var mesh := ref["mesh"] as MeshInstance3D
		if is_instance_valid(mesh):
			var orig = ref["original"]
			if orig != null and not is_instance_valid(orig):
				orig = null
			mesh.set_surface_override_material(ref["surface_id"], orig)
	_reveal_mats.clear()
	_reveal_refs.clear()


func _set_reveal_progress(p: float) -> void:
	for smat in _reveal_mats:
		smat.set_shader_parameter("reveal_progress", p)


func _hide_model() -> void:
	if _geometry_node != null:
		_geometry_node.visible = false


func _show_model() -> void:
	if _geometry_node != null:
		_geometry_node.visible = true


# ---------------------------------------------------------------------------
# Mesh utilities
# ---------------------------------------------------------------------------


func _collect_meshes(target: Node3D) -> Array:
	var meshes: Array = []
	if target is MeshInstance3D:
		meshes.append(target)
	meshes.append_array(target.find_children("*", "MeshInstance3D", true, false))
	return meshes


func _collect_model_meshes(root: Node3D) -> Array:
	var geo := root.find_child("Geometry", true, false) as Node3D
	if geo == null:
		geo = root
	var all := _collect_meshes(geo)
	if _teleporter == null:
		return all
	var result: Array = []
	for mesh in all:
		if (
			not (mesh as Node).is_ancestor_of(_teleporter)
			and mesh != _teleporter
			and not _teleporter.is_ancestor_of(mesh)
		):
			result.append(mesh)
	return result


func _compute_xz_center(meshes: Array) -> Vector2:
	var xz_min := Vector2(INF, INF)
	var xz_max := Vector2(-INF, -INF)
	for m: MeshInstance3D in meshes:
		var aabb := m.get_aabb()
		for xi in range(2):
			for zi in range(2):
				var corner := aabb.position + Vector3(aabb.size.x * xi, 0.0, aabb.size.z * zi)
				var wp: Vector3 = m.global_transform * corner
				xz_min.x = minf(xz_min.x, wp.x)
				xz_min.y = minf(xz_min.y, wp.z)
				xz_max.x = maxf(xz_max.x, wp.x)
				xz_max.y = maxf(xz_max.y, wp.z)
	return (xz_min + xz_max) * 0.5


func _compute_xz_radius(meshes: Array, center: Vector2) -> float:
	var max_r := 0.0
	for m: MeshInstance3D in meshes:
		var aabb := m.get_aabb()
		for xi in range(2):
			for zi in range(2):
				var corner := aabb.position + Vector3(aabb.size.x * xi, 0.0, aabb.size.z * zi)
				var wp: Vector3 = m.global_transform * corner
				max_r = maxf(max_r, Vector2(wp.x - center.x, wp.z - center.y).length())
	return max_r


func _compute_y_bounds(meshes: Array) -> void:
	_model_y_min = INF
	_model_y_max = -INF
	for m: MeshInstance3D in meshes:
		var aabb := m.get_aabb()
		for xi in range(2):
			for yi in range(2):
				for zi in range(2):
					var corner := (
						aabb.position
						+ Vector3(aabb.size.x * xi, aabb.size.y * yi, aabb.size.z * zi)
					)
					var world_y := (m.global_transform * corner).y
					_model_y_min = minf(_model_y_min, world_y)
					_model_y_max = maxf(_model_y_max, world_y)
	# Extend the range slightly so the reveal animation overshoots the model top.
	var height := _model_y_max - _model_y_min
	_model_y_max += height * 0.1


static func _copy_material_to_shader(smat: ShaderMaterial, source: Material) -> void:
	if not source is StandardMaterial3D:
		return
	var std := source as StandardMaterial3D
	smat.set_shader_parameter("albedo", std.albedo_color)
	if std.albedo_texture != null:
		smat.set_shader_parameter("albedo_texture", std.albedo_texture)
		smat.set_shader_parameter("use_albedo_texture", true)
	smat.set_shader_parameter("metallic", std.metallic)
	smat.set_shader_parameter("roughness", std.roughness)
	smat.set_shader_parameter("specular", std.metallic_specular)
	if std.metallic_texture != null:
		smat.set_shader_parameter("metallic_texture", std.metallic_texture)
		smat.set_shader_parameter("use_metallic_texture", true)
	if std.roughness_texture != null:
		smat.set_shader_parameter("roughness_texture", std.roughness_texture)
		smat.set_shader_parameter("use_roughness_texture", true)
	if std.normal_enabled and std.normal_texture != null:
		smat.set_shader_parameter("normal_texture", std.normal_texture)
		smat.set_shader_parameter("use_normal_texture", true)
		smat.set_shader_parameter("normal_scale", std.normal_scale)
