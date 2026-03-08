## Manages structure action modes (Repair, Sell, Disable).
##
## When the player activates an action via the HUD button or hotkey,
## the handler enters "action mode": the cursor changes to the
## action's icon and the next left-click on an owned structure
## sends the corresponding command through CommandBus.
## Right-click or pressing the same hotkey again cancels the mode.
##
## Click detection projects controlled structures to screen space and
## picks the closest one within a generous radius (same approach used
## by ArealUnitSelectionHandler for box-select).
extends Node

const Structure = preload("res://source/match/units/Structure.gd")

const REPAIR_CURSOR = preload("res://assets/ui/icons/repair_icon.png")
const SELL_CURSOR = preload("res://assets/ui/icons/sell_icon.png")
const DISABLE_CURSOR = preload("res://assets/ui/icons/disable_icon.png")

## Maximum screen-space distance (px) from the click to accept a structure.
const PICK_RADIUS_PX := 60.0

var _active_action: int = -1

@onready var _player = get_parent()


func _ready():
	MatchSignals.structure_action_started.connect(_on_action_started)
	MatchSignals.structure_action_ended.connect(_on_action_ended)


func _unhandled_input(event: InputEvent) -> void:
	if _active_action == -1:
		return

	# Right-click cancels the action mode
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		_cancel_action()
		get_viewport().set_input_as_handled()
		return

	# Left-click: find closest owned structure near cursor
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var structure = _pick_structure_near_cursor()
		if structure != null:
			_apply_action(structure)
		_cancel_action()
		get_viewport().set_input_as_handled()


func _on_action_started(action_type: int) -> void:
	# If already in the same mode, toggle off
	if _active_action == action_type:
		_cancel_action()
		return
	_active_action = action_type
	MatchSignals.current_structure_action = action_type
	_update_cursor()


func _on_action_ended() -> void:
	_active_action = -1
	MatchSignals.current_structure_action = -1
	Input.set_custom_mouse_cursor(null)


func _cancel_action() -> void:
	_active_action = -1
	MatchSignals.current_structure_action = -1
	Input.set_custom_mouse_cursor(null)
	MatchSignals.structure_action_ended.emit()


func _update_cursor() -> void:
	var tex: Texture2D = null
	match _active_action:
		Enums.CommandType.REPAIR_ENTITY:
			tex = REPAIR_CURSOR
		Enums.CommandType.SELL_ENTITY:
			tex = SELL_CURSOR
		Enums.CommandType.DISABLE_ENTITY:
			tex = DISABLE_CURSOR
	if tex != null:
		Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2(16, 16))


## Find the closest owned structure within PICK_RADIUS_PX of the mouse.
func _pick_structure_near_cursor():
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var best_structure = null
	var best_dist := PICK_RADIUS_PX
	for unit in get_tree().get_nodes_in_group("controlled_units"):
		if not unit is Structure:
			continue
		if not unit.visible:
			continue
		var screen_pos: Vector2 = camera.unproject_position(unit.global_position)
		var dist := mouse_pos.distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best_structure = unit
	return best_structure


func _apply_action(structure) -> void:
	(
		CommandBus
		. push_command(
			{
				"tick": Match.tick + 1,
				"type": _active_action,
				"player_id": _player.id,
				"data": {"entity_id": structure.id},
			}
		)
	)
