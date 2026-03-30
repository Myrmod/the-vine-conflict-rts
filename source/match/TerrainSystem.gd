class_name TerrainSystem

extends Node3D

# we need to define that, since shaders can't be too dynamic
const MAX_TERRAINS := 16

const _SLOPE_CARDINAL_DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

@export var base_layer: TerrainType = Globals.terrain_types.front()

var size: Vector2i
var map: MapResource
var splat_images: Array[Image] = []
var splat_textures: Array[Texture2D] = []

## Height-grid texture uploaded to the shader so vertex() can displace
## per-vertex based on the MapResource height data.
var _height_grid_texture: ImageTexture

## Separate height-grid for the high-ground plane (only HIGH_GROUND cells).
var _high_ground_height_texture: ImageTexture

## Layer mask textures: R8, white = render, black = discard.
var _base_layer_mask_texture: ImageTexture
var _high_ground_layer_mask_texture: ImageTexture

## Water mask texture: white where water cells exist, black elsewhere.
## Uploaded to the water shader so it can discard non-water fragments.
var _water_mask_texture: ImageTexture

## The terrain system shader assigned in the scene file.  Saved before
## ensure_mesh() overrides material_override with a simple fallback so
## set_map() can restore it when a MapResource supplies real textures.
var _terrain_shader_material: Material = null


func ensure_mesh(map_size: Vector2):
	"""Create the TerrainMesh geometry if it has not been set up yet.
	Called by set_map() for MapResource maps, and directly by Match for
	predefined .tscn maps that have no MapResource."""
	if $TerrainMesh.mesh:
		return
	_create_terrain_mesh(map_size)


func _create_terrain_mesh(map_size: Vector2):
	"""(Re-)create the terrain plane mesh with the given dimensions."""
	# Save the terrain system shader before replacing with a simple fallback.
	# For predefined maps (no MapResource) the shader has no textures and
	# renders solid white, hiding everything at Y=0.
	if not _terrain_shader_material:
		_terrain_shader_material = $TerrainMesh.material_override
	$TerrainMesh.material_override = preload(
		"res://source/match/resources/materials/terrain.material.tres"
	)
	var plane := PlaneMesh.new()
	plane.size = map_size
	plane.subdivide_width = int(map_size.x) - 1
	plane.subdivide_depth = int(map_size.y) - 1
	$TerrainMesh.mesh = plane
	$TerrainMesh.position = Vector3(map_size.x / 2.0, 0, map_size.y / 2.0)

	# High-ground plane: same geometry, separate material for layer masking.
	var hg_plane := PlaneMesh.new()
	hg_plane.size = map_size
	hg_plane.subdivide_width = int(map_size.x) - 1
	hg_plane.subdivide_depth = int(map_size.y) - 1
	$HighGroundMesh.mesh = hg_plane
	$HighGroundMesh.position = Vector3(map_size.x / 2.0, 0, map_size.y / 2.0)


func resize_mesh(map_size: Vector2):
	"""Recreate the terrain mesh at a new size (e.g. after map resize).
	Also clears cached textures so they are rebuilt at the new resolution."""
	_create_terrain_mesh(map_size)
	# Force-clear texture caches — they were created at the old dimensions
	# and ImageTexture.update() cannot change an image's size.
	_height_grid_texture = null
	_high_ground_height_texture = null
	_base_layer_mask_texture = null
	_high_ground_layer_mask_texture = null
	_water_mask_texture = null
	splat_textures.clear()
	splat_images.clear()


func set_map(_map: MapResource):
	map = _map
	size = map.size

	ensure_mesh(map.size)
	# Restore the terrain system shader now that we have real textures to load.
	if _terrain_shader_material:
		$TerrainMesh.material_override = _terrain_shader_material
		# High-ground mesh gets a duplicate material so it can have its own
		# layer mask and height texture while sharing the same shader.
		$HighGroundMesh.material_override = _terrain_shader_material.duplicate()

	if not $WaterMesh.mesh:
		$WaterMesh.mesh = PlaneMesh.new()
	$WaterMesh.mesh.size = _map.size
	var water_y: float = Constants.LEVEL_HEIGHTS[Enums.HeightLevel.WATER]
	$WaterMesh.position = Vector3(map.size.x / 2.0, water_y, map.size.y / 2.0)

	if map.splatmaps.is_empty():
		map.initialize_splatmaps(Globals.terrain_types.size())

	_ensure_splat_textures()
	_upload_splats_to_shader()
	_upload_terrain_textures()
	_upload_height_grid()
	_build_slope_meshes()
	_upload_water_mask()


