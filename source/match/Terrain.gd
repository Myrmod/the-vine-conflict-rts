extends StaticBody3D

@onready var _collision_shape = find_child("CollisionShape3D")


func _ready():
	input_event.connect(_on_input_event)


func update_shape_from_map_size(map_size: Vector2):
	var plane := PlaneMesh.new()
	plane.size = map_size
	plane.center_offset = Vector3(map_size.x / 2.0, 0.0, map_size.y / 2.0)
	_collision_shape.shape = plane.create_trimesh_shape()
	# Add to navmesh source group so the flat collision plane is baked into
	# the navigation mesh. Using the collision shape (instead of the visual
	# TerrainMesh) avoids GPU→CPU readback and keeps the navmesh flat at
	# Y=0 — water cells stay navigable regardless of visual displacement.
	if not is_in_group("terrain_navigation_input"):
		add_to_group("terrain_navigation_input")


func _on_input_event(_camera, event, _click_position, _click_normal, _shape_idx):
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		var camera = get_viewport().get_camera_3d()
		var match_node = get_parent()
		var map = match_node.map if match_node != null else null
		var target_point = camera.get_terrain_ray_intersection(event.position, map)
		if target_point != null:
			MatchSignals.terrain_targeted.emit(target_point)
