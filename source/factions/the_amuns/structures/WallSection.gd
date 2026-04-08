extends Node3D

## References to the two WallPillars this section connects.
var pillar_a: Node = null
var pillar_b: Node = null


## Configure the section's mesh and obstacle to span between two pillars.
func setup(a: Node, b: Node, shield_color: Color = Color(0.26, 0.975, 1.0)) -> void:
	pillar_a = a
	pillar_b = b
	_apply_shield_color(shield_color)

	var pos_a: Vector3 = a.global_position * Vector3(1, 0, 1)
	var pos_b: Vector3 = b.global_position * Vector3(1, 0, 1)
	var midpoint: Vector3 = (pos_a + pos_b) / 2.0
	midpoint.y = (a.global_position.y + b.global_position.y) / 2.0
	var full_distance: float = pos_a.distance_to(pos_b)
	var direction: Vector3 = (pos_b - pos_a).normalized()

	# Span center-to-center
	var section_length := maxf(full_distance, 0.1)

	global_position = midpoint
	# Rotate so local -Z points from A to B
	if direction.length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)

	_resize_model(section_length)
	_resize_obstacle(section_length)


func trigger_impact(hit_position: Vector3) -> void:
	var model := find_child("Model")
	if model != null and model.has_method("impact"):
		# Randomize the Y position across the shield height
		var pos := hit_position
		pos.y += randf_range(0.0, 1.0)
		model.impact(pos)


func _apply_shield_color(c: Color) -> void:
	var model := find_child("Model")
	if model == null:
		return
	if model.has_method("update_material"):
		model.update_material("_color_shield", Color(c.r, c.g, c.b))
	else:
		var mat := (model as MeshInstance3D).get_active_material(0) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("_color_shield", Color(c.r, c.g, c.b))
	var top_edge := find_child("TopEdge") as MeshInstance3D
	if top_edge != null:
		var top_mat := top_edge.get_active_material(0) as StandardMaterial3D
		if top_mat != null:
			top_mat.albedo_color = c


func _resize_model(length: float) -> void:
	var model := find_child("Model") as MeshInstance3D
	if model == null:
		return
	# PlaneMesh lies flat (Y-up). look_at points -Z toward pillar B.
	# Scale Z for length along connection, X for width.
	model.scale = Vector3(1.0, 1.0, length)
	var top_edge := find_child("TopEdge") as MeshInstance3D
	if top_edge != null:
		top_edge.scale = Vector3(1.0, 1.0, length)


func _process(_delta: float) -> void:
	var top_edge := find_child("TopEdge") as MeshInstance3D
	if top_edge == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		top_edge.visible = false
		return
	# Wall faces along local X (perpendicular to the connection axis).
	# Show TopEdge when the camera looks along the wall (shield is edge-on).
	var wall_normal := global_transform.basis.x.normalized()
	var to_cam := cam.global_position - global_position
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.001:
		top_edge.visible = false
		return
	var dot := absf(wall_normal.dot(to_cam.normalized()))
	# dot ~1 = camera facing the wall (shield visible) → hide edge
	# dot ~0 = camera along the wall (shield edge-on) → show edge
	top_edge.visible = dot < 0.5


func _resize_obstacle(length: float) -> void:
	var obstacle := find_child("MovementObstacle") as NavigationObstacle3D
	if obstacle == null:
		return
	var half_len := length / 2.0
	var half_width := 0.5
	obstacle.vertices = PackedVector3Array(
		[
			Vector3(-half_width, 0, -half_len),
			Vector3(half_width, 0, -half_len),
			Vector3(half_width, 0, half_len),
			Vector3(-half_width, 0, half_len),
		]
	)
