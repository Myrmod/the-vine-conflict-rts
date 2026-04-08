class_name AlphaBrush
extends EditorBrush

## Brush that paints transparency into MapResource.alpha_mask.
## erase=true  → paints black (terrain becomes invisible)
## erase=false → paints white (terrain visibility restored)

enum AlphaMode { SOLID, SOFT, AIRBRUSH }

var erase: bool = true
var strength: float = 1.0
var alpha_mode: AlphaMode = AlphaMode.SOFT


func _init(
	map_res: MapResource = null,
	symmetry_sys: SymmetrySystem = null,
	cmd_stack: CommandStack = null,
	_erase: bool = true
) -> void:
	super._init(map_res, symmetry_sys, cmd_stack)
	erase = _erase


func apply(cell_pos: Vector2i) -> void:
	if not can_apply(cell_pos):
		return

	var affected: Array[Vector2i] = get_affected_positions(cell_pos)
	# Use float center (cell center) for accurate falloff
	var center_f: Vector2 = Vector2(float(cell_pos.x) + 0.5, float(cell_pos.y) + 0.5)
	var cmd: PaintAlphaCommand = PaintAlphaCommand.new(
		map_resource, affected, erase, strength, center_f, self
	)
	command_stack.push_command(cmd)
	brush_applied.emit(affected)


func apply_free(world_pos: Vector2) -> void:
	"""Apply brush at a sub-cell float world position (used with Alt held)."""
	var s: float = FeatureFlags.grid_cell_size
	var center_f: Vector2 = world_pos / s
	var affected: Array[Vector2i] = get_affected_positions_f(center_f)
	if affected.is_empty():
		return
	# Filter to in-bounds cells
	var valid: Array[Vector2i] = []
	for p: Vector2i in affected:
		if _is_in_bounds(p):
			valid.append(p)
	if valid.is_empty():
		return
	var cmd: PaintAlphaCommand = PaintAlphaCommand.new(
		map_resource, valid, erase, strength, center_f, self
	)
	command_stack.push_command(cmd)
	brush_applied.emit(valid)


func set_alpha_mode(mode: AlphaMode) -> void:
	alpha_mode = mode


func get_edge_falloff(cell_pos: Vector2i, center: Vector2i) -> float:
	return get_edge_falloff_f(cell_pos, Vector2(float(center.x) + 0.5, float(center.y) + 0.5))


func get_edge_falloff_f(cell_pos: Vector2i, center_f: Vector2) -> float:
	var effective_radius: float = maxf(brush_size + 0.5, 0.5)
	var cell_center_f := Vector2(float(cell_pos.x) + 0.5, float(cell_pos.y) + 0.5)
	var offset := cell_center_f - center_f
	var distance: float = (
		offset.length()
		if brush_shape == BrushShape.CIRCLE
		else maxf(absf(offset.x), absf(offset.y))
	)
	var normalized_distance: float = clampf(distance / effective_radius, 0.0, 1.0)

	match alpha_mode:
		AlphaMode.SOLID:
			return 1.0
		AlphaMode.SOFT:
			var t: float = (
				normalized_distance * normalized_distance * (3.0 - 2.0 * normalized_distance)
			)
			return 1.0 - t
		AlphaMode.AIRBRUSH:
			return exp(-4.0 * normalized_distance * normalized_distance)

	return 1.0


func get_brush_name() -> String:
	var mode_name: String = "Solid"
	match alpha_mode:
		AlphaMode.SOFT:
			mode_name = "Soft"
		AlphaMode.AIRBRUSH:
			mode_name = "Airbrush"
	var action: String = "Erase" if erase else "Restore"
	return "Alpha %s [%s]" % [action, mode_name]


func get_cursor_color() -> Color:
	return Color(0.3, 0.6, 1.0) if erase else Color(1.0, 0.85, 0.2)
