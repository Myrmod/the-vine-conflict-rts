extends CanvasLayer

const TOOLTIP = preload("res://source/utils/Tooltip.tscn")
const Structure = preload("res://source/match/units/Structure.gd")

## Tab-switching hotkeys: Q W E R T Y.
## We use physical scancodes so this adapts to layout automatically:
## QWERTY → Q W E R T Y, QWERTZ → Q W E R T Z, AZERTY → A Z E R T Y
const TAB_HOTKEY_PHYSICAL_KEYS: Array[Key] = [
	KEY_Q,
	KEY_W,
	KEY_E,
	KEY_R,
	KEY_T,
	KEY_Y,
]

## Labels for the physical tab keys (used in tooltips).
const TAB_HOTKEY_LABELS: Array[String] = [
	"Q",
	"W",
	"E",
	"R",
	"T",
	"Z",
]

## Structure action hotkeys
## Physical U → Repair, I → Sell, O → Disable
const ACTION_HOTKEYS: Dictionary = {
	KEY_U: Enums.CommandType.REPAIR_ENTITY,
	KEY_I: Enums.CommandType.SELL_ENTITY,
	KEY_O: Enums.CommandType.DISABLE_ENTITY,
}

## TODO: in replay mode we change the UI
@export var is_replay_mode: bool = false

var tooltip: Tooltip
var current_player: PlayerSettings
var _visible_player_id: int = 0
var _faction_grid_data: Dictionary = {}
var _active_tab_type: int = Enums.ProductionTabType.STRUCTURE
## Structures owned by the local player that produce items for _active_tab_type
var _active_producers: Array = []
## Index into _active_producers for the currently selected producer
var _active_producer_index: int = 0

## Currently observed production queue for grid button display
var _grid_observed_queue = null
## Map of scene_path → grid Button for the current grid layout
var _grid_scene_to_button: Dictionary = {}
## Map of slot index → scene_path for hotkey resolution
var _grid_slot_to_scene: Dictionary = {}
## Tracks whether a slot is a structure (true) or unit (false) for hotkey handling
var _grid_slot_is_structure: Dictionary = {}

@onready var super_weapons_container: GridContainer = $SuperWeaponsHBoxContainer
@onready var game_timer_richtext_label: RichTextLabel = $GameTimer/Panel/BoxContainer/RichTextLabel
@onready var production_queue: ProductionQueue = $ProductionQueue
@onready
var unit_portrait_viewport: SubViewport = $UnitInfoVBoxContainer/UnitPortraitMarginContainer/UnitPortrait/MarginContainer/UnitPortraitViewport
@onready
var unit_ability_container: HBoxContainer = $UnitInfoVBoxContainer/MarginContainer/AbilityHBoxContainer
@onready var support_powers_container: GridContainer = $"LeftMarginContainer/Support Powers"
@onready
var energy_bar: ProgressBar = $RightMarginContainer/HBoxContainer/LeftVBoxContainer/MarginContainer/EnergyBar
@onready
var minimap: PanelContainer = $RightMarginContainer/HBoxContainer/RightVBoxContainer/MapMarginContainer/Minimap

# BuildingModificationMenuTabs
@onready
var repair_button: Button = $RightMarginContainer/HBoxContainer/RightVBoxContainer/ProductionMenuTabs/VBoxContainer/HBoxContainer/RepairButton
@onready
var sell_button: Button = $RightMarginContainer/HBoxContainer/RightVBoxContainer/ProductionMenuTabs/VBoxContainer/HBoxContainer/SellButton
@onready
var disable_button: Button = $RightMarginContainer/HBoxContainer/RightVBoxContainer/ProductionMenuTabs/VBoxContainer/HBoxContainer/DisableButton

# ResourcesContainer
@onready
var credits_label: Label = $RightMarginContainer/HBoxContainer/RightVBoxContainer/ProductionMenuTabs/VBoxContainer/HBoxContainer/ResourcesContainer/Panel/HBoxContainer/Credits
@onready
var secondary_resource_label: Label = $RightMarginContainer/HBoxContainer/RightVBoxContainer/ProductionMenuTabs/VBoxContainer/HBoxContainer/ResourcesContainer/Panel/HBoxContainer/Secondary