# ============================================================
# Height grid → shader
# ============================================================


func _upload_height_grid():
	"""Build height textures and layer masks for the two-plane terrain system.
	Base plane: all cells at their height, HIGH_GROUND cells masked out.
	High-ground plane: flat at HIGH_GROUND height, mask shows only HG cells.
	The HG plane is filled uniformly so boundary vertices never sample a
	different height — the fragment mask handles which cells are visible."""
	if not map:
		return

	var water_depth_offset := 1.0
	var hg_height: float = Constants.LEVEL_HEIGHTS[Enums.HeightLevel.HIGH_GROUND]

	# -- Build images for both planes --
	var base_img := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	# Fill the entire HG height image with a uniform height so every vertex
	# sits at the same elevation — no distortion at mask boundaries.
	var hg_img := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	hg_img.fill(Color(hg_height, 0, 0, 0))
	var base_mask := Image.create(size.x, size.y, false, Image.FORMAT_R8)
	var hg_mask := Image.create(size.x, size.y, false, Image.FORMAT_R8)

	var has_high_ground := false

	for y in range(size.y):
		for x in range(size.x):
			var pos := Vector2i(x, y)
			var h: float = map.get_height_at(pos)
			var ct: int = map.get_cell_type_at(pos) if not map.cell_type_grid.is_empty() else 0

			if ct == MapResource.CELL_HIGH_GROUND:
				# Base plane: discard this cell – the high-ground plane sits above
				# and cliffs cover the vertical transition.
				base_img.set_pixel(x, y, Color(0.0, 0, 0, 0))
				base_mask.set_pixel(x, y, Color(0, 0, 0, 0))
				# High-ground plane: mask in (height already filled uniformly)
				hg_mask.set_pixel(x, y, Color(1, 0, 0, 0))
				has_high_ground = true
			elif ct == MapResource.CELL_WATER:
				base_img.set_pixel(x, y, Color(h - water_depth_offset, 0, 0, 0))
				base_mask.set_pixel(x, y, Color(1, 0, 0, 0))
				hg_mask.set_pixel(x, y, Color(0, 0, 0, 0))
			elif ct == MapResource.CELL_SLOPE or ct == MapResource.CELL_WATER_SLOPE:
				# Slopes are rendered by separate tilted quads — mask out of both planes.
				base_img.set_pixel(x, y, Color(0.0, 0, 0, 0))
				base_mask.set_pixel(x, y, Color(0, 0, 0, 0))
				hg_mask.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				# Normal ground
				base_img.set_pixel(x, y, Color(h, 0, 0, 0))
				base_mask.set_pixel(x, y, Color(1, 0, 0, 0))
				hg_mask.set_pixel(x, y, Color(0, 0, 0, 0))

	# -- Upload base terrain --
	if _height_grid_texture:
		_height_grid_texture.update(base_img)
	else:
		_height_grid_texture = ImageTexture.create_from_image(base_img)

	if _base_layer_mask_texture:
		_base_layer_mask_texture.update(base_mask)
	else:
		_base_layer_mask_texture = ImageTexture.create_from_image(base_mask)

	var base_mat := $TerrainMesh.get_active_material(0) as ShaderMaterial
	if base_mat:
		base_mat.set_shader_parameter("grid_height_tex", _height_grid_texture)
		base_mat.set_shader_parameter("grid_height_scale", 1.0)
		base_mat.set_shader_parameter("layer_mask_tex", _base_layer_mask_texture)
		base_mat.set_shader_parameter("layer_mask_enabled", true)
		# Debug: flat green for normal ground
		var debug_layers: bool = FeatureFlags.debug_terrain_layers if FeatureFlags else false
		base_mat.set_shader_parameter("debug_layer_color_enabled", debug_layers)
		base_mat.set_shader_parameter("debug_layer_color", Color.GREEN)

	# -- Upload high-ground plane --
	$HighGroundMesh.visible = has_high_ground

	if has_high_ground:
		if _high_ground_height_texture:
			_high_ground_height_texture.update(hg_img)
		else:
			_high_ground_height_texture = ImageTexture.create_from_image(hg_img)

		if _high_ground_layer_mask_texture:
			_high_ground_layer_mask_texture.update(hg_mask)
		else:
			_high_ground_layer_mask_texture = ImageTexture.create_from_image(hg_mask)

		var hg_mat := $HighGroundMesh.get_active_material(0) as ShaderMaterial
		if hg_mat:
			hg_mat.set_shader_parameter("grid_height_tex", _high_ground_height_texture)
			hg_mat.set_shader_parameter("grid_height_scale", 1.0)
			hg_mat.set_shader_parameter("layer_mask_tex", _high_ground_layer_mask_texture)
			hg_mat.set_shader_parameter("layer_mask_enabled", true)
			# Debug: flat yellow for high ground
			var debug_layers: bool = FeatureFlags.debug_terrain_layers if FeatureFlags else false
			hg_mat.set_shader_parameter("debug_layer_color_enabled", debug_layers)
			hg_mat.set_shader_parameter("debug_layer_color", Color.YELLOW)


