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
	var resolved := _resolve_animation_name(anim_name)
	if resolved.is_empty() and (anim_name == move_animation or anim_name == attack_move_animation):
		resolved = _fallback_movement_animation()
	if resolved.is_empty():
		if anim_name == idle_animation:
			_reset_to_bind_pose()
		return
	if anim_name == move_animation or anim_name == attack_move_animation:
		var anim_resource := _anim_player.get_animation(resolved)
		if anim_resource != null:
			anim_resource.loop_mode = Animation.LOOP_LINEAR
	if _anim_player.current_animation == resolved and _anim_player.is_playing():
		return
	_anim_player.play(resolved)


func _reset_to_bind_pose() -> void:
	if _anim_player != null:
		_anim_player.stop()
		_anim_player.seek(0.0, true)
	for skeleton in _unit.find_children("*", "Skeleton3D", true, false):
		skeleton.reset_bone_poses()


func _resolve_animation_name(requested: String) -> String:
	if requested.is_empty() or _anim_player == null:
		return ""
	if _anim_player.has_animation(requested):
		return requested

	var requested_lower := requested.to_lower()
	var all: PackedStringArray = _anim_player.get_animation_list()

	for name in all:
		if name.to_lower() == requested_lower:
			return name

	for name in all:
		if name.to_lower().contains(requested_lower):
			return name

	if requested_lower == "move":
		for token in ["run", "walk", "move", "locomotion"]:
			for name in all:
				if name.to_lower().contains(token):
					return name

	return ""


func _fallback_movement_animation() -> String:
	if _anim_player == null:
		return ""
	var idle_resolved := _resolve_animation_name(idle_animation)
	for name in _anim_player.get_animation_list():
		if name == idle_resolved or name.to_lower() == "reset":
			continue
		return name
	return ""


func _find_animation_player() -> AnimationPlayer:
	for sibling in _unit.get_children():
		if sibling is ModelHolder:
			var player = sibling.find_child("AnimationPlayer", true, false)
			if player != null:
				return player

	# Some unit scenes nest ModelHolder under container nodes (e.g. Geometry).
	var nested_holders = _unit.find_children("*", "ModelHolder", true, false)
	for holder in nested_holders:
		var nested_player = holder.find_child("AnimationPlayer", true, false)
		if nested_player != null:
			return nested_player
	return null
