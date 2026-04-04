extends "res://source/factions/the_amuns/AmunStructure.gd"

## Arm local directions in the GLB's coordinate space (post-export).
## Blender +X/−X → Godot local +X/−X; Blender +Y/−Y → Godot local −Z/+Z.
const ARM_LOCAL_DIRECTIONS := {
	"arms_xp": Vector3(1, 0, 0),
	"arms_xn": Vector3(-1, 0, 0),
	"arms_yp": Vector3(0, 0, -1),
	"arms_yn": Vector3(0, 0, 1),
}

var wall_sections: Array = []
var connection_length: float = 0.0

var _cached_wall_section_scene: PackedScene = null


## Resolve the WallSection scene path relative to this pillar's script path.
func _get_wall_section_scene() -> PackedScene:
	if _cached_wall_section_scene == null:
		var dir = get_script().resource_path.get_base_dir()
		_cached_wall_section_scene = load(dir + "/WallSection.tscn")
	return _cached_wall_section_scene


func _finish_construction():
	super()
	_hide_all_arms()
	_connect_to_nearby_pillars()
	_update_arm_visibility()
	hp_changed.connect(_on_hp_changed_ripple)


func _setup_color():
	super()
	var holder := find_child("ModelHolder")
	if holder == null or player == null:
		return
	var player_mat: Material = player.get_color_material()
	for mesh in holder.find_children("*", "MeshInstance3D", true, false):
		for surface_id in range(mesh.mesh.get_surface_count()):
			var surface_mat: Material = mesh.get_active_material(surface_id)
			if surface_mat == null:
				continue
			if surface_mat.resource_name == "PlayerColor":
				mesh.set_surface_override_material(surface_id, player_mat)


func _exit_tree():
	_destroy_wall_sections()
	super()


## Find nearby constructed same-player WallPillars and spawn sections.
func _connect_to_nearby_pillars() -> void:
	if connection_length <= 0.0:
		return
	for unit in get_tree().get_nodes_in_group("units"):
		if unit == self:
			continue
		if not _is_wall_pillar(unit):
			continue
		if unit.player != player:
			continue
		if not unit.is_constructed():
			continue
		if not "connection_length" in unit or unit.connection_length <= 0.0:
			continue

		var dist := (global_position * Vector3(1, 0, 1)).distance_to(
			unit.global_position * Vector3(1, 0, 1)
		)
		var max_range := maxf(connection_length, unit.connection_length)
		if dist > max_range:
			continue
		if not FeatureFlags.allow_diagonal_wall_connections:
			if not _is_axis_aligned(global_position, unit.global_position):
				continue
		if _already_connected_to(unit):
			continue
		if not _has_clear_line(self, unit):
			continue

		_spawn_wall_section(unit)


## Check if this pillar is already connected to another via a section.
func _already_connected_to(other) -> bool:
	for section in wall_sections:
		if not is_instance_valid(section):
			continue
		if section.pillar_a == other or section.pillar_b == other:
			return true
	for section in other.wall_sections:
		if not is_instance_valid(section):
			continue
		if section.pillar_a == self or section.pillar_b == self:
			return true
	return false


## Deterministic LOS check: ensure no structures block the line between pillars.
func _has_clear_line(a: Node, b: Node) -> bool:
	var a_pos = a.global_position * Vector3(1, 0, 1)
	var b_pos = b.global_position * Vector3(1, 0, 1)

	for unit in get_tree().get_nodes_in_group("units"):
		if unit == a or unit == b:
			continue
		if not unit.has_method("is_constructed"):
			continue
		if not unit.is_constructed():
			continue
		var obstacle := unit.find_child("MovementObstacle") as NavigationObstacle3D
		if obstacle == null or not obstacle.affect_navigation_mesh:
			continue
		var unit_pos = unit.global_position * Vector3(1, 0, 1)
		var r = unit.radius if unit.radius != null else 0.5
		if _circle_intersects_segment(unit_pos, r, a_pos, b_pos):
			return false
	return true


## Test if a circle (pos, radius) intersects a line segment (seg_a, seg_b).
static func _circle_intersects_segment(
	circle_pos: Vector3, circle_radius: float, seg_a: Vector3, seg_b: Vector3
) -> bool:
	var d := seg_b - seg_a
	var f := seg_a - circle_pos
	var a := d.dot(d)
	if a < 0.0001:
		return f.length() <= circle_radius
	var b := 2.0 * f.dot(d)
	var c := f.dot(f) - circle_radius * circle_radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0:
		return false
	discriminant = sqrt(discriminant)
	var t1 := (-b - discriminant) / (2.0 * a)
	var t2 := (-b + discriminant) / (2.0 * a)
	# Check if either intersection is within the segment [0, 1]
	if t1 >= 0.0 and t1 <= 1.0:
		return true
	if t2 >= 0.0 and t2 <= 1.0:
		return true
	# Check if segment is entirely inside the circle
	if t1 < 0.0 and t2 > 1.0:
		return true
	return false


