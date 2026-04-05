class_name ForestVine

extends Area3D

const VineArcScript = preload("res://source/factions/neutral/structures/ResourceNode/VineArc.gd")

## Maximum distance to spark arcs to neighbouring vines.
const ARC_RANGE := 1.0
## Min/max seconds between arc spawns.
const ARC_INTERVAL_MIN := 2
const ARC_INTERVAL_MAX := 4

## Speed multiplier applied to units inside the forest zone.
var forest_speed_multiplier: float = 0.5

## Sight range multiplier applied to units inside the forest zone.
var forest_sight_multiplier: float = 0.5

## Extra radius around the vine that counts as forest zone (added to footprint).
var forest_zone_padding: float = 0.5

var armor: Dictionary = {}

var hp: int = 0:
	set(value):
		hp = max(0, value)
		hp_changed.emit()
		if hp <= 0 and _alive:
			_die()
var hp_max: int = 0

signal hp_changed

var radius: float:
	get:
		var obs: Node = find_child("MovementObstacle")
		if obs != null:
			return obs.get("radius") as float
		return 0.0
var global_position_yless:
	get:
		return global_position * Vector3(1, 0, 1)
var id: int
var in_player_vision: bool = false

var _alive: bool = true
var _saved_id: int = -1
var _occupied_cell: Vector2i
var _footprint: Vector2i = Vector2i(2, 1)
var _forest_zone: Area3D = null
var _vehicle_nav_blocker: StaticBody3D = null
var _arc_timer: Timer = null
var _neighbours: Array[ForestVine] = []


func _ready():
	_parse_properties()
	if _saved_id >= 0:
		id = _saved_id
		EntityRegistry.entities[id] = self
		if EntityRegistry._next_id <= id:
			EntityRegistry._next_id = id + 1
	else:
		id = EntityRegistry.register(self)
	var map: Node = MatchGlobal.map
	if map != null:
		_occupied_cell = map.world_to_cell(global_position)
		map.occupy_area(_occupied_cell, _footprint, Enums.OccupationType.FOREST)
	_randomize_model_rotation()
	_create_forest_zone()
	_create_vehicle_nav_blocker()
	(func(): if is_instance_valid(self): _setup_arc_sparking()).call_deferred()


func _parse_properties():
	var props: Dictionary = UnitConstants.get_default_properties(scene_file_path)
	hp_max = props.get("hp_max", 10)
	hp = props.get("hp", hp_max)
	armor = props.get("armor", {})
	_footprint = props.get("footprint", Vector2i(2, 1))


func _randomize_model_rotation():
	var model := get_node_or_null("Geometry/Model")
	if model:
		model.rotation.y = randf() * TAU


func _exit_tree():
	_cleanup_forest_zone()
	if MatchGlobal.map != null:
		MatchGlobal.map.clear_area(_occupied_cell, _footprint)
	if _vehicle_nav_blocker != null:
		_vehicle_nav_blocker.remove_from_group("vehicle_terrain_navigation_input")
		MatchSignals.schedule_navigation_rebake.emit(NavigationConstants.Domain.TERRAIN_VEHICLE)


func _create_forest_zone():
	_forest_zone = Area3D.new()
	_forest_zone.name = "ForestZone"
	_forest_zone.collision_layer = 0
	_forest_zone.collision_mask = 1  # detect unit bodies
	_forest_zone.monitorable = false
	_forest_zone.monitoring = true
	_forest_zone.input_ray_pickable = false

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(
		_footprint.x + forest_zone_padding * 2.0, 1.0, _footprint.y + forest_zone_padding * 2.0
	)
	shape.shape = box
	shape.transform.origin.y = 0.5
	_forest_zone.add_child(shape)
	add_child(_forest_zone)

	_forest_zone.body_entered.connect(_on_forest_body_entered)
	_forest_zone.body_exited.connect(_on_forest_body_exited)


