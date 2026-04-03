@tool
extends Node3D
## Applies a dissolve teleport effect to all MeshInstance3D children of the target node.
## Drives shader progress + GPUParticles3D emission.

@export var target_path: NodePath
@export var duration: float = 1.5
@export var edge_color: Color = Color(0.3, 0.8, 1.0)
@export var edge_intensity: float = 6.0
@export var particle_color: Color = Color(0.3, 0.8, 1.0)
@export var auto_play: bool = true
@export var loop: bool = true
@export var pause_between: float = 1.0

var _progress: float = 0.0
var _playing: bool = false
var _dissolving: bool = true  # true = disappearing, false = appearing
var _paused: bool = false
var _pause_timer: float = 0.0
var _original_materials: Dictionary = {}  # MeshInstance3D -> Array[Material]
var _overlay_materials: Array = []  # Array[ShaderMaterial]
var _particles: GPUParticles3D = null

const TELEPORT_SHADER = preload("res://source/shaders/3d/teleport_dissolve.gdshader")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_setup_particles()
	_apply_overlay_materials()
	if auto_play:
		play()


func play() -> void:
	_progress = 0.0
	_dissolving = true
	_playing = true
	_paused = false
	_set_progress(0.0)
	if _particles:
		_particles.emitting = true


func stop() -> void:
	_playing = false
	_paused = false
	_set_progress(0.0)
	if _particles:
		_particles.emitting = false


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _playing:
		return

	if _paused:
		_pause_timer -= delta
		if _pause_timer <= 0.0:
			_paused = false
			_dissolving = not _dissolving
			if _particles:
				_particles.emitting = true
		return

	var speed := 1.0 / maxf(duration, 0.01)
	if _dissolving:
		_progress += delta * speed
		if _progress >= 1.0:
			_progress = 1.0
			_set_progress(1.0)
			if _particles:
				_particles.emitting = false
			if loop:
				_paused = true
				_pause_timer = pause_between
			else:
				_playing = false
			return
	else:
		_progress -= delta * speed
		if _progress <= 0.0:
			_progress = 0.0
			_set_progress(0.0)
			if _particles:
				_particles.emitting = false
			if loop:
				_paused = true
				_pause_timer = pause_between
			else:
				_playing = false
			return

	_set_progress(_progress)


func _set_progress(value: float) -> void:
	for mat in _overlay_materials:
		mat.set_shader_parameter("progress", value)


func _get_target() -> Node:
	if target_path.is_empty():
		return get_parent()
	return get_node_or_null(target_path)


func _apply_overlay_materials() -> void:
	var target := _get_target()
	if target == null:
		return

	var meshes: Array = []
	if target is MeshInstance3D:
		meshes.append(target)
	meshes.append_array(target.find_children("*", "MeshInstance3D", true, false))

	for mesh: MeshInstance3D in meshes:
		for surface_id in range(mesh.mesh.get_surface_count()):
			var base_mat := mesh.get_active_material(surface_id)
			if base_mat == null:
				base_mat = mesh.mesh.surface_get_material(surface_id)

			var smat := ShaderMaterial.new()
			smat.shader = TELEPORT_SHADER
			smat.set_shader_parameter("progress", 0.0)
			smat.set_shader_parameter(
				"edge_color", Vector3(edge_color.r, edge_color.g, edge_color.b)
			)
			smat.set_shader_parameter("edge_intensity", edge_intensity)

			# Copy surface properties from the original material
			if base_mat is StandardMaterial3D:
				smat.set_shader_parameter("albedo_color", base_mat.albedo_color)
				if base_mat.albedo_texture != null:
					smat.set_shader_parameter("albedo_tex", base_mat.albedo_texture)
					smat.set_shader_parameter("has_albedo_tex", true)
				smat.set_shader_parameter("metallic", base_mat.metallic)
				if base_mat.metallic_texture != null:
					smat.set_shader_parameter("metallic_tex", base_mat.metallic_texture)
					smat.set_shader_parameter("has_metallic_tex", true)
					smat.set_shader_parameter(
						"metallic_tex_channel", base_mat.metallic_texture_channel
					)
				smat.set_shader_parameter("roughness", base_mat.roughness)
				if base_mat.roughness_texture != null:
					smat.set_shader_parameter("roughness_tex", base_mat.roughness_texture)
					smat.set_shader_parameter("has_roughness_tex", true)
					smat.set_shader_parameter(
						"roughness_tex_channel", base_mat.roughness_texture_channel
					)
				if base_mat.normal_enabled and base_mat.normal_texture != null:
					smat.set_shader_parameter("normal_tex", base_mat.normal_texture)
					smat.set_shader_parameter("has_normal_tex", true)

			mesh.set_surface_override_material(surface_id, smat)
			_overlay_materials.append(smat)


func _setup_particles() -> void:
	var target := _get_target()
	if target == null:
		return

	# Estimate bounding box from meshes
	var aabb := AABB()
	var meshes: Array = []
	if target is MeshInstance3D:
		meshes.append(target)
	meshes.append_array(target.find_children("*", "MeshInstance3D", true, false))
	for i in range(meshes.size()):
		var m: MeshInstance3D = meshes[i]
		var mesh_aabb := m.get_aabb()
		mesh_aabb.position += m.position
		if i == 0:
			aabb = mesh_aabb
		else:
			aabb = aabb.merge(mesh_aabb)

	_particles = GPUParticles3D.new()
	_particles.amount = 200
	_particles.lifetime = 1.0
	_particles.emitting = false
	_particles.one_shot = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5
	mat.gravity = Vector3(0, 0.5, 0)
	mat.scale_min = 0.02
	mat.scale_max = 0.06
	mat.color = particle_color
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = aabb.size * 0.5
	_particles.process_material = mat

	# Simple quad mesh for particles
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_color = particle_color
	draw_mat.emission_enabled = true
	draw_mat.emission = particle_color
	draw_mat.emission_energy_multiplier = 4.0
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.no_depth_test = true
	quad.material = draw_mat
	_particles.draw_pass_1 = quad

	_particles.position = aabb.get_center()
	add_child(_particles)
