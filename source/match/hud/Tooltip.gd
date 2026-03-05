class_name Tooltip

extends Control

const OFFSET: Vector2 = Vector2.ONE * 15.0

var opacity_tween: Tween = null

@onready var content_container = $PanelContainer/TooltipContentContainer


func _ready() -> void:
	hide()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseMotion:
		var mouse_pos = get_global_mouse_position() + OFFSET
		var viewport_rect = get_viewport_rect()
		var tooltip_size = size
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
		modulate.a = 0.0
		tween_opacity(1.0)
	else:
		modulate.a = 1.0
		await tween_opacity(0.0).finished
		hide()


func tween_opacity(to: float):
	if opacity_tween:
		opacity_tween.kill()
	opacity_tween = get_tree().create_tween()
	opacity_tween.tween_property(self, "modulate:a", to, 0.3)

	return opacity_tween