func _create_vehicle_nav_blocker():
	# StaticBody3D with a collision shape that the navmesh baker will parse
	# and carve out of the vehicle terrain nav map.
	_vehicle_nav_blocker = StaticBody3D.new()
	_vehicle_nav_blocker.name = "VehicleNavBlocker"
	_vehicle_nav_blocker.collision_layer = 2  # layer 2 — matches navmesh geometry_collision_mask
	_vehicle_nav_blocker.collision_mask = 0
	_vehicle_nav_blocker.input_ray_pickable = false

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_footprint.x, 1.0, _footprint.y)
	shape.shape = box
	shape.transform.origin.y = 0.5
	_vehicle_nav_blocker.add_child(shape)
	add_child(_vehicle_nav_blocker)

	_vehicle_nav_blocker.add_to_group("vehicle_terrain_navigation_input")
	MatchSignals.schedule_navigation_rebake.emit(NavigationConstants.Domain.TERRAIN_VEHICLE)


func _cleanup_forest_zone():
	# Restore any units still inside when this vine is freed.
	if _forest_zone == null:
		return
	for body in _forest_zone.get_overlapping_bodies():
		_remove_forest_debuff(body)


func _on_forest_body_entered(body: Node3D):
	if body.is_in_group("units") and "forest_zones_inside" in body:
		body.forest_zones_inside += 1
		body.forest_speed_multiplier = min(body.forest_speed_multiplier, forest_speed_multiplier)
		body.forest_sight_multiplier = min(body.forest_sight_multiplier, forest_sight_multiplier)


func _on_forest_body_exited(body: Node3D):
	_remove_forest_debuff(body)


func _remove_forest_debuff(body: Node3D):
	if body.is_in_group("units") and "forest_zones_inside" in body:
		body.forest_zones_inside = max(0, body.forest_zones_inside - 1)
		if body.forest_zones_inside == 0:
			body.forest_speed_multiplier = 1.0
			body.forest_sight_multiplier = 1.0


func _die():
	_alive = false
	EntityRegistry.unregister(self)
	queue_free()


# --- Arc sparking between neighbouring vines ---


func _setup_arc_sparking():
	if not is_inside_tree():
		return
	# Find nearby ForestVines once.
	for vine in get_tree().get_nodes_in_group("forest_vines"):
		if vine == self or not vine is ForestVine:
			continue
		if global_position.distance_to(vine.global_position) <= ARC_RANGE:
			_neighbours.append(vine)
	if _neighbours.is_empty():
		return
	# Start a repeating timer with randomised interval.
	_arc_timer = Timer.new()
	_arc_timer.one_shot = true
	add_child(_arc_timer)
	_arc_timer.timeout.connect(_on_arc_timer)
	_schedule_next_arc()


func _schedule_next_arc():
	if _arc_timer == null:
		return
	_arc_timer.wait_time = randf_range(ARC_INTERVAL_MIN, ARC_INTERVAL_MAX)
	_arc_timer.start()


func _on_arc_timer():
	if not is_inside_tree() or _neighbours.is_empty():
		return
	# Pick a random neighbour that's still alive.
	var valid: Array[ForestVine] = []
	for n in _neighbours:
		if is_instance_valid(n) and n.is_inside_tree():
			valid.append(n)
	_neighbours = valid
	if _neighbours.is_empty():
		return
	var target: ForestVine = _neighbours[randi() % _neighbours.size()]
	_spawn_arc_to(target)
	_schedule_next_arc()


func _spawn_arc_to(target: ForestVine):
	# Random point near the top of each vine mesh for variety.
	var from_pos := (
		global_position
		+ Vector3(randf_range(-0.3, 0.3), randf_range(0.2, 0.6), randf_range(-0.3, 0.3))
	)
	var to_pos := (
		target.global_position
		+ Vector3(randf_range(-0.3, 0.3), randf_range(0.2, 0.6), randf_range(-0.3, 0.3))
	)
	var arc := MeshInstance3D.new()
	arc.set_script(VineArcScript)
	# Parent to Match so the arc outlives either vine if freed mid-flash.
	var match_node := find_parent("Match")
	if match_node:
		match_node.add_child(arc)
	else:
		get_tree().current_scene.add_child(arc)
	arc.setup(from_pos, to_pos)