# Production
@onready
var production_tab_bar: TabBar = $RightMarginContainer/HBoxContainer/RightVBoxContainer/ProductionMenuTabs/VBoxContainer/ProductionTabBar
@onready
var production_tab_bar_overflow: TabBar = $RightMarginContainer/HBoxContainer/RightVBoxContainer/ProductionMenuTabs/VBoxContainer/ProductionTabBarOverflow
@onready
var production_grid: GridContainer = $RightMarginContainer/HBoxContainer/RightVBoxContainer/ProductionMenuTabs/VBoxContainer/ProductionGrid

# ControlGroups
@onready
var control_groups_container: VBoxContainer = $RightMarginContainer/HBoxContainer/RightVBoxContainer/HBoxContainer/ControlGroupsVBoxContainer


func _ready() -> void:
	tooltip = TOOLTIP.instantiate()
	add_child(tooltip)

	init_building_modification_buttons()

	production_tab_bar.tab_changed.connect(_on_production_tab_changed)
	production_tab_bar_overflow.tab_changed.connect(_on_overflow_tab_changed)

	# Show hotkey in tab tooltips
	for i in range(production_tab_bar.tab_count):
		if i < TAB_HOTKEY_LABELS.size():
			var tab_name := production_tab_bar.get_tab_title(i)
			production_tab_bar.set_tab_tooltip(i, "%s  [%s]" % [tab_name, TAB_HOTKEY_LABELS[i]])

	MatchSignals.tick_advanced.connect(set_timer)
	MatchSignals.unit_spawned.connect(_on_unit_changed)
	MatchSignals.unit_died.connect(_on_unit_changed)
	MatchSignals.unit_construction_finished.connect(_on_unit_changed)
	MatchSignals.unit_construction_finished.connect(_on_structure_construction_finished)
	MatchSignals.structure_disabled_changed.connect(_on_unit_changed)
	MatchSignals.player_resource_changed.connect(update_resource_label)
	MatchSignals.unit_selected.connect(_on_structure_selected)

	production_tab_bar.tab_clicked.connect(_on_production_tab_clicked)
	production_tab_bar_overflow.tab_clicked.connect(_on_overflow_tab_clicked)


func _process(_delta: float) -> void:
	# Update grid button timers every frame so the countdown stays current.
	_update_all_grid_button_displays()


func init_building_modification_buttons():
	repair_button.pressed.connect(
		func(): MatchSignals.structure_action_started.emit(Enums.CommandType.REPAIR_ENTITY)
	)
	sell_button.pressed.connect(
		func(): MatchSignals.structure_action_started.emit(Enums.CommandType.SELL_ENTITY)
	)
	disable_button.pressed.connect(
		func(): MatchSignals.structure_action_started.emit(Enums.CommandType.DISABLE_ENTITY)
	)

	repair_button.mouse_entered.connect(_on_action_button_hover.bind("Repair", "U"))
	repair_button.mouse_exited.connect(_on_production_button_exit)
	sell_button.mouse_entered.connect(_on_action_button_hover.bind("Sell", "I"))
	sell_button.mouse_exited.connect(_on_production_button_exit)
	disable_button.mouse_entered.connect(_on_action_button_hover.bind("Disable", "O"))
	disable_button.mouse_exited.connect(_on_production_button_exit)


func _on_action_button_hover(action_name: String, hotkey: String) -> void:
	tooltip.set_content("%s  [%s]" % [action_name, hotkey], {})
	tooltip.toggle(true)


func set_timer():
	if Match.tick % MatchConstants.TICK_RATE == 0:
		game_timer_richtext_label.text = Utils.seconds_to_time(
			Match.tick / MatchConstants.TICK_RATE
		)