func update_height_at(_positions: Array[Vector2i]):
	"""Efficiently update only the changed cells after a brush stroke."""
	if not map or not _height_grid_texture:
		_upload_height_grid()
		_build_slope_meshes()
		return

	# Rebuild the full image (RF images don't support partial update easily)
	_upload_height_grid()
	_build_slope_meshes()
	_upload_water_mask()


# ============================================================
# Slope meshes — separate tilted quads per region
# ============================================================


func _build_slope_meshes() -> void:
	"""Build per-cell tilted quads for every slope region.  Each region is
	flood-filled, a dominant ramp direction computed from boundary heights,
	then per-cell quads connect the low side to the high side with proper
	linear interpolation.  All cells in a region share one ArrayMesh."""
	for child in $SlopeMeshes.get_children():
		child.queue_free()
	if not map or map.cell_type_grid.is_empty():
		return

	var visited := {}

	for y in range(size.y):
		for x in range(size.x):
			var pos := Vector2i(x, y)
			if visited.has(pos):
				continue
			var ct: int = map.get_cell_type_at(pos)
			if ct != MapResource.CELL_SLOPE and ct != MapResource.CELL_WATER_SLOPE:
				continue

			# Flood-fill the slope region
			var region: Array[Vector2i] = []
			var queue: Array[Vector2i] = [pos]
			visited[pos] = true
			while not queue.is_empty():
				var p: Vector2i = queue.pop_front()
				region.append(p)
				for d in _SLOPE_CARDINAL_DIRS:
					var n := p + d
					if n.x < 0 or n.x >= size.x or n.y < 0 or n.y >= size.y:
						continue
					if visited.has(n):
						continue
					var nct: int = map.get_cell_type_at(n)
					if nct == ct:
						visited[n] = true
						queue.append(n)

			_create_slope_region_mesh(region)