func _spawn_wall_section(other) -> void:
	var section := _get_wall_section_scene().instantiate()
	# Add to the match root (same level as players) to avoid coupling to player tree
	var match_node := find_parent("Match")
	if match_node == null:
		return
	match_node.add_child(section)
	section.setup(self, other, player.color)
	wall_sections.append(section)
	other.wall_sections.append(section)
	_update_arm_visibility()
	if other.has_method("_update_arm_visibility"):
		other._update_arm_visibility()


func _destroy_wall_sections() -> void:
	var sections_copy := wall_sections.duplicate()
	var neighbors: Array = []
	wall_sections.clear()
	for section in sections_copy:
		if not is_instance_valid(section):
			continue
		# Remove from the other pillar's tracking
		var other = section.pillar_b if section.pillar_a == self else section.pillar_a
		if is_instance_valid(other) and "wall_sections" in other:
			other.wall_sections.erase(section)
			if other.has_method("_update_arm_visibility"):
				other._update_arm_visibility()
			neighbors.append(other)
		section.queue_free()
	# After a delay, let neighbors try to reconnect to each other
	if neighbors.size() >= 2:
		_schedule_neighbor_reconnect(neighbors)


func _schedule_neighbor_reconnect(neighbors: Array) -> void:
	var target_tick: int = Match.tick + 30
	var callback_ref: Array = []
	var callback := func():
		if Match.tick < target_tick:
			return
		MatchSignals.tick_advanced.disconnect(callback_ref[0])
		for i in range(neighbors.size()):
			var a = neighbors[i]
			if not is_instance_valid(a) or not a.is_inside_tree():
				continue
			if not a.has_method("_connect_to_nearby_pillars"):
				continue
			a._connect_to_nearby_pillars()
			a._update_arm_visibility()
	callback_ref.append(callback)
	MatchSignals.tick_advanced.connect(callback)


func _on_hp_changed_ripple() -> void:
	for section in wall_sections:
		if is_instance_valid(section):
			section.trigger_impact(global_position)


func _is_wall_pillar(unit) -> bool:
	return "wall_sections" in unit and "connection_length" in unit


## Check if two positions are aligned on the X or Z axis (within grid tolerance).
static func _is_axis_aligned(a_pos: Vector3, b_pos: Vector3) -> bool:
	var tolerance := 0.1
	return absf(a_pos.x - b_pos.x) < tolerance or absf(a_pos.z - b_pos.z) < tolerance


## ---------------------------------------------------------------------------
## Arm visibility — show only arms that face a connected wall section.
## ---------------------------------------------------------------------------


func _find_arm_node(arm_name: String) -> Node3D:
	var holder := find_child("ModelHolder")
	if holder == null:
		return null
	return holder.find_child(arm_name, true, false)


func _hide_all_arms() -> void:
	for arm_name in ARM_LOCAL_DIRECTIONS:
		var arm := _find_arm_node(arm_name)
		if arm != null:
			arm.visible = false


func _update_arm_visibility() -> void:
	_hide_all_arms()

	var holder := find_child("ModelHolder") as Node3D
	if holder == null:
		return

	for section in wall_sections:
		if not is_instance_valid(section):
			continue
		var other = section.pillar_b if section.pillar_a == self else section.pillar_a
		if not is_instance_valid(other):
			continue
		var dir: Vector3 = other.global_position - global_position
		dir.y = 0.0
		if dir.length_squared() < 0.001:
			continue
		dir = dir.normalized()

		var best_name := ""
		var best_dot := -2.0
		for arm_name in ARM_LOCAL_DIRECTIONS:
			var world_dir: Vector3 = (
				(holder.global_transform.basis * ARM_LOCAL_DIRECTIONS[arm_name]).normalized()
			)
			world_dir.y = 0.0
			if world_dir.length_squared() < 0.001:
				continue
			world_dir = world_dir.normalized()
			var dot: float = world_dir.dot(dir)
			if dot > best_dot:
				best_dot = dot
				best_name = arm_name

		if not best_name.is_empty():
			var arm := _find_arm_node(best_name)
			if arm != null:
				arm.visible = true
