class_name Actions extends Node

# unit actions
const Moving = preload("res://source/match/units/actions/Moving.gd")
const MovingToUnit = preload("res://source/match/units/actions/MovingToUnit.gd")
const Following = preload("res://source/match/units/actions/Following.gd")
const CollectingResourcesSequentially = preload(
	"res://source/match/units/actions/CollectingResourcesSequentially.gd"
)
const AutoAttacking = preload("res://source/match/units/actions/AutoAttacking.gd")
const Constructing = preload("res://source/match/units/actions/Constructing.gd")
const EntityIsQueued = preload("res://source/match/units/actions/EntityIsQueued.gd")

# player actions
const CastSupportPowerAction = preload(
	"res://source/match/players/actions/CastSupportPowerAction.gd"
)
const DisableAction = preload("res://source/match/players/actions/DisableAction.gd")
const RepairAction = preload("res://source/match/players/actions/RepairAction.gd")
const SellAction = preload("res://source/match/players/actions/SellAction.gd")
