extends GridHotkeys

const Structure = preload("res://source/match/units/Structure.gd")

var units = []

func _ready():
	super._ready()

func _on_cancel_action_button_pressed():
	if len(units) == 1 and units[0] is Structure and units[0].is_under_construction():
		# Cancel construction through CommandBus (refunds resources + frees structure)
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.CANCEL_CONSTRUCTION,
			"player_id": units[0].player.id,
			"data": {
				"entity_id": units[0].id,
			}
		})
		return
	for unit in units:
		CommandBus.push_command({
			"tick": Match.tick + 1,
			"type": Enums.CommandType.ACTION_CANCEL,
			"player_id": unit.player.id,
			"data": {
				"targets": [{"unit": unit.id, "pos": unit.global_position, "rot": unit.global_rotation}],
			}
		})