func set_replay_mode(mode: bool) -> void:
	is_replay_mode = mode


func set_player_settings(settings: MatchSettings):
	current_player = settings.players[settings.visible_player]
	_visible_player_id = settings.visible_player

	_set_player_faction()

	# set starting resources
	if Factions.get_starting_resource()["energy"] != 0:
		energy_bar.value = Factions.get_starting_resource()["energy"]
	else:
		energy_bar.visible = false

	# TODO: implement for relevant factions
	secondary_resource_label.visible = false


func _set_player_faction():
	var faction_class = Factions.get_faction_by_enum(current_player.faction)
	faction_class.init()
	_faction_grid_data = Factions.get_production_grid()
	_active_tab_type = Enums.ProductionTabType.STRUCTURE
	production_tab_bar.current_tab = _active_tab_type
	_refresh_tab()


## Called when the player clicks a different production tab (STRUCTURE, DEFENCES, etc.)
func _on_production_tab_changed(tab_index: int) -> void:
	_active_tab_type = tab_index
	_refresh_tab()


## Called when the player clicks a different producer in the overflow bar
func _on_overflow_tab_changed(tab_index: int) -> void:
	_active_producer_index = tab_index
	_update_observed_producer()


## Called when any unit spawns, dies, or finishes construction — refresh if relevant
func _on_unit_changed(_unit) -> void:
	_refresh_tab()


## When a controlled structure is selected, switch to its first production tab
func _on_structure_selected(unit) -> void:
	if not unit is Structure:
		return
	if not unit.is_in_group("controlled_units"):
		return
	if unit.produces.is_empty():
		return
	if unit.is_under_construction():
		return
	var tab_type: int = unit.produces[0]
	if tab_type != _active_tab_type:
		production_tab_bar.current_tab = tab_type
	# Select this structure in the overflow if it's among the producers
	var producers = _find_producers_for_tab(tab_type)
	var idx = producers.find(unit)
	if idx >= 0 and idx != _active_producer_index:
		_active_producer_index = idx
		if production_tab_bar_overflow.tab_count > idx:
			production_tab_bar_overflow.current_tab = idx
		else:
			_update_observed_producer()


## When a selected structure finishes construction, switch to its production tab
func _on_structure_construction_finished(unit) -> void:
	if not unit is Structure:
		return
	if not unit.is_in_group("selected_units"):
		return
	if not unit.is_in_group("controlled_units"):
		return
	if unit.produces.is_empty():
		return
	var tab_type: int = unit.produces[0]
	if tab_type != _active_tab_type:
		production_tab_bar.current_tab = tab_type
	var producers = _find_producers_for_tab(tab_type)
	var idx = producers.find(unit)
	if idx >= 0:
		_active_producer_index = idx
		if production_tab_bar_overflow.tab_count > idx:
			production_tab_bar_overflow.current_tab = idx
		else:
			_update_observed_producer()


## Double-click on production tab → move camera to active structure
var _last_tab_click_time: int = 0
var _last_tab_click_index: int = -1
var _last_tab_hotkey_time: int = 0
var _last_tab_hotkey_index: int = -1
const TAB_DOUBLE_CLICK_MS = 500


func _on_production_tab_clicked(tab_index: int) -> void:
	var now = Time.get_ticks_msec()
	if tab_index == _last_tab_click_index and now - _last_tab_click_time <= TAB_DOUBLE_CLICK_MS:
		_move_camera_to_active_producer()
		_last_tab_click_index = -1
		_last_tab_click_time = 0
	else:
		_last_tab_click_index = tab_index
		_last_tab_click_time = now


## Double-click on overflow tab → move camera to that structure
var _last_overflow_click_time: int = 0
var _last_overflow_click_index: int = -1


func _on_overflow_tab_clicked(tab_index: int) -> void:
	var now = Time.get_ticks_msec()
	if (
		tab_index == _last_overflow_click_index
		and now - _last_overflow_click_time <= TAB_DOUBLE_CLICK_MS
	):
		_move_camera_to_active_producer()
		_last_overflow_click_index = -1
		_last_overflow_click_time = 0
	else:
		_last_overflow_click_index = tab_index
		_last_overflow_click_time = now


