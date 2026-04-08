extends StaticBody3D

## Minimum screen-pixel distance for a right-click to count as a drag
## rather than a plain click.
const _DRAG_THRESHOLD_PX := 8.0

@onready var _collision_shape = find_child("CollisionShape3D")

## Separate flat-plane body used only for navmesh baking.
## Stays at y=0 so the navmesh remains one connected surface.
var _nav_body: StaticBody3D = null

var _rclick_start_screen: Vector2 = Vector2.ZERO
var _rclick_start_world: Vector3 = Vector3.ZERO
var _rclick_dragging: bool = false


func _ready():
	input_event.connect(_on_input_event)


func update_shape_from_map_size(map_size: Vector2):
	var plane := PlaneMesh.new()
	plane.size = map_size
	plane.center_offset = Vector3(map_size.x / 2.0, 0.0, map_size.y / 2.0)
	_collision_shape.shape = plane.create_trimesh_shape()
	if not is_in_group("terrain_navigation_input"):
		add_to_group("terrain_navigation_input")


const _CELL_SLOPE := 3
const _CELL_WATER_SLOPE := 4


func update_shape_from_map(map) -> void:
	"""Build a height-aware collision mesh from the map's height grid.
	Non-slope cells get flat quads at their cell height.
	Slope cells get smooth ramp triangles computed from their position
	within the contiguous slope region, so the navmesh sees a continuous
	surface from ground through the ramp to high ground."""
	var sx: int = int(map.size.x)
	var sy: int = int(map.size.y)

	if map.height_grid.is_empty():
		update_shape_from_map_size(map.size)
		return

	# Pre-compute slope region data so each slope cell knows its ramp params
	var slope_data: Dictionary = {}  # Vector2i -> Dictionary
	var visited: Dictionary = {}

	for z in range(sy):
		for x in range(sx):
			var pos := Vector2i(x, z)
			if visited.has(pos):
				continue
			var ct: int = map.get_cell_type_at_cell(pos)
			if ct != _CELL_SLOPE and ct != _CELL_WATER_SLOPE:
				continue

			# Flood-fill the contiguous slope region
			var region: Array[Vector2i] = []
			var stack: Array[Vector2i] = [pos]
			var region_set: Dictionary = {}
			while stack.size() > 0:
				var p: Vector2i = stack.pop_back()
				if visited.has(p) or region_set.has(p):
					continue
				if p.x < 0 or p.x >= sx or p.y < 0 or p.y >= sy:
					continue
				var pct: int = map.get_cell_type_at_cell(p)
				if pct != ct:
					continue
				visited[p] = true
				region_set[p] = true
				region.append(p)
				for d: Vector2i in [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
				]:
					stack.append(p + d)

			# Compute dominant direction and height range from boundary neighbours
			var total_diff := Vector2.ZERO
			var low_h: float = INF
			var high_h: float = -INF
			for p: Vector2i in region:
				var my_h: float = map.get_height_at_cell(p)
				for d: Vector2i in [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
				]:
					var n: Vector2i = p + d
					if n.x < 0 or n.x >= sx or n.y < 0 or n.y >= sy:
						continue
					if region_set.has(n):
						continue
					var nh: float = map.get_height_at_cell(n)
					total_diff += Vector2(d.x, d.y) * (nh - my_h)
					low_h = minf(low_h, nh)
					high_h = maxf(high_h, nh)

			if low_h == INF:
				low_h = 0.0
			if high_h == -INF:
				high_h = 0.0

			var direction: Vector2i
			if total_diff.length_squared() < 0.001:
				direction = Vector2i(1, 0)
			elif absf(total_diff.x) >= absf(total_diff.y):
				direction = Vector2i(1, 0) if total_diff.x > 0 else Vector2i(-1, 0)
			else:
				direction = Vector2i(0, 1) if total_diff.y > 0 else Vector2i(0, -1)

			# Region extent along ramp axis
			var rmin: int = 999999
			var rmax: int = -999999
			for p: Vector2i in region:
				var coord: int = p.x if abs(direction.x) > 0 else p.y
				rmin = mini(rmin, coord)
				rmax = maxi(rmax, coord)

			for p: Vector2i in region:
				slope_data[p] = {
					"low_h": low_h,
					"high_h": high_h,
					"dir": direction,
					"rmin": rmin,
					"rmax": rmax,
				}

	# Build collision triangles
	var faces := PackedVector3Array()
	faces.resize(sx * sy * 6)
	var idx: int = 0

	for z in range(sy):
		for x in range(sx):
			var pos := Vector2i(x, z)
			var fx: float = float(x)
			var fz: float = float(z)
			var h00: float
			var h10: float
			var h01: float
			var h11: float

			if slope_data.has(pos):
				var sd: Dictionary = slope_data[pos]
				var lh: float = sd.low_h
				var hh: float = sd.high_h
				var dir: Vector2i = sd.dir
				var span: float = float(sd.rmax - sd.rmin + 1)

				if abs(dir.x) > 0:
					var t0: float = float(x - sd.rmin) / span
					var t1: float = float(x + 1 - sd.rmin) / span
					if dir.x < 0:
						t0 = 1.0 - t0
						t1 = 1.0 - t1
					h00 = lerpf(lh, hh, t0)
					h10 = lerpf(lh, hh, t1)
					h01 = lerpf(lh, hh, t0)
					h11 = lerpf(lh, hh, t1)
				else:
					var t0: float = float(z - sd.rmin) / span
					var t1: float = float(z + 1 - sd.rmin) / span
					if dir.y < 0:
						t0 = 1.0 - t0
						t1 = 1.0 - t1
					h00 = lerpf(lh, hh, t0)
					h10 = lerpf(lh, hh, t0)
					h01 = lerpf(lh, hh, t1)
					h11 = lerpf(lh, hh, t1)
			else:
				var h: float = map.get_height_at_cell(pos)
				h00 = h
				h10 = h
				h01 = h
				h11 = h

			faces[idx] = Vector3(fx, h00, fz)
			faces[idx + 1] = Vector3(fx + 1.0, h10, fz)
			faces[idx + 2] = Vector3(fx, h01, fz + 1.0)
			faces[idx + 3] = Vector3(fx + 1.0, h10, fz)
			faces[idx + 4] = Vector3(fx + 1.0, h11, fz + 1.0)
			faces[idx + 5] = Vector3(fx, h01, fz + 1.0)
			idx += 6

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	_collision_shape.shape = shape

	# This height-aware shape is for mouse raycasting only — keep it OUT of
	# the navigation group so the navmesh stays flat and fully connected.
	if is_in_group("terrain_navigation_input"):
		remove_from_group("terrain_navigation_input")

	# Create a separate flat ground-plane body in the navigation group
	# so the navmesh bake has a walkable surface (cliff walls carve it).
	_ensure_nav_plane(map.size)


