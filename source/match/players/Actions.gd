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
const AttackMoving = preload("res://source/match/units/actions/AttackMoving.gd")
const HoldPosition = preload("res://source/match/units/actions/HoldPosition.gd")
const Patrolling = preload("res://source/match/units/actions/Patrolling.gd")
const ReverseMoving = preload("res://source/match/units/actions/ReverseMoving.gd")
const WaitingForTargets = preload("res://source/match/units/actions/WaitingForTargets.gd")
const Spreading = preload("res://source/match/units/actions/Spreading.gd")

# player actions
const CastSupportPowerAction = preload(
	"res://source/match/players/actions/CastSupportPowerAction.gd"
)
