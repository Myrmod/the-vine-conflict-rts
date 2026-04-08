class_name CliffPlacer
extends Node3D

## Auto-places cliff meshes along terrain height edges using MultiMesh batching.
## Cliff .res files are loaded from assets_overide/RockPack1/ (or assets/ fallback).

# ── asset paths (relative to OVERRIDE_PREFIX / DEFAULT_PREFIX) ──────────
const OVERRIDE_PREFIX := "res://assets_overide/"
const DEFAULT_PREFIX := "res://assets/"

const CLIFF_MESH_PATHS: Array[String] = [
	"RockPack1/Models/meshes/Cliff_models_cliff1_mesh.res",
	"RockPack1/Models/meshes/Cliff_models_cliff3_mesh.res",
	"RockPack1/Models/meshes/Cliff_models_cliff4_mesh.res",
	"RockPack1/Models/meshes/Cliff_models_cliff6_mesh.res",
]

# Bounding-box Y from data/model_sizes.json — used to compute uniform scale.
const CLIFF_MODEL_HEIGHTS: Array[float] = [9.413, 9.157, 9.007, 9.369]

# Bounding-box Z (depth) — used to center the cliff across the cell boundary.
const CLIFF_MODEL_DEPTHS: Array[float] = [3.572, 3.794, 3.439, 5.639]

# Direction toward the LOW side → Y-rotation so the cliff face looks that way.
const DIR_ROT := {
	Vector2i(0, -1): 0.0,
	Vector2i(1, 0): -PI / 2.0,
	Vector2i(0, 1): PI,
	Vector2i(-1, 0): PI / 2.0,
}

const CARDINAL_DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

## Material applied to cliff meshes.  Relative to assets_overide/ (or assets/).
@export var material_path: String = "RockPack1/Materials/Cliff_Material_Photoscan.tres"

## Extra Y-rotation (radians) applied to every cliff instance.
## Tweak this if cliff faces point the wrong direction by default.
@export var facing_rotation_offset: float = 0.0

## Vertical shift applied to every cliff instance for alignment tuning.
@export var vertical_offset: float = 0.0

## Height differences smaller than this are ignored (skip micro-edges).
@export var min_height_diff: float = 0.5

## Random seed for deterministic mesh variant assignment.
@export var placement_seed: int = 12345

var _meshes: Array[Mesh] = []
var _mesh_aabb_centers: Array[Vector3] = []  # AABB center per mesh (model space)
var _material: Material
var _loaded := false

# ── public API ──────────────────────────────────────────────────────────


func update_cliffs(map: MapResource, map_size: Vector2i) -> void:
	_clear()
	if not _ensure_assets():
		return
	var edges := _collect_edges(map, map_size)
	if edges.is_empty():
		return
	_build_multimeshes(edges)


# ── internals ───────────────────────────────────────────────────────────


func _clear() -> void:
	for child in get_children():
		child.queue_free()


func _resolve(relative: String) -> String:
	for base: String in [OVERRIDE_PREFIX, DEFAULT_PREFIX]:
		var full: String = base + relative
		if ResourceLoader.exists(full):
			return full
	return ""


func _ensure_assets() -> bool:
	if _loaded:
		return not _meshes.is_empty()
	_loaded = true
	_meshes.clear()
	_mesh_aabb_centers.clear()

	for path in CLIFF_MESH_PATHS:
		var full := _resolve(path)
		if full.is_empty():
			continue
		var res = load(full)
		var mesh: Mesh = null
		if res is Mesh:
			mesh = res
		elif res is PackedScene:
			var inst := (res as PackedScene).instantiate()
			for child in inst.get_children():
				if child is MeshInstance3D and child.mesh:
					mesh = child.mesh
					break
			inst.queue_free()
		if mesh:
			_meshes.append(mesh)
			var aabb := mesh.get_aabb()
			_mesh_aabb_centers.append(aabb.position + aabb.size * 0.5)

	if _meshes.is_empty():
		push_warning("CliffPlacer: no cliff meshes found – skipping cliff placement.")
		return false

	if not material_path.is_empty():
		var mat_full := _resolve(material_path)
		if not mat_full.is_empty():
			_material = load(mat_full)

	return true


func _cell_type(map: MapResource, pos: Vector2i) -> int:
	if map.cell_type_grid.is_empty():
		return MapResource.CELL_GROUND
	var idx := pos.y * map.size.x + pos.x
	if idx < 0 or idx >= map.cell_type_grid.size():
		return MapResource.CELL_GROUND
	return map.cell_type_grid[idx]