func _create_slope_region_mesh(region: Array[Vector2i]) -> void:
	if region.is_empty():
		return

	# Find boundary heights (low / high) from neighbouring non-slope cells FIRST
	# so direction computation doesn't depend on stored slope heights.
	var low_h: float = INF
	var high_h: float = -INF
	for p in region:
		for d in _SLOPE_CARDINAL_DIRS:
			var n := p + d
			if n.x < 0 or n.x >= size.x or n.y < 0 or n.y >= size.y:
				continue
			var nct: int = map.get_cell_type_at(n)
			if nct == MapResource.CELL_SLOPE or nct == MapResource.CELL_WATER_SLOPE:
				continue
			var nh: float = map.get_height_at(n)
			low_h = minf(low_h, nh)
			high_h = maxf(high_h, nh)

	if low_h == INF:
		low_h = 0.0
	if high_h == -INF:
		high_h = low_h

	# Compute dominant ramp direction using boundary neighbours only.
	# Use mid_h as the reference so direction is independent of stored slope heights.
	var mid_h := (low_h + high_h) * 0.5
	var total_diff := Vector2.ZERO
	for p in region:
		for d in _SLOPE_CARDINAL_DIRS:
			var n := p + d
			if n.x < 0 or n.x >= size.x or n.y < 0 or n.y >= size.y:
				continue
			var nct: int = map.get_cell_type_at(n)
			if nct == MapResource.CELL_SLOPE or nct == MapResource.CELL_WATER_SLOPE:
				continue
			total_diff += Vector2(d.x, d.y) * (map.get_height_at(n) - mid_h)

	var direction: Vector2i
	if total_diff.length_squared() < 0.001:
		direction = Vector2i(1, 0)
	elif absf(total_diff.x) >= absf(total_diff.y):
		direction = Vector2i(1, 0) if total_diff.x > 0 else Vector2i(-1, 0)
	else:
		direction = Vector2i(0, 1) if total_diff.y > 0 else Vector2i(0, -1)

	# Ramp extent along direction
	var ramp_min: int = 0x7FFFFFFF
	var ramp_max: int = -0x7FFFFFFF
	for p in region:
		var along: int = p.x * direction.x + p.y * direction.y
		ramp_min = mini(ramp_min, along)
		ramp_max = maxi(ramp_max, along)
	var ramp_len: int = ramp_max - ramp_min + 1

	# Build per-cell quads into a single ArrayMesh
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for p in region:
		var cx: float = float(p.x)
		var cz: float = float(p.y)

		# t values at the cell edges along the ramp (0..1 across full region)
		var along: int = p.x * direction.x + p.y * direction.y
		var t0: float = float(along - ramp_min) / float(ramp_len)
		var t1: float = float(along - ramp_min + 1) / float(ramp_len)
		var h_lo: float = low_h + t0 * (high_h - low_h)
		var h_hi: float = low_h + t1 * (high_h - low_h)

		# Assign corner heights based on ramp direction
		var h00: float
		var h10: float
		var h01: float
		var h11: float
		if direction == Vector2i(1, 0):
			h00 = h_lo
			h10 = h_hi
			h01 = h_lo
			h11 = h_hi
		elif direction == Vector2i(-1, 0):
			h00 = h_hi
			h10 = h_lo
			h01 = h_hi
			h11 = h_lo
		elif direction == Vector2i(0, 1):
			h00 = h_lo
			h10 = h_lo
			h01 = h_hi
			h11 = h_hi
		else:  # (0, -1)
			h00 = h_hi
			h10 = h_hi
			h01 = h_lo
			h11 = h_lo

		# Store the origin-corner height so Map.get_height_at_world()
		# bilinear interpolation reproduces the exact ramp surface.
		map.set_height_at(p, h00)

		var base_idx: int = verts.size()
		verts.append(Vector3(cx, h00, cz))
		verts.append(Vector3(cx + 1.0, h10, cz))
		verts.append(Vector3(cx + 1.0, h11, cz + 1.0))
		verts.append(Vector3(cx, h01, cz + 1.0))

		# World-aligned UVs so splatmap textures line up with other planes
		uvs.append(Vector2(cx / float(size.x), cz / float(size.y)))
		uvs.append(Vector2((cx + 1.0) / float(size.x), cz / float(size.y)))
		uvs.append(Vector2((cx + 1.0) / float(size.x), (cz + 1.0) / float(size.y)))
		uvs.append(Vector2(cx / float(size.x), (cz + 1.0) / float(size.y)))

		# Face normal from two edges
		var e1 := Vector3(1.0, h10 - h00, 0.0)
		var e2 := Vector3(0.0, h01 - h00, 1.0)
		var n := e1.cross(e2).normalized()
		if n.y < 0:
			n = -n
		for _i in 4:
			normals.append(n)

		(
			indices
			. append_array(
				[
					base_idx,
					base_idx + 1,
					base_idx + 2,
					base_idx,
					base_idx + 2,
					base_idx + 3,
				]
			)
		)

	var arr_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Duplicate terrain shader material without height-grid displacement
	var slope_mat: ShaderMaterial = null
	if _terrain_shader_material:
		slope_mat = _terrain_shader_material.duplicate() as ShaderMaterial
		if slope_mat:
			slope_mat.set_shader_parameter("layer_mask_enabled", false)
			slope_mat.set_shader_parameter("grid_height_scale", 0.0)
			var debug_layers: bool = FeatureFlags.debug_terrain_layers if FeatureFlags else false
			slope_mat.set_shader_parameter("debug_layer_color_enabled", debug_layers)
			slope_mat.set_shader_parameter("debug_layer_color", Color.ORANGE)

	var mmi := MeshInstance3D.new()
	mmi.mesh = arr_mesh
	if slope_mat:
		mmi.material_override = slope_mat
	$SlopeMeshes.add_child(mmi)


