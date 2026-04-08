extends Node

# requests
signal deselect_all_units
signal setup_and_spawn_unit(unit, transform, player, self_constructing)
signal place_structure(structure_prototype)
signal schedule_navigation_rebake(domain)
signal navigate_unit_to_rally_point(unit, rally_point)  # currently, only for human players

# notifications
signal match_started
signal match_aborted
signal match_finished_with_victory
signal match_finished_with_defeat
signal tick_advanced  # emitted after each deterministic tick is processed (use instead of wall-clock timers)
signal terrain_targeted(position)
## Emitted with per-unit spread targets when a move command is issued.
## targets is Array of [unit, Vector3] pairs.
signal movement_targets_assigned(targets)
## Emitted every frame during a right-click drag on terrain (formation spread).
signal terrain_drag_updated(start_position, current_position)
## Emitted when a right-click drag on terrain ends (mouse released).
signal terrain_drag_finished(start_position, end_position)
signal unit_spawned(unit)
signal unit_targeted(unit)
signal unit_selected(unit)
signal unit_deselected(unit)
signal unit_damaged(unit)
signal unit_died(unit)
signal unit_production_started(unit_prototype, producer_unit)
signal unit_production_finished(unit, producer_unit)
signal unit_construction_finished(unit)
signal not_enough_resources_for_production(player)
signal not_enough_resources_for_construction(player)
signal structure_placement_started
signal structure_placement_ended

signal player_resource_changed(player, value: int, type: Enums.ResourceType)

## Structure action mode (repair / sell / disable)
signal structure_action_started(action_type: Enums.CommandType)
signal structure_action_ended
signal structure_disabled_changed(unit)
signal control_group_changed(group_id: int)

## Set by StructurePlacementHandler before emitting structure_placement_started
## so BuildRadius nodes know which radius (land or water) to display.
var current_placement_domains: Array = []

## Currently active structure action type, or -1 if none.
var current_structure_action: int = -1

## Set true by Targetability when a unit is right-click targeted.  Terrain
## checks (and clears) this on right-click release so the move command is
## suppressed when the player intended to interact with a unit, not the ground.
var unit_targeted_this_click: bool = false

## Currently active unit command mode (NORMAL, ATTACK_MOVE, MOVE, PATROL).
## Set by hotkey press; consumed by the next left-click on terrain.
var active_command_mode: int = Enums.UnitCommandMode.NORMAL
signal command_mode_changed(mode)

## Set by Hud before emitting place_structure so StructurePlacementHandler
## knows whether this is an off-field deploy or a trickle placement.
var pending_off_field_deploy: bool = false
var pending_trickle: bool = false
## Entity ID of the producer structure for off-field deploy.
var pending_off_field_producer_id: int = -1
