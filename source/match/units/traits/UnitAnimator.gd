extends Node3D

## Reusable trait that plays animations on a sibling ModelHolder's AnimationPlayer
## based on the unit's current action.
##
## Add as a child of any unit scene alongside a ModelHolder node.
## Configure animation names via exports to match the model's animation library.

const Moving = preload("res://source/match/units/actions/Moving.gd")
const MovingToUnit = preload("res://source/match/units/actions/MovingToUnit.gd")
const AttackMoving = preload("res://source/match/units/actions/AttackMoving.gd")
const Patrolling = preload("res://source/match/units/actions/Patrolling.gd")
const FollowingToReachDistance = preload(
	"res://source/match/units/actions/FollowingToReachDistance.gd"
)
const Following = preload("res://source/match/units/actions/Following.gd")

@export var idle_animation: String = "RESET"
@export var move_animation: String = "Run 50_"
@export var attack_move_animation: String = "Run 100_"
@export var attack_animation: String = "Idle 100_"

var _anim_player: AnimationPlayer = null

@onready var _unit = get_parent()


func _ready():
	# Defer lookup so ModelHolder has time to load its model and create the AnimationPlayer
	_unit.action_changed.connect(_on_action_changed)
	call_deferred("_deferred_init")


func _deferred_init():
	_anim_player = _find_animation_player()
	if _anim_player == null:
		push_warning("UnitAnimator: No AnimationPlayer found in sibling ModelHolder.")
		return
	_play(idle_animation)


func _on_action_changed(new_action):
	match true:
		_ when new_action is AttackMoving:
			_play(attack_move_animation)
		_ when (
			new_action is Moving
			or new_action is MovingToUnit
			or new_action is Patrolling
			or new_action is FollowingToReachDistance
			or new_action is Following
		):
			_play(move_animation)
		_:
			_play(idle_animation)


func _play(anim_name: String) -> void:
	if _anim_player == null:
		return
	if not _anim_player.has_animation(anim_name):
		return
	if _anim_player.current_animation == anim_name:
		return
	_anim_player.play(anim_name)


func _find_animation_player() -> AnimationPlayer:
	for sibling in _unit.get_children():
		if sibling is ModelHolder:
			var player = sibling.find_child("AnimationPlayer", true, false)
			if player != null:
				return player
	return null
