extends Node3D

## Renders translucent circles at preview positions during a
## right-click drag to show where units will end up, plus an
## arrow indicating the forward (facing) direction.

const CIRCLE_SEGMENTS := 24
const CIRCLE_COLOR := Color(0.5, 1.0, 0.5, 0.45)
const ARROW_COLOR := Color(0.5, 1.0, 0.5, 0.7)
const CIRCLE_Y := 0.08
const ARROW_Y := 0.09
const ARROW_LENGTH := 1.2
const ARROW_HEAD_LENGTH := 0.4
const ARROW_WIDTH := 0.06
const ARROW_HEAD_WIDTH := 0.25

var _meshes: Array[MeshInstance3D] = []
var _arrow: MeshInstance3D = null


func show_preview(positions: Array, radii: Array, forward_dir: Vector3 = Vector3.ZERO) -> void:
	_ensure_mesh_count(positions.size())
	for i in range(positions.size()):
		var mi: MeshInstance3D = _meshes[i]
		mi.visible = true
		mi.global_transform.origin = Vector3(positions[i].x, CIRCLE_Y, positions[i].z)
		var r: float = radii[i] if i < radii.size() else 0.5
		mi.mesh = _build_circle_mesh(r)

	# Arrow showing forward direction.
	if forward_dir.length() > 0.01 and positions.size() > 0:
		_ensure_arrow()
		# Place arrow at the midpoint of all positions.
		var center := Vector3.ZERO
		for p in positions:
			center += p
		center /= float(positions.size())
		_arrow.global_transform.origin = Vector3(center.x, ARROW_Y, center.z)
		var fwd := Vector3(forward_dir.x, 0.0, forward_dir.z).normalized()
		var yaw := atan2(-fwd.x, -fwd.z)
		_arrow.global_transform.basis = Basis(Vector3.UP, yaw)
		_arrow.mesh = _build_arrow_mesh()
		_arrow.visible = true
	elif _arrow:
		_arrow.visible = false


func hide_preview() -> void:
	for mi in _meshes:
		mi.visible = false
	if _arrow:
		_arrow.visible = false


func _ensure_mesh_count(count: int) -> void:
	while _meshes.size() < count:
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = CIRCLE_COLOR
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mi.material_override = mat
		add_child(mi)
		_meshes.append(mi)


func _ensure_arrow() -> void:
	if _arrow:
		return
	_arrow = MeshInstance3D.new()
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.visible = false
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = ARROW_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	_arrow.material_override = mat
	add_child(_arrow)


func _build_circle_mesh(radius: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3.ZERO
	for seg in range(CIRCLE_SEGMENTS):
		var a0: float = TAU * float(seg) / float(CIRCLE_SEGMENTS)
		var a1: float = TAU * float(seg + 1) / float(CIRCLE_SEGMENTS)
		st.add_vertex(center)
		st.add_vertex(Vector3(cos(a0) * radius, 0, sin(a0) * radius))
		st.add_vertex(Vector3(cos(a1) * radius, 0, sin(a1) * radius))
	st.generate_normals()
	return st.commit()


## Build an arrow mesh pointing along -Z (the model's forward).
## Consists of a thin shaft + a triangular arrowhead.
func _build_arrow_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = ARROW_WIDTH * 0.5
	var shaft_end: float = -(ARROW_LENGTH - ARROW_HEAD_LENGTH)

	# Shaft (quad = 2 triangles).
	st.add_vertex(Vector3(-hw, 0, 0))
	st.add_vertex(Vector3(hw, 0, 0))
	st.add_vertex(Vector3(hw, 0, shaft_end))

	st.add_vertex(Vector3(-hw, 0, 0))
	st.add_vertex(Vector3(hw, 0, shaft_end))
	st.add_vertex(Vector3(-hw, 0, shaft_end))

	# Arrowhead triangle.
	var hhw: float = ARROW_HEAD_WIDTH * 0.5
	var tip: float = -ARROW_LENGTH
	st.add_vertex(Vector3(-hhw, 0, shaft_end))
	st.add_vertex(Vector3(hhw, 0, shaft_end))
	st.add_vertex(Vector3(0, 0, tip))

	st.generate_normals()
	return st.commit()
