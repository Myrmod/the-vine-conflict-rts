## Draws an animated electric discharge between two world positions.
## Uses a billboarded PlaneMesh with the vine_arc fBm shader.
## Same billboard convention as the laser beam system in Projectile.gd.
extends MeshInstance3D

const ARC_WIDTH := 0.6
const DURATION := 0.25
const LIGHT_COLOR := Color(0.4, 0.6, 1.0)
const LIGHT_ENERGY := 1.0
const LIGHT_RANGE := 2.0
const VINE_ARC_SHADER = preload("res://source/shaders/3d/vine_arc.gdshader")

static var _shared_material: ShaderMaterial = null

var _from: Vector3
var _to: Vector3
var _elapsed: float = 0.0
var _material: ShaderMaterial
var _light: OmniLight3D


static func _ensure_shared_material() -> ShaderMaterial:
	if _shared_material != null:
		return _shared_material
	_shared_material = ShaderMaterial.new()
	_shared_material.shader = VINE_ARC_SHADER
	_shared_material.set_shader_parameter("effect_color", Color(0.2, 0.3, 0.8))
	return _shared_material


func setup(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	_build_mesh()


func _build_mesh() -> void:
	var direction := _to - _from
	var length := direction.length()
	if length < 0.1:
		queue_free()
		return

	var dir_norm := direction.normalized()
	var center := (_from + _to) * 0.5

	# Default PlaneMesh (FACE_Y) has vertices in XZ: VERTEX.x = along beam, VERTEX.z = width
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	mesh = plane

	# Build basis matching Projectile._beam_transform convention:
	# Column 0 (X) = beam direction * length
	# Column 1 (Y) = up (billboard shader overrides)
	# Column 2 (Z) = perpendicular * width
	var up := Vector3.UP
	if absf(dir_norm.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var perp := dir_norm.cross(up).normalized()

	global_transform = Transform3D(
		Basis(dir_norm * length, dir_norm.cross(perp).normalized(), perp * ARC_WIDTH),
		center,
	)

	_material = _ensure_shared_material().duplicate() as ShaderMaterial
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_light = OmniLight3D.new()
	_light.light_color = LIGHT_COLOR
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = LIGHT_RANGE
	_light.omni_attenuation = 2.0
	_light.shadow_enabled = false
	_light.position = Vector3.ZERO
	add_child(_light)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	var fade: float = 1.0 - _elapsed / DURATION
	_material.set_shader_parameter("fade", fade)
	_light.light_energy = LIGHT_ENERGY * fade