func _move_camera_to_active_producer() -> void:
	if _active_producers.is_empty():
		return
	var idx := clampi(_active_producer_index, 0, _active_producers.size() - 1)
	var structure = _active_producers[idx]
	if structure == null or not is_instance_valid(structure):
		return
	var camera = get_viewport().get_camera_3d()
	if camera and camera.has_method("set_position_safely"):
		camera.set_position_safely(structure.global_position)


## Master refresh: updates overflow bar + production grid for the active tab type
func _refresh_tab() -> void:
	_refresh_overflow_bar()
	_populate_production_grid(_faction_grid_data, _active_tab_type)


## Find all controlled structures that produce items for the active tab type,
## populate the overflow bar with them, and clamp the selected index.
func _refresh_overflow_bar() -> void:
	_active_producers = _find_producers_for_tab(_active_tab_type)
	_active_producer_index = clampi(
		_active_producer_index, 0, maxi(_active_producers.size() - 1, 0)
	)

	# Hide overflow when 0-1 producers, show otherwise
	production_tab_bar_overflow.visible = (_active_producers.size() > 1)

	# Block tab_changed while rebuilding to avoid resetting index
	if production_tab_bar_overflow.tab_changed.is_connected(_on_overflow_tab_changed):
		production_tab_bar_overflow.tab_changed.disconnect(_on_overflow_tab_changed)

	# Clear existing tabs
	while production_tab_bar_overflow.tab_count > 0:
		production_tab_bar_overflow.remove_tab(0)

	for i in range(_active_producers.size()):
		production_tab_bar_overflow.add_tab(str(i + 1))

	if not _active_producers.is_empty():
		production_tab_bar_overflow.current_tab = (_active_producer_index)

	# Reconnect after rebuild
	production_tab_bar_overflow.tab_changed.connect(_on_overflow_tab_changed)

	_update_observed_producer()


## Tell the HUD ProductionQueue widget to observe all producers,
## and the grid to observe only the active one.
func _update_observed_producer() -> void:
	_detach_grid_queue()
	# Global queue observes ALL producing structures
	var all_producers := _find_all_producers()
	production_queue.observe_structures(all_producers)
	if _active_producers.is_empty():
		_update_all_grid_button_displays()
		return
	var idx := clampi(_active_producer_index, 0, _active_producers.size() - 1)
	var structure = _active_producers[idx]
	_attach_grid_queue(structure)


## Return all constructed, controlled structures whose `produces` array contains tab_type.
func _find_producers_for_tab(tab_type: int) -> Array:
	var result: Array = []
	var controlled = get_tree().get_nodes_in_group("controlled_units")
	for unit in controlled:
		if not "produces" in unit:
			continue
		if unit.produces.is_empty():
			continue
		if unit.is_under_construction():
			continue
		if "is_disabled" in unit and unit.is_disabled:
			continue
		if unit.produces.has(tab_type):
			result.append(unit)
	return result


## Return ALL constructed, controlled structures that have a ProductionQueue.
func _find_all_producers() -> Array:
	var result: Array = []
	var controlled = get_tree().get_nodes_in_group("controlled_units")
	for unit in controlled:
		if not "production_queue" in unit:
			continue
		if unit.production_queue == null:
			continue
		if unit.is_under_construction():
			continue
		if "is_disabled" in unit and unit.is_disabled:
			continue
		result.append(unit)
	return result


