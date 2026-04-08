extends Node

## Tracks per-player economy and military statistics during a match.

const Structure = preload("res://source/match/units/Structure.gd")

# player_id → { units_produced, units_lost, units_killed,
#                structures_built, resources_spent, resources_earned }
var stats: Dictionary = {}


func _ready() -> void:
	MatchSignals.unit_spawned.connect(_on_unit_spawned)
	MatchSignals.unit_died.connect(_on_unit_died)
	MatchSignals.unit_production_finished.connect(_on_unit_production_finished)
	MatchSignals.unit_construction_finished.connect(_on_unit_construction_finished)


func _ensure_player(player_id: int) -> void:
	if player_id not in stats:
		stats[player_id] = {
			"units_produced": 0,
			"units_lost": 0,
			"structures_built": 0,
			"structures_lost": 0,
		}


func _on_unit_spawned(_unit) -> void:
	pass


func _on_unit_died(unit) -> void:
	if unit == null or unit.player == null:
		return
	var owner_id: int = unit.player.id
	_ensure_player(owner_id)
	if unit is Structure:
		stats[owner_id]["structures_lost"] += 1
	else:
		stats[owner_id]["units_lost"] += 1


func _on_unit_production_finished(_unit, _producer) -> void:
	if _producer == null or _producer.player == null:
		return
	var pid: int = _producer.player.id
	_ensure_player(pid)
	stats[pid]["units_produced"] += 1


func _on_unit_construction_finished(unit) -> void:
	if unit == null or unit.player == null:
		return
	var pid: int = unit.player.id
	_ensure_player(pid)
	stats[pid]["structures_built"] += 1


## Build a summary array for showing in the end screen.
func get_summary(players: Array) -> Array:
	var result: Array = []
	for p in players:
		_ensure_player(p.id)
		var s: Dictionary = stats[p.id]
		(
			result
			. append(
				{
					"player_id": p.id,
					"color": p.color,
					"team": p.team,
					"credits": p.credits,
					"units_produced": s["units_produced"],
					"units_lost": s["units_lost"],
					"structures_built": s["structures_built"],
					"structures_lost": s["structures_lost"],
				}
			)
		)
	return result
