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

signal player_resource_changed(credits: int, type: Enums.ResourceType)

## Structure action mode (repair / sell / disable)
signal structure_action_started(action_type: Enums.CommandType)
signal structure_action_ended
signal structure_disabled_changed(unit)

## Set by StructurePlacementHandler before emitting structure_placement_started
## so BuildRadius nodes know which radius (land or water) to display.
var current_placement_domains: Array = []

## Currently active structure action type, or -1 if none.
var current_structure_action: int = -1
