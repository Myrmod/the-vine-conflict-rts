extends PanelContainer

@onready var _match = find_parent("Match")


func _on_toggle_button_pressed():
	_match.global_build_grid.toggle_debug_grid()