func _populate_production_grid(grid_data: Dictionary, tab_type: int) -> void:
	var buttons = production_grid.get_children()
	var hs = Globals.hotkey_settings
	var has_producer := not _active_producers.is_empty()
	_grid_scene_to_button.clear()
	_grid_slot_to_scene.clear()
	_grid_slot_is_structure.clear()
	# Reset all buttons to empty state
	for i in range(buttons.size()):
		var button: Button = buttons[i]
		button.icon = null
		button.text = ""
		button.disabled = true
		_disconnect_all(button.mouse_entered)
		_disconnect_all(button.mouse_exited)
		_disconnect_all(button.pressed)
		_disconnect_all(button.gui_input)
		_ensure_grid_labels(button)
		_update_grid_button_queue_display(button, "")

	# Assign entries to their designated grid slot
	var entries = grid_data.get(tab_type, [])
	for entry in entries:
		var slot: int = entry.get("production_tab_grid_slot", -1)
		if slot < 0 or slot >= buttons.size():
			continue
		var button: Button = buttons[slot]
		var scene_path: String = entry.get("scene_path", "")
		var unit_name := scene_path.get_file().get_basename()
		var icon_path := "res://assets/ui/icons/%s.png" % unit_name
		# Disable when no producer structure exists for this tab
		button.disabled = not has_producer
		button.expand_icon = true
		if ResourceLoader.exists(icon_path):
			button.icon = load(icon_path)
		else:
			button.text = unit_name[0]

		_grid_scene_to_button[scene_path] = button
		_grid_slot_to_scene[slot] = scene_path

		var slot_name: String = hs.SLOT_NAMES[slot] if slot < hs.SLOT_NAMES.size() else ""
		var hotkey_label: String = hs.get_key_label(slot_name) if slot_name != "" else ""
		var stats := _build_entry_stats(entry)
		button.mouse_entered.connect(
			_on_production_button_hover.bind(unit_name, stats, hotkey_label)
		)
		button.mouse_exited.connect(_on_production_button_exit)

		var is_structure := UnitConstants.STRUCTURE_BLUEPRINTS.has(scene_path)
		_grid_slot_is_structure[slot] = is_structure
		if is_structure:
			button.gui_input.connect(_on_structure_grid_button_gui_input.bind(scene_path))
		else:
			button.gui_input.connect(_on_grid_button_gui_input.bind(scene_path))

	_update_all_grid_button_displays()


## Decide whether to place a structure or queue unit production.
func _on_production_button_pressed(scene_path: String) -> void:
	var is_structure := UnitConstants.STRUCTURE_BLUEPRINTS.has(scene_path)
	if is_structure:
		var prototype = load(scene_path)
		if prototype:
			MatchSignals.place_structure.emit(prototype)
	else:
		if _active_producers.is_empty():
			return
		var idx := clampi(_active_producer_index, 0, _active_producers.size() - 1)
		var producer = _active_producers[idx]
		if producer == null or not is_instance_valid(producer):
			return
		ProductionQueue._generate_unit_production_command(
			producer.id, scene_path, producer.player.id
		)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return

	# Tab-switching hotkeys (Q W E R) via physical keycode
	var physical: Key = event.physical_keycode

	# Structure action hotkeys (T, Y/Z, U)
	if ACTION_HOTKEYS.has(physical):
		MatchSignals.structure_action_started.emit(ACTION_HOTKEYS[physical])
		get_viewport().set_input_as_handled()
		return

	for i in range(TAB_HOTKEY_PHYSICAL_KEYS.size()):
		if physical == TAB_HOTKEY_PHYSICAL_KEYS[i]:
			if i < production_tab_bar.tab_count:
				var now = Time.get_ticks_msec()
				if production_tab_bar.current_tab == i:
					if (
						i == _last_tab_hotkey_index
						and now - _last_tab_hotkey_time <= TAB_DOUBLE_CLICK_MS
					):
						_move_camera_to_active_producer()
						_last_tab_hotkey_index = -1
						_last_tab_hotkey_time = 0
					elif _active_producers.size() > 1:
						var next := (_active_producer_index + 1) % _active_producers.size()
						production_tab_bar_overflow.current_tab = next
						_last_tab_hotkey_index = i
						_last_tab_hotkey_time = now
					else:
						_last_tab_hotkey_index = i
						_last_tab_hotkey_time = now
				else:
					production_tab_bar.current_tab = i
					_last_tab_hotkey_index = -1
					_last_tab_hotkey_time = 0
			get_viewport().set_input_as_handled()
			return

	# Production grid hotkeys
	var hs = Globals.hotkey_settings
	var buttons = production_grid.get_children()
	for i in range(buttons.size()):
		var slot = hs.SLOT_NAMES[i]
		if not hs.bindings.has(slot):
			continue
		if event.keycode == hs.bindings[slot] and not buttons[i].disabled:
			var sp: String = _grid_slot_to_scene.get(i, "")
			if sp != "":
				_on_production_button_pressed(sp)
			get_viewport().set_input_as_handled()
			return


