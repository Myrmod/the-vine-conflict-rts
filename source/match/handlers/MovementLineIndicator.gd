extends Node3D
## Draws dashed lines from friendly moving units to their target positions
## and places a movement marker at each target.  Lives under the Match node.
##
## Data persists as long as a unit is moving.  Visuals (lines + markers) are
## only shown while the unit is selected.  Deselecting hides them; reselecting
## shows them again.  Only friendly ("controlled_units") units are tracked.

const MouseClickAnimation = preload("res://source/match/utils/MouseClickAnimation.tscn")

const LINE_Y := 0.12
const LINE_WIDTH := 0.06

var _dashed_line_material: ShaderMaterial = null

## unit instance_id → { unit, target, action_cb }
## Stores movement target data for all friendly moving units.
var _unit_targets: Dictionary = {}

## unit instance_id → { line: MeshInstance3D, marker: Node3D }
## Only created for currently selected units with active targets.
var _visuals: Dictionary = {}


func _ready() -> void:
	_dashed_line_material = ShaderMaterial.new()
	_dashed_line_material.shader = preload("res://source/shaders/3d/dashed_line.gdshader")
	_dashed_line_material.set_shader_parameter("line_color", Color(0.5, 1.0, 0.5, 0.55))
	_dashed_line_material.set_shader_parameter("dash_length", 0.3)
	_dashed_line_material.set_shader_parameter("gap_length", 0.2)
	MatchSignals.unit_selected.connect(_on_unit_selected)
	MatchSignals.unit_deselected.connect(_on_unit_deselected)


## Called by MouseClickAnimationsHandler when a move command is issued.
func show_indicators(unit_target_pairs: Array) -> void:
	for pair in unit_target_pairs:
		var unit: Node = pair[0]
		var target_pos: Vector3 = pair[1]
		if not unit.is_in_group("controlled_units"):
			continue
		_register_target(unit, target_pos)


func _register_target(unit: Node, target_pos: Vector3) -> void:
	var uid: int = unit.get_instance_id()

	# If already tracked, remove old entry first.
	if uid in _unit_targets:
		_unregister_target_by_id(uid)

	# Listen for action changes — remove when no longer Moving.
	var on_action_changed := func(new_action: Variant) -> void:
		var is_moving: bool = (
			new_action != null
			and new_action.get_script() != null
			and new_action.get_script().resource_path.ends_with("Moving.gd")
		)
		if not is_moving:
			_unregister_target_by_id(uid)
	unit.action_changed.connect(on_action_changed)

	_unit_targets[uid] = {
		"unit": unit,
		"target": target_pos,
		"action_cb": on_action_changed,
	}

	# If the unit is currently selected, create visuals immediately.
	if unit.is_in_group("selected_units"):
		_create_visuals(uid)


func _unregister_target_by_id(uid: int) -> void:
	if uid not in _unit_targets:
		return
	var entry: Dictionary = _unit_targets[uid]
	var unit = entry["unit"]

	# Disconnect signal.
	if unit != null and is_instance_valid(unit) and unit.has_signal("action_changed"):
		if unit.action_changed.is_connected(entry["action_cb"]):
			unit.action_changed.disconnect(entry["action_cb"])

	# Remove visuals.
	_destroy_visuals(uid)

	_unit_targets.erase(uid)


func _on_unit_selected(unit: Node) -> void:
	var uid: int = unit.get_instance_id()
	if uid in _unit_targets and uid not in _visuals:
		_create_visuals(uid)


func _on_unit_deselected(unit: Node) -> void:
	_destroy_visuals(unit.get_instance_id())


func _create_visuals(uid: int) -> void:
	if uid in _visuals or uid not in _unit_targets:
		return
	var entry: Dictionary = _unit_targets[uid]
	var target_pos: Vector3 = entry["target"]

	# Snap Y to terrain height — circle_spread zeroes Y for navmesh purposes,
	# but the visual marker must appear at the correct ground elevation.
	var match_node = find_parent("Match")
	if match_node != null and match_node.map != null:
		target_pos.y = match_node.map.get_height_at_world(target_pos)
	# Write back so _update_line_mesh also uses the correct height.
	entry["target"] = target_pos

	# Marker at target position.
	var marker: Node3D = MouseClickAnimation.instantiate()
	marker.global_transform = Transform3D(Basis(), target_pos)
	add_child(marker)
	# Prevent the marker from auto-destructing after its fade-out animation.
	# _ready() already ran (add_child triggers it), so stop the animation
	# and disconnect the self-destruct callback.
	var anim_player = marker.find_child("AnimationPlayer")
	if anim_player:
		anim_player.stop()
		for connection in anim_player.animation_finished.get_connections():
			anim_player.animation_finished.disconnect(connection["callable"])
	# Reset scale in case the animation partially played.
	var sprite = marker.find_child("Sprite3D")
	if sprite:
		sprite.scale = Vector3.ONE

	# Dashed line from unit to target.
	var line_mesh := MeshInstance3D.new()
	line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line_mesh.material_override = _dashed_line_material
	add_child(line_mesh)

	_visuals[uid] = {"line": line_mesh, "marker": marker}


func _destroy_visuals(uid: int) -> void:
	if uid not in _visuals:
		return
	var vis: Dictionary = _visuals[uid]
	if vis["line"] != null and is_instance_valid(vis["line"]):
		vis["line"].queue_free()
	if vis["marker"] != null and is_instance_valid(vis["marker"]):
		vis["marker"].queue_free()
	_visuals.erase(uid)


func _process(_delta: float) -> void:
	# Update line meshes every frame to follow moving units.
	for uid in _visuals:
		if uid not in _unit_targets:
			continue
		var entry: Dictionary = _unit_targets[uid]
		var unit = entry["unit"]
		if unit == null or not is_instance_valid(unit):
			continue
		var vis: Dictionary = _visuals[uid]
		var line: MeshInstance3D = vis["line"]
		if line == null or not is_instance_valid(line):
			continue
		_update_line_mesh(line, unit.global_position, entry["target"])


func _update_line_mesh(mesh_inst: MeshInstance3D, from_pos: Vector3, to_pos: Vector3) -> void:
	var start := Vector3(from_pos.x, from_pos.y + LINE_Y, from_pos.z)
	var end := Vector3(to_pos.x, to_pos.y + LINE_Y, to_pos.z)
	var diff := end - start
	var length := diff.length()
	if length < 0.01:
		mesh_inst.visible = false
		return
	mesh_inst.visible = true

	var dir := diff / length
	# Perpendicular vector for line width.
	var perp := Vector3(-dir.z, 0.0, dir.x) * LINE_WIDTH * 0.5

	# Build a quad (two triangles) along the line.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# UV.x encodes distance along the line for the dash shader.
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(start - perp)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(start + perp)
	st.set_uv(Vector2(length, 1.0))
	st.add_vertex(end + perp)

	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(start - perp)
	st.set_uv(Vector2(length, 1.0))
	st.add_vertex(end + perp)
	st.set_uv(Vector2(length, 0.0))
	st.add_vertex(end - perp)

	st.generate_normals()
	mesh_inst.mesh = st.commit()
