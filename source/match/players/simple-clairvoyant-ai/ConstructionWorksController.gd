extends Node

const Structure = preload("res://source/match/units/Structure.gd")
const Worker = preload("res://source/match/units/Worker.gd")
const Constructing = preload("res://source/match/units/actions/Constructing.gd")

# Tick-based refresh interval. At TICK_RATE 10, 5 ticks = 0.5 s.
const REFRESH_INTERVAL_TICKS = 5

var _player = null
var _ticks_until_refresh = REFRESH_INTERVAL_TICKS


func setup(player):
	_player = player
	MatchSignals.tick_advanced.connect(_on_tick_advanced)


func _on_tick_advanced():
	_ticks_until_refresh -= 1
	if _ticks_until_refresh > 0:
		return
	_ticks_until_refresh = REFRESH_INTERVAL_TICKS
	_on_refresh()


func _on_refresh():
	var workers = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is Worker and unit.player == _player
	)
	if workers.any(func(worker): return worker.action != null and worker.action is Constructing):
		return
	var structures_to_construct = get_tree().get_nodes_in_group("units").filter(
		func(unit):
			return (
				unit is Structure
				and not unit.is_constructed()
				and not unit._self_constructing
				and unit.player == _player
			)
	)
	if not structures_to_construct.is_empty() and not workers.is_empty():
		# TODO: introduce some algortihm based on distances
		MatchUtils.rng_shuffle(workers)
		MatchUtils.rng_shuffle(structures_to_construct)
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.CONSTRUCTING,
			"player_id": _player.id,
			"data": {
				"structure": structures_to_construct[0].id,
				"selected_constructors": [{
					"unit": workers[0].id,
					"pos": workers[0].global_position,
					"rot": workers[0].global_rotation,
				}],
			}
		})
