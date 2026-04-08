extends CanvasLayer

@onready var _victory_tile = find_child("Victory")
@onready var _defeat_tile = find_child("Defeat")
@onready var _finish_tile = find_child("Finish")
@onready var _vbox = find_child("VBoxContainer")

var _stats_tracker: Node = null


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
	_setup_stats_tracker()


func _setup_stats_tracker() -> void:
	_stats_tracker = preload("res://source/match/handlers/MatchStatisticsTracker.gd").new()
	_stats_tracker.name = "MatchStatisticsTracker"
	add_child(_stats_tracker)


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
	_build_statistics_panel()
	# Suppress disconnect overlay in multiplayer
	var overlay = get_tree().current_scene.find_child("MatchOverlay")
	if overlay != null and overlay.has_method("set_match_finished"):
		overlay.set_match_finished()


func _build_statistics_panel() -> void:
	var players: Array = get_tree().get_nodes_in_group("players")
	if players.is_empty() or _stats_tracker == null:
		return
	var summary: Array = _stats_tracker.get_summary(players)

	var stats_label := Label.new()
	stats_label.text = "Statistics"
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 22)
	# Insert before the exit button (last child)
	_vbox.add_child(stats_label)
	_vbox.move_child(stats_label, _vbox.get_child_count() - 2)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 4)
	_vbox.add_child(grid)
	_vbox.move_child(grid, _vbox.get_child_count() - 2)

	# Header row
	for header in [
		"Player",
		"Credits",
		"Units Built",
		"Units Lost",
		"Structures Built",
		"Structures Lost",
	]:
		var lbl := Label.new()
		lbl.text = header
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		grid.add_child(lbl)

	# Data rows
	for s in summary:
		var pcolor: Color = s["color"]
		var values := [
			"Player %d" % (s["player_id"] + 1),
			str(s["credits"]),
			str(s["units_produced"]),
			str(s["units_lost"]),
			str(s["structures_built"]),
			str(s["structures_lost"]),
		]
		for i in range(values.size()):
			var lbl := Label.new()
			lbl.text = values[i]
			lbl.add_theme_font_size_override("font_size", 16)
			if i == 0:
				lbl.add_theme_color_override("font_color", pcolor)
			grid.add_child(lbl)


func _on_new_unit(unit, _transform, _player, _self_constructing = false):
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

	var local_player = find_parent("Match")._get_local_player()

	if local_player == null:
		# No local player, just check if one team remains
		if units_by_team.size() == 1:
			_handle_finish()
		return

	var local_team = local_player.team
	var local_team_has_units = (
		local_team in units_by_team and not units_by_team[local_team].is_empty()
	)

	if not local_team_has_units:
		_handle_defeat()
	elif units_by_team.size() == 1:
		_handle_victory()
	elif units_by_team.size() > 1:
		# Multiple teams still exist, no end condition yet
		pass


func _on_exit_button_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")
