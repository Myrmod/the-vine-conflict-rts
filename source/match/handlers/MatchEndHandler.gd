extends CanvasLayer

const Human = preload("res://source/match/players/human/Human.gd")

@onready var _victory_tile = find_child("Victory")
@onready var _defeat_tile = find_child("Defeat")
@onready var _finish_tile = find_child("Finish")


func _ready():
	if not FeatureFlags.handle_match_end:
		queue_free()
		return
	hide()
	_victory_tile.hide()
	_defeat_tile.hide()
	_finish_tile.hide()
	await find_parent("Match").ready
	MatchSignals.setup_and_spawn_unit.connect(_on_new_unit)
	for unit in get_tree().get_nodes_in_group("units"):
		unit.tree_exited.connect(_on_unit_tree_exited)


func _handle_defeat():
	_defeat_tile.show()
	_show()
	MatchSignals.match_finished_with_defeat.emit()


func _handle_victory():
	_victory_tile.show()
	_show()
	MatchSignals.match_finished_with_victory.emit()


func _handle_finish():
	_finish_tile.show()
	_show()


func _show():
	show()
	get_tree().paused = true


func _on_new_unit(unit, _transform, _player):
	unit.tree_exited.connect(_on_unit_tree_exited)


func _on_unit_tree_exited():
	if visible or not is_inside_tree():
		return
	var units_by_team = {}
	for unit in get_tree().get_nodes_in_group("units"):
		var team = unit.player.team
		if not team in units_by_team:
			units_by_team[team] = []
		units_by_team[team].append(unit)
	
	var human_players = get_tree().get_nodes_in_group("players").filter(
		func(player): return player is Human
	)
	
	if human_players.is_empty():
		# No human player, just check if one team remains
		if units_by_team.size() == 1:
			_handle_finish()
		return
	
	var human_player = human_players[0]
	var human_team = human_player.team
	var human_team_has_units = human_team in units_by_team and not units_by_team[human_team].is_empty()
	
	if not human_team_has_units:
		_handle_defeat()
	elif units_by_team.size() == 1:
		_handle_victory()
	elif units_by_team.size() > 1:
		# Multiple teams still exist, no end condition yet
		pass


func _on_exit_button_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")
