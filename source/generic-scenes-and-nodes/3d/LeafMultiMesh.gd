@tool
class_name LeafMultiMesh extends MultiMeshInstance3D

## Scatters leaf quads via MultiMesh inside an ellipsoidal volume.
## Tweak the exported properties in the inspector, then the mesh regenerates
## automatically whenever a value changes.

## The leaf texture (albedo with alpha).
@export var leaf_texture: Texture2D:
	set(value):
		leaf_texture = value
		_rebuild()

## Number of leaf instances.
@export_range(1, 5000, 1) var leaf_count: int = 120:
	set(value):
		leaf_count = value
		_rebuild()

## Size of each leaf quad.
@export var leaf_size: Vector2 = Vector2(0.3, 0.3):
	set(value):
		leaf_size = value
		_rebuild()

## Radii of the ellipsoidal scatter volume (x, y, z).
@export var crown_radius: Vector3 = Vector3(1.5, 1.0, 1.5):
	set(value):
		crown_radius = value
		_rebuild()

## Centre offset of the crown volume relative to this node.
@export var crown_offset: Vector3 = Vector3.ZERO:
	set(value):
		crown_offset = value
		_rebuild()

## Random scale variation: each leaf is scaled between (1 - variation) and (1 + variation).
@export_range(0.0, 0.9, 0.01) var scale_variation: float = 0.25:
	set(value):
		scale_variation = value
		_rebuild()

## Alpha‑scissor threshold (cheaper than alpha‑blend, avoids sorting).
@export_range(0.0, 1.0, 0.01) var alpha_scissor_threshold: float = 0.5:
	set(value):
		alpha_scissor_threshold = value
		_rebuild()

## Seed for reproducible placement.
@export var seed_value: int = 0:
	set(value):
		seed_value = value
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return

	# --- material ---
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = alpha_scissor_threshold
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if leaf_texture:
		mat.albedo_texture = leaf_texture

	# --- quad mesh ---
	var quad: QuadMesh = QuadMesh.new()
	quad.size = leaf_size
	quad.material = mat

	# --- multimesh ---
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = leaf_count

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value

	for i: int in leaf_count:
		# Uniform random point inside an ellipsoid using rejection sampling
		var point: Vector3 = _random_point_in_ellipsoid(rng, crown_radius)
		point += crown_offset

		# Random rotation around all axes
		var rot: Basis = Basis(
			Vector3.UP, rng.randf_range(0.0, TAU)
		) * Basis(
			Vector3.RIGHT, rng.randf_range(-PI * 0.25, PI * 0.25)
		)

		# Random scale
		var s: float = 1.0 + rng.randf_range(-scale_variation, scale_variation)

		var xform: Transform3D = Transform3D(rot * Basis.IDENTITY.scaled(Vector3(s, s, s)), point)
		mm.set_instance_transform(i, xform)

	multimesh = mm


func _random_point_in_ellipsoid(rng: RandomNumberGenerator, radii: Vector3) -> Vector3:
	# Rejection sampling: pick a random point in the bounding box, keep if inside unit sphere
	for attempt: int in 100:
		var p: Vector3 = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
		)
		if p.length_squared() <= 1.0:
			return p * radii
	# Fallback: return origin (should almost never happen)
	return Vector3.ZERO