static func _disconnect_all(sig: Signal) -> void:
	for conn in sig.get_connections():
		sig.disconnect(conn["callable"])


static func _build_entry_stats(entry: Dictionary) -> Dictionary:
	var stats := {}
	if entry.has("hp_max"):
		stats["HP"] = entry["hp_max"]
	if entry.has("costs"):
		stats["Cost"] = entry["costs"].get("resource", 0)
	if entry.has("build_time"):
		stats["Build"] = "%ss" % entry["build_time"]
	return stats


func _on_production_button_hover(
	unit_name: String, stats: Dictionary, hotkey_label: String
) -> void:
	var title := unit_name
	if hotkey_label != "":
		title += "  [%s]" % hotkey_label
	tooltip.set_content(title, stats)
	tooltip.toggle(true)


func _on_production_button_exit() -> void:
	tooltip.toggle(false)


# ── PRODUCTION GRID QUEUE DISPLAY ──────────────────────────────────────────


## Ensure a grid button has TimeLabel and CountLabel children.
func _ensure_grid_labels(button: Button) -> void:
	if not button.has_node("TimeLabel"):
		var tl := Label.new()
		tl.name = "TimeLabel"
		tl.add_theme_font_size_override("font_size", 10)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		tl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		tl.offset_left = -60
		tl.offset_top = -16
		tl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		tl.grow_vertical = Control.GROW_DIRECTION_BEGIN
		tl.visible = false
		button.add_child(tl)
	if not button.has_node("CountLabel"):
		var cl := Label.new()
		cl.name = "CountLabel"
		cl.add_theme_font_size_override("font_size", 10)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		cl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		cl.set_anchors_preset(Control.PRESET_TOP_LEFT)
		cl.offset_right = 24
		cl.offset_bottom = 16
		cl.visible = false
		button.add_child(cl)


func _detach_grid_queue() -> void:
	if _grid_observed_queue != null:
		if _grid_observed_queue.element_enqueued.is_connected(_on_grid_queue_changed):
			_grid_observed_queue.element_enqueued.disconnect(_on_grid_queue_changed)
		if _grid_observed_queue.element_removed.is_connected(_on_grid_queue_changed):
			_grid_observed_queue.element_removed.disconnect(_on_grid_queue_changed)
		_grid_observed_queue = null


func _attach_grid_queue(structure) -> void:
	if structure == null or not is_instance_valid(structure):
		_update_all_grid_button_displays()
		return
	if not "production_queue" in structure or structure.production_queue == null:
		_update_all_grid_button_displays()
		return
	_grid_observed_queue = structure.production_queue
	_grid_observed_queue.element_enqueued.connect(_on_grid_queue_changed)
	_grid_observed_queue.element_removed.connect(_on_grid_queue_changed)
	_update_all_grid_button_displays()


func _on_grid_queue_changed(_element) -> void:
	_update_all_grid_button_displays()


func _update_all_grid_button_displays() -> void:
	for scene_path in _grid_scene_to_button:
		var button: Button = _grid_scene_to_button[scene_path]
		_update_grid_button_queue_display(button, scene_path)


