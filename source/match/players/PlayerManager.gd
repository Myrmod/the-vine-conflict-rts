extends Node

class_name PlayerManager

static var players: Dictionary[int, PlayerData] = {}

## Clear all player data between matches / before replays so IDs restart from 0.
static func reset():
	players.clear()

static func add_player():
	var id = players.size()
	players[id] = PlayerData.new()

	return id

static func get_player_by_id(id: int):
	return players[id]
