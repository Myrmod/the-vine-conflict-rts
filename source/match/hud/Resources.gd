extends VBoxContainer

@onready var _match = find_parent("Match")

# TODO: handle human player removal/addition


func _ready():
	await find_parent("Match").ready
	_hide_all_bars()
	_setup_all_bars()
	var local_player = _match._get_local_player()
	if _match.settings.visibility == _match.settings.Visibility.PER_PLAYER and local_player != null:
		_show_player_bars([local_player])
	else:
		_show_player_bars(get_tree().get_nodes_in_group("players"))


func _hide_all_bars():
	for bar in get_children():
		bar.hide()


func _setup_all_bars():
	var bar_nodes = get_children()
	var players = get_tree().get_nodes_in_group("players")
	for i in range(players.size()):
		bar_nodes[i].setup(players[i])


func _show_player_bars(players):
	for player in players:
		for bar_node in get_children():
			if bar_node.player == player:
				bar_node.show()
