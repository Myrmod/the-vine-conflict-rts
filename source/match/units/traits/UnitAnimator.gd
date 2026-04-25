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
const Constructing = preload("res://source/match/units/actions/Constructing.gd")
const ConstructingWhileInRange = preload(
	"res://source/match/units/actions/ConstructingWhileInRange.gd"
)
const Spreading = preload("res://source/match/units/actions/Spreading.gd")

@export var idle_animation: String = "RESET"
@export var move_animation: String = "Run 50_"
@export var attack_move_animation: String = "Run 100_"
@export var attack_animation: String = "Idle 100_"
## Optional one-shot animations triggered explicitly via play_special().
@export var build_animation: String = ""
@export var grow_animation: String = ""

var _anim_player: AnimationPlayer = null
var _special_anim_active: bool = false

@onready var _unit = get_parent()


func _ready():
	# Defer lookup so ModelHolder has time to load its model and create the AnimationPlayer
	_unit.action_changed.connect(_on_action_changed)
	_unit.action_updated.connect(_on_action_runtime_updated)
	call_deferred("_deferred_init")


func _deferred_init():
	_anim_player = _find_animation_player()
	if _anim_player == null:
		push_warning("UnitAnimator: No AnimationPlayer found in sibling ModelHolder.")
		return
	# Respect the current action immediately (important for actions assigned
	# before the animator finishes deferred initialization).
	_on_action_changed(_unit.action)


func _on_action_changed(new_action):
	if _special_anim_active:
		return
	match true:
		_ when new_action is AttackMoving:
			_play(attack_move_animation)
		_ when _is_movement_action(new_action):
			_play(move_animation)
		_:
			_play(idle_animation)


func _on_action_runtime_updated() -> void:
	if _special_anim_active:
		return
	if _unit != null:
		_on_action_changed(_unit.action)


func _is_movement_action(action_node: Node) -> bool:
	if action_node == null:
		return false
	if (
		action_node is Moving
		or action_node is MovingToUnit
		or action_node is Patrolling
		or action_node is FollowingToReachDistance
		or action_node is Following
		or action_node is Spreading
	):
		return true
	if action_node is Constructing:
		for child: Node in action_node.get_children():
			if child is MovingToUnit:
				return true
			if child is ConstructingWhileInRange:
				return false
	return false


## Play a one-shot animation by key (e.g. "build" or "grow"). While active,
## action-driven animation switches are suppressed. Call stop_special() to
## restore action-driven behaviour.
func play_special(anim_key: String) -> void:
	if _anim_player == null:
		_anim_player = _find_animation_player()
	if _anim_player == null:
		return
	var requested := _anim_key_to_export(anim_key)
	if requested.is_empty():
		requested = anim_key
	var resolved := _resolve_animation_name(requested)
	if resolved.is_empty():
		return
	var anim_resource := _anim_player.get_animation(resolved)
	if anim_resource != null:
		anim_resource.loop_mode = Animation.LOOP_NONE
	_special_anim_active = true
	_anim_player.play(resolved)


## Stop any active special animation and return to the action-driven default.
func stop_special() -> void:
	if not _special_anim_active:
		return
	_special_anim_active = false
	if _unit != null:
		_on_action_changed(_unit.action)


func _anim_key_to_export(anim_key: String) -> String:
	match anim_key:
		"build":
			return build_animation
		"grow":
			return grow_animation
		_:
			return ""


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