# ============================================================
# Water mask → water shader
# ============================================================


func _upload_water_mask():
	"""Build an R8 mask image: white for water cells, black elsewhere.
	Padded by 1 cell so water is visible through terrain cliff edges.
	Uploaded to the water shader so it can discard non-water fragments."""
	if not map:
		return

	var img := Image.create(size.x, size.y, false, Image.FORMAT_R8)
	var has_water := false

	# First pass: mark actual water cells
	for y in range(size.y):
		for x in range(size.x):
			var idx: int = y * size.x + x
			var ct: int = map.cell_type_grid[idx] if idx < map.cell_type_grid.size() else 0
			if ct == MapResource.CELL_WATER or ct == MapResource.CELL_WATER_SLOPE:
				img.set_pixel(x, y, Color(1, 0, 0, 0))
				has_water = true

	# Second pass: pad 1 cell around water so it shows through cliff edges
	if has_water:
		var padded := img.duplicate()
		for y in range(size.y):
			for x in range(size.x):
				if img.get_pixel(x, y).r > 0.5:
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							var nx := x + dx
							var ny := y + dy
							if nx >= 0 and nx < size.x and ny >= 0 and ny < size.y:
								padded.set_pixel(nx, ny, Color(1, 0, 0, 0))
		img = padded

	$WaterMesh.visible = has_water

	if _water_mask_texture:
		_water_mask_texture.update(img)
	else:
		_water_mask_texture = ImageTexture.create_from_image(img)

	var mat: ShaderMaterial = $WaterMesh.get_active_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("water_mask_tex", _water_mask_texture)
		mat.set_shader_parameter("map_size", Vector2(size))


func apply_base_layer(terrain: TerrainType):
	if not map:
		return
	base_layer = terrain

	var terrain_id = base_layer.id
	var splat_index = terrain_id / 4
	var channel = terrain_id % 4

	# Ensure splatmaps exist
	if map.splatmaps.is_empty():
		map.initialize_splatmaps(Globals.terrain_types.size())

	# Clear all splatmaps first
	for img in map.splatmaps:
		for x in range(map.size.x):
			for y in range(map.size.y):
				img.set_pixel(x, y, Color(0, 0, 0, 0))

	# Fill selected terrain channel = 1
	var base_img = map.splatmaps[splat_index]

	# TODO: might cause performance issues on large maps
	for x in range(map.size.x):
		for y in range(map.size.y):
			var c = Color(0, 0, 0, 0)

			match channel:
				0:
					c.r = 1.0
				1:
					c.g = 1.0
				2:
					c.b = 1.0
				3:
					c.a = 1.0

			base_img.set_pixel(x, y, c)

	for i in range(map.splatmaps.size()):
		splat_textures[i].update(map.splatmaps[i])
	_ensure_splat_textures()


func _ensure_splat_textures():
	# If textures don't exist yet, create them
	if splat_textures.size() != map.splatmaps.size():
		splat_textures.clear()

		for img in map.splatmaps:
			var tex := ImageTexture.create_from_image(img)
			splat_textures.append(tex)

		_upload_splats_to_shader()
		return

	# Otherwise just update existing textures
	for i in range(map.splatmaps.size()):
		splat_textures[i].update(map.splatmaps[i])


func _upload_splats_to_shader():
	var mat := $TerrainMesh.get_active_material(0) as ShaderMaterial
	if not mat:
		push_warning("TerrainMesh has no ShaderMaterial")
		return

	if splat_textures.is_empty():
		push_warning("No splat textures found")
		return

	mat.set_shader_parameter("splat_tex", splat_textures)
	mat.set_shader_parameter("splat_count", splat_textures.size())

	# Mirror to high-ground plane
	var hg_mat := $HighGroundMesh.get_active_material(0) as ShaderMaterial
	if hg_mat:
		hg_mat.set_shader_parameter("splat_tex", splat_textures)
		hg_mat.set_shader_parameter("splat_count", splat_textures.size())