func _update_grid_button_queue_display(button: Button, scene_path: String) -> void:
	var time_label = button.get_node_or_null("TimeLabel")
	var count_label = button.get_node_or_null("CountLabel")
	if time_label == null or count_label == null:
		return
	if scene_path == "":
		time_label.visible = false
		count_label.visible = false
		return

	# ── Construction progress for structure slots ──
	if UnitConstants.STRUCTURE_BLUEPRINTS.has(scene_path):
		var building_count := 0
		var best_progress := 0.0
		var any_paused := false
		for unit in get_tree().get_nodes_in_group("controlled_units"):
			if not unit is Structure:
				continue
			var unit_scene: String = unit.get_script().resource_path.replace(".gd", ".tscn")
			if unit_scene != scene_path:
				continue
			if unit.is_under_construction():
				building_count += 1
				if unit.is_construction_paused:
					any_paused = true
				if unit.construction_progress > best_progress:
					best_progress = unit.construction_progress
		if building_count > 0:
			var pct := int(best_progress * 100.0)
			time_label.text = ("%d%% ||" % pct if any_paused else "%d%%" % pct)
			time_label.visible = true
			if building_count > 1:
				count_label.text = "x%d" % building_count
				count_label.visible = true
			else:
				count_label.visible = false
			return
		time_label.visible = false
		count_label.visible = false
		return

	# ── Production queue display for unit slots ──
	if _grid_observed_queue == null:
		time_label.visible = false
		count_label.visible = false
		return

	# Gather elements of this type from the observed queue
	var all_elements = _grid_observed_queue.get_elements()
	var type_elements: Array = []
	for el in all_elements:
		if el.unit_prototype.resource_path == scene_path:
			type_elements.append(el)

	if type_elements.is_empty():
		time_label.visible = false
		count_label.visible = false
		return

	# Show timer for the producing element of this type
	var producing_element = null
	for el in type_elements:
		if el.is_producing(all_elements):
			producing_element = el
			break
	if producing_element != null:
		time_label.text = "%.1fs" % producing_element.time_left
		time_label.visible = true
	else:
		time_label.visible = false

	# Show count
	if type_elements.size() > 1:
		count_label.text = "x%d" % type_elements.size()
		count_label.visible = true
	else:
		count_label.visible = false


func _on_structure_grid_button_gui_input(event: InputEvent, scene_path: String) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	# gui_input fires even on disabled buttons — block when no producer
	if _active_producers.is_empty():
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		# If a paused under-construction structure exists, resume it
		# instead of placing a new one.
		if _resume_paused_structure(scene_path):
			return
		_on_production_button_pressed(scene_path)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_building_structure(scene_path)


func _resume_paused_structure(scene_path: String) -> bool:
	## Unpause the most-progressed paused structure of this type.
	## Returns true if a command was sent, false if nothing to resume.
	var best = null
	var best_progress := -1.0
	for unit in get_tree().get_nodes_in_group("controlled_units"):
		if not unit is Structure:
			continue
		if not unit.is_under_construction():
			continue
		if not unit.is_construction_paused:
			continue
		var unit_scene: String = unit.get_script().resource_path.replace(".gd", ".tscn")
		if unit_scene != scene_path:
			continue
		if unit.construction_progress > best_progress:
			best_progress = unit.construction_progress
			best = unit
	if best == null:
		return false
	(
		CommandBus
		. push_command(
			{
				"tick": Match.tick + 1,
				"type": Enums.CommandType.PAUSE_CONSTRUCTION,
				"player_id": best.player.id,
				"data": {"entity_id": best.id},
			}
		)
	)
	return true


