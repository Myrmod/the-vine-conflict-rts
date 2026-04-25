extends CreepSource

## Small Radix creep source that a Seedling becomes after the `spread` ability.
## Visually: the Seedling model frozen at the end of its `grow` animation.

const GROW_ANIM_NAME := "grow"
const MAX_PLAYER_COLOR_RETRIES := 60

@export_range(0.0, 20.0, 0.1)
var player_color_emission_energy: float = RadixPlayerColor.DEFAULT_EMISSION_ENERGY

var _player_color_retry_count: int = 0
var _player_color_materials: Array[StandardMaterial3D] = []
var _grow_pose_applied: bool = false
var _using_adopted_visuals: bool = false


func _ready() -> void:
	super()
	if not _using_adopted_visuals:
		call_deferred("_apply_grow_end_pose")
	call_deferred("_apply_player_color_glow")


## Reuses the Seedling's already-loaded Geometry node so the Sapling appears as a
## perfect in-place transformation with no model-load flicker.
func adopt_seedling_visuals(seedling: Node) -> void:
	if seedling == null or not is_instance_valid(seedling):
		return
	var seedling_geometry: Node = seedling.find_child("Geometry", false, false)
	if seedling_geometry == null:
		return
	var existing_geometry: Node = find_child("Geometry", false, false)
	if existing_geometry != null:
		remove_child(existing_geometry)
		existing_geometry.queue_free()
	seedling.remove_child(seedling_geometry)
	add_child(seedling_geometry)
	seedling_geometry.name = "Geometry"
	_using_adopted_visuals = true
	_grow_pose_applied = true


func _apply_grow_end_pose() -> void:
	if _grow_pose_applied:
		return
	var anim_player: AnimationPlayer = _find_animation_player()
	if anim_player == null:
		# Model not loaded yet; retry next frame.
		call_deferred("_apply_grow_end_pose")
		return
	var resolved: String = _resolve_animation_name(anim_player, GROW_ANIM_NAME)
	if resolved.is_empty():
		_grow_pose_applied = true
		return
	var anim_resource: Animation = anim_player.get_animation(resolved)
	if anim_resource != null:
		anim_resource.loop_mode = Animation.LOOP_NONE
	anim_player.play(resolved)
	anim_player.seek(anim_resource.length if anim_resource != null else 99.0, true)
	anim_player.pause()
	_grow_pose_applied = true


func _find_animation_player() -> AnimationPlayer:
	var holders: Array = find_children("*", "ModelHolder", true, false)
	for holder: Node in holders:
		var ap: Node = holder.find_child("AnimationPlayer", true, false)
		if ap != null:
			return ap
	return null


func _resolve_animation_name(anim_player: AnimationPlayer, requested: String) -> String:
	if anim_player.has_animation(requested):
		return requested
	var lower := requested.to_lower()
	for name in anim_player.get_animation_list():
		if name.to_lower() == lower or name.to_lower().contains(lower):
			return name
	return ""


func _apply_player_color_glow() -> void:
	if player == null:
		if _player_color_retry_count < MAX_PLAYER_COLOR_RETRIES:
			_player_color_retry_count += 1
			call_deferred("_apply_player_color_glow")
		return
	_player_color_retry_count = 0
	if not player.changed.is_connected(_on_player_changed):
		player.changed.connect(_on_player_changed)
	var geometry: Node = find_child("Geometry")
	if geometry == null:
		return
	_player_color_materials = RadixPlayerColor.apply(
		geometry, player.color, player_color_emission_energy
	)


func _on_player_changed() -> void:
	if player == null:
		return
	RadixPlayerColor.refresh_materials(
		_player_color_materials, player.color, player_color_emission_energy
	)