func _upload_terrain_textures():
	var mat := $TerrainMesh.get_active_material(0) as ShaderMaterial
	if not mat:
		push_warning("No ShaderMaterial")
		return

	var terrains = Globals.terrain_types
	if terrains.is_empty():
		return

	var albedo_array: Array[Texture2D] = []
	var normal_array: Array[Texture2D] = []
	var rough_array: Array[Texture2D] = []
	var ao_array: Array[Texture2D] = []
	var height_array: Array[Texture2D] = []

	for i in range(MAX_TERRAINS):
		if i < terrains.size():
			var t = terrains[i]
			albedo_array.append(t.albedo)
			normal_array.append(t.normal_gl)
			rough_array.append(t.roughness)
			ao_array.append(t.ao)
			height_array.append(t.displacement)
		else:
			albedo_array.append(null)
			normal_array.append(null)
			rough_array.append(null)
			ao_array.append(null)
			height_array.append(null)

	mat.set_shader_parameter("albedo_tex", albedo_array)
	mat.set_shader_parameter("normal_tex", normal_array)
	mat.set_shader_parameter("roughness_tex", rough_array)
	mat.set_shader_parameter("ao_tex", ao_array)
	mat.set_shader_parameter("height_tex", height_array)

	mat.set_shader_parameter("terrain_count", terrains.size())

	# this makes the picture repeat itself so we don't have one big picture covering the entire map
	# maybe we should adjust it depending on map size?
	mat.set_shader_parameter("uv_scale", 16.0)
	mat.set_shader_parameter("height_strength", 0.05)

	# Mirror all terrain textures to high-ground plane
	var hg_mat := $HighGroundMesh.get_active_material(0) as ShaderMaterial
	if hg_mat:
		hg_mat.set_shader_parameter("albedo_tex", albedo_array)
		hg_mat.set_shader_parameter("normal_tex", normal_array)
		hg_mat.set_shader_parameter("roughness_tex", rough_array)
		hg_mat.set_shader_parameter("ao_tex", ao_array)
		hg_mat.set_shader_parameter("height_tex", height_array)
		hg_mat.set_shader_parameter("terrain_count", terrains.size())
		hg_mat.set_shader_parameter("uv_scale", 16.0)
		hg_mat.set_shader_parameter("height_strength", 0.05)


func rebuild_terrain_index_texture():
	var img = Image.create(map.size.x, map.size.y, false, Image.FORMAT_R8)

	for y in range(map.size.y):
		for x in range(map.size.x):
			var index = y * map.size.x + x
			var value = map.terrain_grid[index]
			img.set_pixel(x, y, Color(value / 255.0, 0, 0))


func apply_texture_brush(positions: Array[Vector2i]):
	if not map:
		return

	var modified_splats := {}

	for pos in positions:
		var px = pos.x
		var py = pos.y

		# Collect weights
		var flat := []

		for s in range(map.splatmaps.size()):
			var c = map.splatmaps[s].get_pixel(px, py)
			flat.append(c.r)
			flat.append(c.g)
			flat.append(c.b)
			flat.append(c.a)

		# Increase selected terrain
		var terrain_id = base_layer.id  # or pass active terrain
		var strength = 0.25

		flat[terrain_id] += strength

		# Clamp
		for i in range(flat.size()):
			flat[i] = clamp(flat[i], 0.0, 1.0)

		# Normalize
		var total := 0.0
		for v in flat:
			total += v

		if total > 0.0001:
			for i in range(flat.size()):
				flat[i] /= total

		# Write back
		var index := 0
		for s in range(map.splatmaps.size()):
			var img = map.splatmaps[s]

			var c = Color(flat[index], flat[index + 1], flat[index + 2], flat[index + 3])

			img.set_pixel(px, py, c)
			modified_splats[s] = true
			index += 4

	# Update textures ONCE per splat
	for s in modified_splats.keys():
		splat_textures[s].update(map.splatmaps[s])