func _cancel_building_structure(scene_path: String) -> void:
	# Collect all under-construction structures of this type.
	var unpaused: Array = []
	var paused: Array = []
	for unit in get_tree().get_nodes_in_group("controlled_units"):
		if not unit is Structure:
			continue
		if not unit.is_under_construction():
			continue
		var unit_scene: String = unit.get_script().resource_path.replace(".gd", ".tscn")
		if unit_scene != scene_path:
			continue
		if unit.is_construction_paused:
			paused.append(unit)
		else:
			unpaused.append(unit)

	# 1st right-click: pause the least-progressed unpaused structure.
	if not unpaused.is_empty():
		var best = unpaused[0]
		for u in unpaused:
			if u.construction_progress < best.construction_progress:
				best = u
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.PAUSE_CONSTRUCTION,
					"player_id": best.player.id,
					"data": {"entity_id": best.id},
				}
			)
		)
		return

	# 2nd right-click: cancel the least-progressed paused structure.
	if not paused.is_empty():
		var best = paused[0]
		for u in paused:
			if u.construction_progress < best.construction_progress:
				best = u
		(
			CommandBus
			. push_command(
				{
					"tick": Match.tick + 1,
					"type": Enums.CommandType.CANCEL_CONSTRUCTION,
					"player_id": best.player.id,
					"data": {"entity_id": best.id},
				}
			)
		)


func _on_grid_button_gui_input(event: InputEvent, scene_path: String) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if _active_producers.is_empty():
		return
	var idx := clampi(_active_producer_index, 0, _active_producers.size() - 1)
	var producer = _active_producers[idx]
	if producer == null or not is_instance_valid(producer):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		# Left-click: if paused elements exist for this type, resume; otherwise queue
		if _grid_has_paused_elements(scene_path):
			_grid_toggle_pause(producer, scene_path)
		else:
			ProductionQueue._generate_unit_production_command(
				producer.id, scene_path, producer.player.id
			)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.shift_pressed:
			_grid_cancel_all_of_type(producer, scene_path)
		else:
			_grid_right_click(producer, scene_path)


func _grid_has_paused_elements(scene_path: String) -> bool:
	if _grid_observed_queue == null:
		return false
	for el in _grid_observed_queue.get_elements():
		if el.unit_prototype.resource_path == scene_path and el.paused:
			return true
	return false


func _grid_right_click(producer, scene_path: String) -> void:
	if _grid_observed_queue == null:
		return
	var all_elements = _grid_observed_queue.get_elements()
	var is_producing := false
	for el in all_elements:
		if el.unit_prototype.resource_path == scene_path and el.is_producing(all_elements):
			is_producing = true
			break
	if is_producing:
		_grid_toggle_pause(producer, scene_path)
	else:
		_grid_cancel_one(producer, scene_path)


func _grid_toggle_pause(producer, scene_path: String) -> void:
	(
		CommandBus
		. push_command(
			{
				"tick": Match.tick + 1,
				"type": Enums.CommandType.ENTITY_PRODUCTION_PAUSED,
				"player_id": producer.player.id,
				"data":
				{
					"entity_id": producer.id,
					"unit_type": scene_path,
				}
			}
		)
	)


func _grid_cancel_one(producer, scene_path: String) -> void:
	(
		CommandBus
		. push_command(
			{
				"tick": Match.tick + 1,
				"type": Enums.CommandType.ENTITY_PRODUCTION_CANCELED,
				"player_id": producer.player.id,
				"data":
				{
					"entity_id": producer.id,
					"unit_type": scene_path,
				}
			}
		)
	)


func _grid_cancel_all_of_type(producer, scene_path: String) -> void:
	if _grid_observed_queue == null:
		return
	for el in _grid_observed_queue.get_elements():
		if el.unit_prototype.resource_path == scene_path:
			(
				CommandBus
				. push_command(
					{
						"tick": Match.tick + 1,
						"type": Enums.CommandType.ENTITY_PRODUCTION_CANCELED,
						"player_id": producer.player.id,
						"data":
						{
							"entity_id": producer.id,
							"unit_type": scene_path,
						}
					}
				)
			)


## resource is the updated value, not the delta
func update_resource_label(player, resource: int, type: Enums.ResourceType):
	if player.id != _visible_player_id:
		return
	match type:
		Enums.ResourceType.CREDITS:
			credits_label.text = str(resource) + "$"

		Enums.ResourceType.ENERGY:
			energy_bar.value = resource

		_:
			push_warning("Resource of unknown type updated: ", type)
