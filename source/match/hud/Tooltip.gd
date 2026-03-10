class_name Tooltip

extends Control

const OFFSET: Vector2 = Vector2.ONE * 15.0

var opacity_tween: Tween = null

@onready var content_container = $PanelContainer/TooltipContentContainer
@onready var _panel: PanelContainer = $PanelContainer
@onready
var _title_label: RichTextLabel = $PanelContainer/TooltipContentContainer/VBoxContainer/RichTextLabel
@onready
var _stats_grid: GridContainer = $PanelContainer/TooltipContentContainer/VBoxContainer/GridContainer


func set_content(title: String, stats: Dictionary = {}) -> void:
	_title_label.text = "[b]%s[/b]" % title
	var labels = _stats_grid.get_children()
	# Hide all stat labels first
	for child in labels:
		child.visible = false
	# Populate existing labels or create new ones as needed
	var idx := 0
	for key in stats:
		var label: RichTextLabel
		if idx < labels.size():
			label = labels[idx]
		else:
			label = RichTextLabel.new()
			label.custom_minimum_size = Vector2(62, 0)
			label.bbcode_enabled = true
			label.fit_content = true
			label.scroll_active = false
			_stats_grid.add_child(label)
		label.text = "%s: %s" % [key, str(stats[key])]
		label.visible = true
		idx += 1


func _ready() -> void:
	hide()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseMotion:
		var mouse_pos = get_global_mouse_position() + OFFSET
		var viewport_rect = get_viewport_rect()
		var tooltip_size = _panel.size
		# Clamp right/bottom edge
		if mouse_pos.x + tooltip_size.x > viewport_rect.size.x:
			mouse_pos.x = viewport_rect.size.x - tooltip_size.x
		if mouse_pos.y + tooltip_size.y > viewport_rect.size.y:
			mouse_pos.y = viewport_rect.size.y - tooltip_size.y
		# Clamp left/top edge
		mouse_pos.x = max(mouse_pos.x, 0)
		mouse_pos.y = max(mouse_pos.y, 0)
		global_position = mouse_pos


func toggle(on: bool):
	if on:
		show()
		_clamp_position()
		modulate.a = 0.0
		tween_opacity(1.0)
	else:
		modulate.a = 1.0
		await tween_opacity(0.0).finished
		hide()


func _clamp_position() -> void:
	var mouse_pos = get_global_mouse_position() + OFFSET
	await get_tree().process_frame
	var vp_size = get_viewport_rect().size
	var ts = _panel.size
	if mouse_pos.x + ts.x > vp_size.x:
		mouse_pos.x = vp_size.x - ts.x
	if mouse_pos.y + ts.y > vp_size.y:
		mouse_pos.y = vp_size.y - ts.y
	mouse_pos.x = max(mouse_pos.x, 0)
	mouse_pos.y = max(mouse_pos.y, 0)
	global_position = mouse_pos


func tween_opacity(to: float):
	if opacity_tween:
		opacity_tween.kill()
	opacity_tween = get_tree().create_tween()
	opacity_tween.tween_property(self, "modulate:a", to, 0.3)

	return opacity_tween
