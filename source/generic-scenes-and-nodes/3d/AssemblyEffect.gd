class_name AssemblyEffect
extends Node3D
## Reusable build/sell assembly effect.
## Add as a child of any Structure node. It auto-hooks into construction and
## sell lifecycle by watching the parent's state each frame.
##
## progress = 0.0 → model fully visible, particles invisible (assembled)
## progress = 1.0 → model fully invisible, particles scattered (dissolved)

@export var particle_count: int = 500
@export var particle_size: float = 0.02
@export var scatter_radius: float = 1.0
@export var particle_color: Color = Color(0.3, 0.9, 1.0)

const ASSEMBLY_SHADER = preload("res://source/shaders/3d/assembly_effect.gdshader")

## When true the animation plays in reverse (build: 1→0). Set false for sell (0→1).
var assembling: bool = true

var _progress: float = 0.0
var _surface_mats: Array[ShaderMaterial] = []
var _original_overrides: Array = []  # Array of {mesh, surface_id, material}
var _multimesh: MultiMesh = null
var _mmi: MultiMeshInstance3D = null
var _surface_points: PackedVector3Array
var _scatter_positions: PackedVector3Array
var _y_min: float = 0.0
var _y_max: float = 1.0
var _is_setup: bool = false


func _ready() -> void:
	# Wait one frame so the parent's _ready() (including _setup_color) finishes first.
	call_deferred("_deferred_setup")


func _deferred_setup() -> void:
	var target := get_parent() as Node3D
	if target == null:
		return
	var meshes := _collect_meshes(target)
	if meshes.is_empty():
		return
	_compute_y_bounds(meshes)
	_cache_and_apply_shaders(meshes)
	# Use player colour for particles — most reliable source.
	if target.get("player") != null and "color" in target.player:
		particle_color = target.player.color
	_surface_points = _sample_surface_points(meshes, particle_count)
	_build_scatter_positions()
	_setup_multimesh()
	_is_setup = true
	# If the parent structure is already under construction, start scattered.
	if target.has_method("is_under_construction") and target.is_under_construction():
		assembling = true
		_progress = 1.0
	_apply_progress()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


## Set the effect progress. 0 = assembled/visible, 1 = scattered/invisible.
func set_progress(p: float) -> void:
	_progress = clampf(p, 0.0, 1.0)
	if _is_setup:
		_apply_progress()


## Remove all surface overrides and hide particles (call before queue_free or
## after construction finishes to let normal materials show).
func clear() -> void:
	for entry in _original_overrides:
		if not is_instance_valid(entry.mesh):
			continue
		if entry.material != null and not is_instance_valid(entry.material):
			continue
		(entry.mesh as MeshInstance3D).set_surface_override_material(
			entry.surface_id, entry.material
		)
	_original_overrides.clear()
	_surface_mats.clear()
	if _mmi != null:
		_mmi.visible = false
	_is_setup = false


# ---------------------------------------------------------------------------
# Internal: shader / material setup
# ---------------------------------------------------------------------------


func _collect_meshes(target: Node3D) -> Array:
	var meshes: Array = []
	if target is MeshInstance3D:
		meshes.append(target)
	meshes.append_array(target.find_children("*", "MeshInstance3D", true, false))
	return meshes


func _compute_y_bounds(meshes: Array) -> void:
	_y_min = INF
	_y_max = -INF
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
					_y_min = minf(_y_min, world_y)
					_y_max = maxf(_y_max, world_y)


func _cache_and_apply_shaders(meshes: Array) -> void:
	for mesh: MeshInstance3D in meshes:
		for surface_id in range(mesh.mesh.get_surface_count()):
			# Store current override so we can restore it later.
			var existing := mesh.get_surface_override_material(surface_id)
			_original_overrides.append(
				{"mesh": mesh, "surface_id": surface_id, "material": existing}
			)
			var smat := ShaderMaterial.new()
			smat.shader = ASSEMBLY_SHADER
			smat.set_shader_parameter("progress", _progress)
			smat.set_shader_parameter("y_min", _y_min)
			smat.set_shader_parameter("y_max", _y_max)
			# Copy visual properties from the active material so the model
			# keeps its correct look while the dissolve shader runs.
			var source_mat := mesh.get_active_material(surface_id)
			_copy_material_to_shader(smat, source_mat)
			mesh.set_surface_override_material(surface_id, smat)
			_surface_mats.append(smat)


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


# ---------------------------------------------------------------------------
# Internal: particles
# ---------------------------------------------------------------------------


