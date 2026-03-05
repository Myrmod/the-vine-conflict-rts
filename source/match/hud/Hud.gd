extends CanvasLayer

const TOOLTIP = preload("uid://c52x883bd5etq")
var tooltip: Tooltip

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


func init_building_modification_buttons():
	disable_button.mouse_entered.connect(_on_repair_button_mouse_entered)
	disable_button.mouse_exited.connect(_on_repair_button_mouse_exited)


func _on_repair_button_mouse_entered():
	tooltip.toggle(true)


func _on_repair_button_mouse_exited():
	tooltip.toggle(false)
