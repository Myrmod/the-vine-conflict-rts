class_name PaintAlphaCommand
extends EditorCommand

var map_resource: MapResource
var positions: Array[Vector2i]
var erase: bool
var strength: float = 1.0
var center_f: Vector2  ## brush center in cell-space float units (cell + 0.5 for grid-snapped)
var brush_ref: EditorBrush

var previous_values: PackedFloat32Array = PackedFloat32Array()


func _init(
	map_res: MapResource,
	_positions: Array[Vector2i],
	_erase: bool,
	_strength: float,
	_center_f: Vector2,
	_brush: EditorBrush
) -> void:
	map_resource = map_res
	positions = _positions
	erase = _erase
	strength = _strength
	center_f = _center_f
	brush_ref = _brush
	description = "Paint Alpha"


func execute() -> void:
	previous_values.clear()
	if map_resource.alpha_mask == null:
		map_resource._ensure_alpha_mask()

	for pos in positions:
		previous_values.append(map_resource.alpha_mask.get_pixel(pos.x, pos.y).r)

		var falloff: float = 1.0
		if brush_ref != null:
			falloff = brush_ref.get_edge_falloff_f(pos, center_f)

		var cell_strength: float = strength * falloff
		if cell_strength <= 0.0:
			continue

		var target: float = 0.0 if erase else 1.0
		var current: float = map_resource.alpha_mask.get_pixel(pos.x, pos.y).r
		var new_val: float = lerpf(current, target, cell_strength)
		map_resource.alpha_mask.set_pixel(pos.x, pos.y, Color(new_val, 0.0, 0.0, 1.0))


func undo() -> void:
	for i: int in range(positions.size()):
		var pos: Vector2i = positions[i]
		var old_val: float = previous_values[i]
		map_resource.alpha_mask.set_pixel(pos.x, pos.y, Color(old_val, 0.0, 0.0, 1.0))