func _sample_surface_points(meshes: Array, count: int) -> PackedVector3Array:
	var tris: Array = []
	var total_area := 0.0
	for m: MeshInstance3D in meshes:
		var faces := m.mesh.get_faces()
		var xform := m.global_transform
		var i := 0
		while i + 2 < faces.size():
			var a: Vector3 = xform * faces[i]
			var b: Vector3 = xform * faces[i + 1]
			var c: Vector3 = xform * faces[i + 2]
			var area := (b - a).cross(c - a).length() * 0.5
			if area > 0.00001:
				total_area += area
				tris.append({"a": a, "b": b, "c": c, "area": area})
			i += 3
	var points := PackedVector3Array()
	if tris.is_empty() or total_area < 0.00001:
		return points
	for _i in range(count):
		var r := randf() * total_area
		var acc := 0.0
		for tri in tris:
			acc += tri.area
			if acc >= r:
				var u := randf()
				var v := randf()
				if u + v > 1.0:
					u = 1.0 - u
					v = 1.0 - v
				points.append(tri.a + (tri.b - tri.a) * u + (tri.c - tri.a) * v)
				break
	return points


func _build_scatter_positions() -> void:
	_scatter_positions = PackedVector3Array()
	_scatter_positions.resize(_surface_points.size())
	for i in range(_surface_points.size()):
		_scatter_positions[i] = (
			_surface_points[i]
			+ Vector3(
				randf_range(-scatter_radius, scatter_radius),
				randf_range(0.2, scatter_radius),
				randf_range(-scatter_radius, scatter_radius)
			)
		)


func _setup_multimesh() -> void:
	# Use a QuadMesh so particles face the camera (billboard) and can have a
	# soft radial falloff for a blurred glow look.
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * particle_size
	var mat := ShaderMaterial.new()
	mat.shader = _make_particle_shader()
	quad.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = _surface_points.size()
	mm.mesh = quad
	_multimesh = mm

	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.visible = false
	# Use top_level so particle positions stay in world-space regardless of
	# the structure's transform (surface points are sampled in world-space).
	_mmi.top_level = true
	add_child(_mmi)


func _make_particle_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

void vertex() {
	// Billboard: make quad always face camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz), 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz), 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
}

void fragment() {
	// Soft radial falloff from centre of quad for a blur / glow look.
	float dist = length(UV - vec2(0.5));
	float soft = 1.0 - smoothstep(0.0, 0.5, dist);
	float a = COLOR.a * soft;
	ALBEDO = COLOR.rgb;
	ALPHA = a;
}
"""
	return s


# ---------------------------------------------------------------------------
# Internal: per-frame update
# ---------------------------------------------------------------------------


func _apply_progress() -> void:
	# Update model shader.
	for smat in _surface_mats:
		smat.set_shader_parameter("progress", _progress)

	# Update particles.
	if _multimesh == null or _surface_points.is_empty():
		return

	var y_range := maxf(_y_max - _y_min, 0.001)

	if assembling:
		_apply_progress_assemble(y_range)
	else:
		_apply_progress_dissolve(y_range)


## Build direction (progress 1→0): model assembles from scattered particles.
func _apply_progress_assemble(y_range: float) -> void:
	if _progress <= 0.0:
		_mmi.visible = false
		return
	_mmi.visible = true

	# Fade particles out as the model finishes assembling (progress → 0).
	var fade_out := smoothstep(0.0, 0.15, _progress)

	for i in range(_surface_points.size()):
		var pos := _surface_points[i].lerp(_scatter_positions[i], _progress)
		_multimesh.set_instance_transform(i, Transform3D(Basis(), pos))

		# Top particles (high y_norm) settle first → higher threshold → fade out sooner.
		var y_norm := clampf((_surface_points[i].y - _y_min) / y_range, 0.0, 1.0)
		var settle_threshold := 0.1 + y_norm * 0.6
		var local_alpha := smoothstep(settle_threshold, settle_threshold + 0.15, _progress)
		var a := fade_out * local_alpha
		_multimesh.set_instance_color(
			i, Color(particle_color.r, particle_color.g, particle_color.b, a)
		)


## Sell direction (progress 0→1): model dissolves into scattered particles.
func _apply_progress_dissolve(y_range: float) -> void:
	if _progress >= 1.0:
		_mmi.visible = false
		return
	_mmi.visible = true

	var sweep_start := 0.05
	var sweep_width := 1.25

	for i in range(_surface_points.size()):
		var pos := _surface_points[i].lerp(_scatter_positions[i], _progress)
		_multimesh.set_instance_transform(i, Transform3D(Basis(), pos))

		var y_norm := clampf((_surface_points[i].y - _y_min) / y_range, 0.0, 1.0)
		var local_threshold := sweep_start + (1.0 - y_norm) * sweep_width * 0.5
		var local_alpha := 1.0 - smoothstep(local_threshold, local_threshold + 0.15, _progress)
		var fade_in := smoothstep(0.0, 0.1, _progress)
		var a := fade_in * local_alpha
		_multimesh.set_instance_color(
			i, Color(particle_color.r, particle_color.g, particle_color.b, a)
		)
