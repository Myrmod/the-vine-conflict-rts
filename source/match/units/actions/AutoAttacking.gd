# AutoAttacking action: Unit pursues and attacks an enemy target until the target is destroyed or out of range.
# This is a state machine action (extends Action) that manages two sub-actions:
# 1. AttackingWhileInRange: Unit stands still and attacks if target is in range
# 2. FollowingToReachDistance: Unit moves closer if target is out of range
# Transitions between them as the target moves.
#
# NOTE: This action is ASSIGNED by Match._execute_command() based on commands queued
# by either human players (via UnitActionsController) or AI systems (via AutoAttackingBattlegroup).
# The unit's _process() loop activates this action, which contains the game logic.
extends "res://source/match/units/actions/Action.gd"

const AttackingWhileInRange = preload("res://source/match/units/actions/AttackingWhileInRange.gd")
const FollowingToReachDistance = preload(
	"res://source/match/units/actions/FollowingToReachDistance.gd"
)

var _target_unit = null
var _sub_action = null
@onready var _unit = Utils.NodeEx.find_parent_with_group(self, "units")


# Check if a unit can attack a target. This validation is called by:
# 1. UnitActionsController when human selects an attack target (UI validation)
# 2. AutoAttackingBattlegroup when picking targets (AI validation)
# 3. Match._execute_command() indirectly when applying actions (command validation)
# TEAM CHECK: Units cannot attack same-team units. This is the primary team control point.
static func is_applicable(source_unit, target_unit):
	return (
		source_unit.attack_range != null
		and "player" in target_unit
		and source_unit.player != target_unit.player
		# TEAM SYSTEM: Same-team players cannot attack each other - core team mechanic
		and source_unit.player.team != target_unit.player.team
		and target_unit.movement_domain in source_unit.attack_domains
	)


func _init(target_unit):
	# Constructor is called by Match._execute_command() when applying a COMMAND.AUTO_ATTACKING command.
	# Just stores the target; no validation here (separation of concerns).
	# The actual attack logic starts in _ready() when this action node enters the scene tree.
	_target_unit = target_unit


func _ready():
	# Action has been added to unit's action stack. Set up sub-action and transitions.
	_target_unit.tree_exited.connect(_on_target_unit_removed)
	_attack_or_move_closer()


func _to_string():
	return "{0}({1})".format([super(), str(_sub_action) if _sub_action != null else ""])


func _target_in_range():
	return (
		_unit.global_position_yless.distance_to(_target_unit.global_position_yless)
		<= _unit.attack_range
	)


func _attack_or_move_closer():
	# Select sub-action based on range to target.
	# If target in range: attack immediately.
	# If target out of range: move closer until attack range reached, then transition.
	_sub_action = (
		AttackingWhileInRange.new(_target_unit)
		if _target_in_range()
		else FollowingToReachDistance.new(_target_unit, _unit.attack_range)
	)
	_sub_action.tree_exited.connect(_on_sub_action_finished)
	add_child(_sub_action)
	_unit.action_updated.emit()


func _on_target_unit_removed():
	queue_free()


func _on_sub_action_finished():
	if not is_inside_tree():
		return
	if not _target_unit.is_inside_tree():
		return
	_attack_or_move_closer()