func _ensure_nav_plane(map_size: Vector2) -> void:
	"""Create (or update) a flat StaticBody3D at y=0 solely for navmesh baking."""
	if _nav_body != null and is_instance_valid(_nav_body):
		_nav_body.queue_free()

	_nav_body = StaticBody3D.new()
	_nav_body.name = "NavGroundPlane"
	_nav_body.collision_layer = 2
	_nav_body.collision_mask = 0
	_nav_body.input_ray_pickable = false
	_nav_body.add_to_group("terrain_navigation_input")

	var plane := PlaneMesh.new()
	plane.size = map_size
	plane.center_offset = Vector3(map_size.x / 2.0, 0.0, map_size.y / 2.0)

	var col := CollisionShape3D.new()
	col.shape = plane.create_trimesh_shape()
	_nav_body.add_child(col)
	add_child(_nav_body)


func _on_input_event(_camera, event, click_position, _click_normal, _shape_idx):
	if not event is InputEventMouseButton:
		return

	var is_right_click = event.button_index == MOUSE_BUTTON_RIGHT
	var is_left_click = event.button_index == MOUSE_BUTTON_LEFT
	var command_mode_active = MatchSignals.active_command_mode != Enums.UnitCommandMode.NORMAL

	# ── Left-click in command mode: instant targeted (no drag) ──
	if is_left_click and command_mode_active and event.pressed:
		MatchSignals.terrain_targeted.emit(click_position)
		return

	# ── Right-click press: begin potential drag ──
	if is_right_click and event.pressed:
		_rclick_start_screen = event.position
		_rclick_start_world = click_position
		_rclick_dragging = true
		return

	# ── Right-click release: finish click or drag ──
	if is_right_click and not event.pressed:
		if not _rclick_dragging:
			MatchSignals.unit_targeted_this_click = false
			return
		_rclick_dragging = false
		var suppressed := MatchSignals.unit_targeted_this_click
		MatchSignals.unit_targeted_this_click = false
		var drag_dist: float = event.position.distance_to(_rclick_start_screen)
		if drag_dist < _DRAG_THRESHOLD_PX:
			# Tiny movement → treat as a normal click.
			if not suppressed:
				MatchSignals.terrain_targeted.emit(_rclick_start_world)
		else:
			MatchSignals.terrain_drag_finished.emit(_rclick_start_world, click_position)
		return


func _unhandled_input(event: InputEvent) -> void:
	if not _rclick_dragging:
		return
	if event is InputEventMouseMotion:
		var screen_pos: Vector2 = event.position
		if screen_pos.distance_to(_rclick_start_screen) < _DRAG_THRESHOLD_PX:
			return
		var current_world = _world_pos_from_mouse(screen_pos)
		if current_world != null:
			MatchSignals.terrain_drag_updated.emit(_rclick_start_world, current_world)
	# Cancel drag if right button released outside the collision body
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and not event.pressed
	):
		if _rclick_dragging:
			_rclick_dragging = false
			var suppressed := MatchSignals.unit_targeted_this_click
			MatchSignals.unit_targeted_this_click = false
			var end_world = _world_pos_from_mouse(event.position)
			if end_world != null:
				var drag_dist: float = event.position.distance_to(_rclick_start_screen)
				if drag_dist < _DRAG_THRESHOLD_PX:
					if not suppressed:
						MatchSignals.terrain_targeted.emit(_rclick_start_world)
				else:
					MatchSignals.terrain_drag_finished.emit(_rclick_start_world, end_world)


func _world_pos_from_mouse(screen_pos: Vector2) -> Variant:
	var camera = get_viewport().get_camera_3d()
	var match_node = get_parent()
	var map = match_node.map if match_node != null else null
	return camera.get_terrain_ray_intersection(screen_pos, map)
