extends Node3D

@export var player_color: Color = Color(0.2, 0.8, 1.0)
@export var teleporter_rotation_speed: float = 1.0  # radians per second

const TELEPORTER_SHADER = preload("res://tests/manual/TriangleAssemblyTest.gdshader")

var _teleporter: Node3D = null


func _ready() -> void:
	var model := find_child("Amuns_Wall_Pillar", true, false)
	if model == null:
		return

	var meshes := _collect_meshes(model)
	if meshes.is_empty():
		return

	var xz_radius := _compute_xz_radius(meshes)
	var model_center := _compute_xz_center(meshes)

	var teleporter := find_child("Teleporter", true, false)
	if teleporter != null:
		_teleporter = teleporter as Node3D
		_apply_teleporter_materials(teleporter)
		_setup_teleporter(_teleporter, model_center, xz_radius)


func _process(delta: float) -> void:
	if _teleporter != null:
		_teleporter.rotate_y(teleporter_rotation_speed * delta)


func _collect_meshes(target: Node3D) -> Array:
	var meshes: Array = []
	if target is MeshInstance3D:
		meshes.append(target)
	meshes.append_array(target.find_children("*", "MeshInstance3D", true, false))
	return meshes


func _compute_xz_radius(meshes: Array) -> float:
	var max_r := 0.0
	for m: MeshInstance3D in meshes:
		var aabb := m.get_aabb()
		for xi in range(2):
			for zi in range(2):
				var corner := aabb.position + Vector3(aabb.size.x * xi, 0.0, aabb.size.z * zi)
				var wp: Vector3 = m.global_transform * corner
				var r := Vector2(wp.x, wp.z).length()
				max_r = maxf(max_r, r)
	return max_r


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


func _setup_teleporter(teleporter: Node3D, model_center: Vector2, xz_radius: float) -> void:
	var ref_radius := maxf(xz_radius, 0.01)
	var tp_scale := 0.1 * (1.0 / ref_radius)
	teleporter.scale = Vector3(tp_scale, 1.0, tp_scale)
	teleporter.global_position = Vector3(
		model_center.x, teleporter.global_position.y, model_center.y
	)


func _apply_teleporter_materials(teleporter: Node) -> void:
	var meshes := _collect_meshes(teleporter as Node3D)
	for mesh: MeshInstance3D in meshes:
		for surface_id in range(mesh.mesh.get_surface_count()):
			var source_mat := mesh.get_active_material(surface_id)
			var mat_name := ""
			if source_mat != null:
				mat_name = source_mat.resource_name

			var smat := ShaderMaterial.new()
			smat.shader = TELEPORTER_SHADER
			smat.set_shader_parameter("player_color", player_color)

			if mat_name == "PlayerColor":
				smat.set_shader_parameter("alpha", 1.0)
				smat.set_shader_parameter("emission_strength", 3.0)
			else:
				smat.set_shader_parameter("alpha", 0.15)
				smat.set_shader_parameter("emission_strength", 0.0)

			mesh.set_surface_override_material(surface_id, smat)