func _collect_edges(map: MapResource, sz: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	# Pre-compute slope direction per cell so we can skip ramp-direction edges.
	var slope_dir_map := _compute_slope_directions(map, sz)

	for y in range(sz.y):
		for x in range(sz.x):
			var pos := Vector2i(x, y)
			var h := map.get_height_at(pos)
			var ct := _cell_type(map, pos)

			for dir: Vector2i in CARDINAL_DIRS:
				var n := pos + dir
				if n.x < 0 or n.x >= sz.x or n.y < 0 or n.y >= sz.y:
					continue
				var nh := map.get_height_at(n)

				var diff := h - nh
				if diff < min_height_diff:
					continue

				# For slope cells: only place cliffs on edges perpendicular
				# to the ramp direction (the sides), not along the ramp
				# (top/bottom where it connects to ground / high-ground).
				if ct == MapResource.CELL_SLOPE or ct == MapResource.CELL_WATER_SLOPE:
					if slope_dir_map.has(pos):
						var slope_axis: Vector2i = slope_dir_map[pos]
						# slope_axis is the ramp direction (e.g. (1,0)).
						# Skip if this edge is along the ramp axis.
						if absi(dir.x) == absi(slope_axis.x) and absi(dir.y) == absi(slope_axis.y):
							continue

				# Same check for the neighbour being a slope cell
				var nct := _cell_type(map, n)
				if nct == MapResource.CELL_SLOPE or nct == MapResource.CELL_WATER_SLOPE:
					if slope_dir_map.has(n):
						var slope_axis: Vector2i = slope_dir_map[n]
						if absi(dir.x) == absi(slope_axis.x) and absi(dir.y) == absi(slope_axis.y):
							continue

				(
					result
					. append(
						{
							"pos": pos,
							"dir": dir,
							"h_high": h,
							"h_low": nh,
						}
					)
				)

	return result


func _compute_slope_directions(map: MapResource, sz: Vector2i) -> Dictionary:
	"""Return a Dictionary mapping each slope cell (Vector2i) to its region's
	dominant ramp direction (Vector2i).  Uses flood-fill to group regions."""
	var result := {}
	var visited := {}

	for y in range(sz.y):
		for x in range(sz.x):
			var pos := Vector2i(x, y)
			if visited.has(pos):
				continue
			var ct := _cell_type(map, pos)
			if ct != MapResource.CELL_SLOPE and ct != MapResource.CELL_WATER_SLOPE:
				continue

			# Flood-fill the slope region
			var region: Array[Vector2i] = []
			var queue: Array[Vector2i] = [pos]
			visited[pos] = true
			while not queue.is_empty():
				var p: Vector2i = queue.pop_front()
				region.append(p)
				for d in CARDINAL_DIRS:
					var n := p + d
					if n.x < 0 or n.x >= sz.x or n.y < 0 or n.y >= sz.y:
						continue
					if visited.has(n):
						continue
					if _cell_type(map, n) == ct:
						visited[n] = true
						queue.append(n)

			# Compute dominant direction for this region
			var total_diff := Vector2.ZERO
			for p in region:
				var my_h: float = map.get_height_at(p)
				for d in CARDINAL_DIRS:
					var n := p + d
					if n.x < 0 or n.x >= sz.x or n.y < 0 or n.y >= sz.y:
						continue
					var nct := _cell_type(map, n)
					if nct == ct:
						continue  # same slope region — skip
					var diff: float = map.get_height_at(n) - my_h
					total_diff += Vector2(d.x, d.y) * diff

			var direction: Vector2i
			if total_diff.length_squared() < 0.001:
				direction = Vector2i(1, 0)
			elif absf(total_diff.x) >= absf(total_diff.y):
				direction = Vector2i(1, 0) if total_diff.x > 0 else Vector2i(-1, 0)
			else:
				direction = Vector2i(0, 1) if total_diff.y > 0 else Vector2i(0, -1)

			# Assign direction to every cell in the region
			for p in region:
				result[p] = direction

	return result


func _build_multimeshes(edges: Array[Dictionary]) -> void:
	var variant_count := _meshes.size()

	# Distribute edges deterministically across mesh variants
	var buckets: Array[Array] = []
	buckets.resize(variant_count)
	for i in variant_count:
		buckets[i] = []

	var rng := RandomNumberGenerator.new()
	rng.seed = placement_seed
	for edge in edges:
		buckets[rng.randi_range(0, variant_count - 1)].append(edge)

	for v in variant_count:
		if buckets[v].is_empty():
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[v]
		mm.instance_count = buckets[v].size()

		var model_h: float = CLIFF_MODEL_HEIGHTS[v] if v < CLIFF_MODEL_HEIGHTS.size() else 9.0

		for i in buckets[v].size():
			var e: Dictionary = buckets[v][i]
			var pos: Vector2i = e["pos"]
			var dir: Vector2i = e["dir"]
			var h_low: float = e["h_low"]
			var diff: float = e["h_high"] - h_low
			var s: float = diff / model_h

			var rot_y: float = DIR_ROT.get(dir, 0.0) + facing_rotation_offset

			# Place at the exact boundary between the high and low cells.
			# pos is the HIGH cell; dir points toward the LOW cell.
			# Cell center is at (pos + 0.5), boundary is 0.5 further in dir.
			var wx: float = float(pos.x) + 0.5 + float(dir.x) * 0.5
			var wz: float = float(pos.y) + 0.5 + float(dir.y) * 0.5
			var wy: float = h_low + vertical_offset

			var xform_basis := Basis.IDENTITY.scaled(Vector3(s, s, s)).rotated(Vector3.UP, rot_y)

			# Offset to center the mesh's AABB at the placement point.
			# The AABB center in model space needs to be scaled and rotated
			# to find where it ends up, then we shift the origin to compensate.
			var center: Vector3 = (
				_mesh_aabb_centers[v] if v < _mesh_aabb_centers.size() else Vector3.ZERO
			)
			# We want the bottom of the AABB at wy, so only center XZ.
			# Y offset: place bottom of AABB at wy (subtract min Y, not center Y).
			var aabb := _meshes[v].get_aabb()
			var y_bottom: float = aabb.position.y
			center.y = y_bottom  # offset from origin to bottom
			var world_offset: Vector3 = xform_basis * center
			var origin := Vector3(wx - world_offset.x, wy - world_offset.y, wz - world_offset.z)
			mm.set_instance_transform(i, Transform3D(xform_basis, origin))

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if _material:
			mmi.material_override = _material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
