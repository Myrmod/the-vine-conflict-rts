extends Node3D

## Speed of the animation (full cycle per second, e.g. 0.2 = 5 seconds).
@export var sweep_speed: float = 0.2
## Number of particle cubes sampled from the model surface.
@export var particle_count: int = 600
## Side length of each particle cube in world units.
@export var particle_size: float = 0.07
## Max distance particles scatter away from the model.
@export var scatter_radius: float = 3.0
## Emissive colour of the particles.
@export var particle_color: Color = Color(0.3, 0.9, 1.0)

const FADE_SHADER = preload("res://tests/manual/TeleportShaderTest.gdshader")

var _progress: float = 0.0
var _direction: float = 1.0  # 1 = dissolve out, -1 = assemble in
var _surface_mats: Array[ShaderMaterial] = []
var _multimesh: MultiMesh = null
var _mmi: MultiMeshInstance3D = null
var _y_min: float = 0.0
var _y_max: float = 1.0
var _surface_points: PackedVector3Array
var _scatter_positions: PackedVector3Array


func _ready() -> void:
	var pillar := find_child("Amuns_Wall_Pillar2", true, false)
	if pillar == null:
		return

	var meshes := pillar.find_children("*", "MeshInstance3D", true, false)

	# --- Y bounds for shader ---
	var y_min := INF
	var y_max := -INF
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
					y_min = minf(y_min, world_y)
					y_max = maxf(y_max, world_y)

	# --- Apply fade shader to all surfaces ---
	_y_min = y_min
	_y_max = y_max
	for mesh: MeshInstance3D in meshes:
		for surface_id in range(mesh.mesh.get_surface_count()):
			var smat := ShaderMaterial.new()
			smat.shader = FADE_SHADER
			smat.set_shader_parameter("progress", 0.0)
			smat.set_shader_parameter("y_min", y_min)
			smat.set_shader_parameter("y_max", y_max)
			mesh.set_surface_override_material(surface_id, smat)
			_surface_mats.append(smat)

	# --- Sample surface points and build particle system ---
	_surface_points = _sample_surface_points(meshes, particle_count)
	_build_scatter_positions()
	_setup_multimesh()
	_apply()


## Weighted-random surface sampling across all meshes.
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


## Randomise scatter destinations (called on each left-click for variety).
func _build_scatter_positions() -> void:
	_scatter_positions = PackedVector3Array()
	_scatter_positions.resize(_surface_points.size())
	for i in range(_surface_points.size()):
		_scatter_positions[i] = (
			_surface_points[i]
			+ Vector3(
				randf_range(-scatter_radius, scatter_radius),
				randf_range(0.5, scatter_radius),
				randf_range(-scatter_radius, scatter_radius)
			)
		)


func _setup_multimesh() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * particle_size

	# ShaderMaterial so emission is multiplied by instance colour alpha.
	# StandardMaterial3D emission ignores alpha entirely.
	var mat := ShaderMaterial.new()
	mat.shader = _make_particle_shader()
	mat.set_shader_parameter("emission_color", particle_color)
	mat.set_shader_parameter("emission_energy", 4.0)
	box.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = _surface_points.size()
	mm.mesh = box
	_multimesh = mm

	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	add_child(_mmi)


func _make_particle_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;
uniform vec3 emission_color : source_color = vec3(0.3, 0.9, 1.0);
uniform float emission_energy = 4.0;
void fragment() {
    // COLOR is the per-instance colour set via set_instance_color().
    // alpha drives both transparency and emission brightness.
    float a = COLOR.a;
    ALBEDO = emission_color * emission_energy * a;
    ALPHA = a;
}
"""
	return s


func _process(delta: float) -> void:
	_progress = clampf(_progress + delta * sweep_speed * _direction, 0.0, 1.0)
	_apply()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Dissolve out — regenerate scatter targets for variety.
			_progress = 0.0
			_direction = 1.0
			_build_scatter_positions()
			_apply()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Assemble in from current progress.
			_direction = -1.0


func _apply() -> void:
	for smat in _surface_mats:
		smat.set_shader_parameter("progress", _progress)
	_update_multimesh()


func _update_multimesh() -> void:
	if _multimesh == null or _surface_points.is_empty():
		return
	# Hide entirely at endpoints so zero-alpha emission cannot bleed through bloom.
	if _progress <= 0.0 or _progress >= 1.0:
		_mmi.visible = false
		return
	_mmi.visible = true

	# Spread of the particle sweep: particle fade lags behind the model (slower).
	# Each particle's fade is offset by its normalised Y: top particles fade first.
	var y_range := maxf(_y_max - _y_min, 0.001)
	# Sweep band: particles start fading at sweep_start and finish at sweep_end.
	# Use a wider range (0 to 1.3) so the slowest (bottom) particles fully disappear.
	var sweep_start := 0.3  # progress at which top particles begin fading
	var sweep_width := 1.25  # total progress range for the full top-to-bottom sweep

	for i in range(_surface_points.size()):
		var pos := _surface_points[i].lerp(_scatter_positions[i], _progress)
		_multimesh.set_instance_transform(i, Transform3D(Basis(), pos))

		# y_norm: 1 = top, 0 = bottom (top fades first)
		var y_norm := clampf((_surface_points[i].y - _y_min) / y_range, 0.0, 1.0)
		# Each particle gets its own fade progress offset by its height.
		# Top particles (y_norm=1) start fading at progress=sweep_start.
		# Bottom particles (y_norm=0) start fading at progress=sweep_start+sweep_width*0.5.
		var local_threshold := sweep_start + (1.0 - y_norm) * sweep_width * 0.5
		var local_alpha := 1.0 - smoothstep(local_threshold, local_threshold + 0.15, _progress)
		# Also keep global fade-in so particles don't pop at the very start.
		var fade_in := smoothstep(0.0, 0.1, _progress)
		var a := fade_in * local_alpha
		_multimesh.set_instance_color(
			i, Color(particle_color.r, particle_color.g, particle_color.b, a)
		)
