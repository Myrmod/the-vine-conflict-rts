extends CanvasLayer

const TOOLTIP = preload("res://source/utils/Tooltip.tscn")

## Tab-switching hotkeys: Q W E R T and the key next to T.
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

## TODO: in replay mode we change the UI
@export var is_replay_mode: bool = false

var tooltip: Tooltip
var current_player: PlayerSettings
var _faction_grid_data: Dictionary = {}
var _active_tab_type: int = Enums.ProductionTabType.STRUCTURE
## Structures owned by the local player that produce items for _active_tab_type
var _active_producers: Array = []
## Index into _active_producers for the currently selected producer
var _active_producer_index: int = 0

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

	MatchSignals.tick_advanced.connect(set_timer)
	MatchSignals.unit_spawned.connect(_on_unit_changed)
	MatchSignals.unit_died.connect(_on_unit_changed)
	MatchSignals.unit_construction_finished.connect(_on_unit_changed)
	MatchSignals.player_resource_changed.connect(update_resource_label)


func init_building_modification_buttons():
	disable_button.mouse_entered.connect(_on_repair_button_mouse_entered)
	disable_button.mouse_exited.connect(_on_repair_button_mouse_exited)


func _on_repair_button_mouse_entered():
	tooltip.toggle(true)


func _on_repair_button_mouse_exited():
	tooltip.toggle(false)


func set_timer():
	if Match.tick % MatchConstants.TICK_RATE == 0:
		game_timer_richtext_label.text = Utils.seconds_to_time(
			Match.tick / MatchConstants.TICK_RATE
		)


func set_replay_mode(mode: bool) -> void:
	is_replay_mode = mode


func set_player_settings(settings: MatchSettings):
	current_player = settings.players[settings.visible_player]

	_set_player_faction()

	# set starting resources
	if Factions.get_starting_resource()["energy"] != 0:
		energy_bar.value = Factions.get_starting_resource()["energy"]
	else:
		energy_bar.visible = false


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
	production_tab_bar_overflow.visible = _active_producers.size() > 1

	# Clear existing tabs
	while production_tab_bar_overflow.tab_count > 0:
		production_tab_bar_overflow.remove_tab(0)

	for i in range(_active_producers.size()):
		var structure = _active_producers[i]
		var sname = structure.type if structure else "??"
		production_tab_bar_overflow.add_tab(sname)

	if not _active_producers.is_empty():
		production_tab_bar_overflow.current_tab = _active_producer_index

	_update_observed_producer()


## Tell the HUD ProductionQueue widget to observe the active producer.
func _update_observed_producer() -> void:
	if _active_producers.is_empty():
		production_queue.observe_structure(null)
		return
	var idx := clampi(_active_producer_index, 0, _active_producers.size() - 1)
	production_queue.observe_structure(_active_producers[idx])


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
		if unit.produces.has(tab_type):
			result.append(unit)
	return result


func _populate_production_grid(grid_data: Dictionary, tab_type: int) -> void:
	var buttons = production_grid.get_children()
	var hs = Globals.hotkey_settings
	var has_producer := not _active_producers.is_empty()
	# Reset all buttons to empty state
	for i in range(buttons.size()):
		var button: Button = buttons[i]
		button.icon = null
		button.text = ""
		button.disabled = true
		_disconnect_all(button.mouse_entered)
		_disconnect_all(button.mouse_exited)
		_disconnect_all(button.pressed)

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

		var slot_name: String = hs.SLOT_NAMES[slot] if slot < hs.SLOT_NAMES.size() else ""
		var hotkey_label: String = hs.get_key_label(slot_name) if slot_name != "" else ""
		var stats := _build_entry_stats(entry)
		button.mouse_entered.connect(
			_on_production_button_hover.bind(unit_name, stats, hotkey_label)
		)
		button.mouse_exited.connect(_on_production_button_exit)
		button.pressed.connect(_on_production_button_pressed.bind(scene_path))


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

	# Tab-switching hotkeys (Q W E R T Y/Z) via physical keycode
	var physical: Key = event.physical_keycode
	for i in range(TAB_HOTKEY_PHYSICAL_KEYS.size()):
		if physical == TAB_HOTKEY_PHYSICAL_KEYS[i]:
			if i < production_tab_bar.tab_count:
				production_tab_bar.current_tab = i
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
			buttons[i].pressed.emit()
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


## resource is the updated value, not the delta
func update_resource_label(resource: int, type: Enums.ResourceType):
	match type:
		Enums.ResourceType.CREDITS:
			credits_label.text = str(resource) + "$"

		Enums.ResourceType.ENERGY:
			energy_bar.value = resource

		_:
			push_warning("Resource of unknown type updated: ", type)
