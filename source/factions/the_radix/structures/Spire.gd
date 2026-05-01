extends RadixSeedlingStartedStructure

const BRANCH_OPEN_DURATION := 0.5
const BRANCH_HOLD_OPEN_DURATION := 0.1
const BRANCH_CLOSE_DURATION := 0.3

## Animation pairs per branch (0-indexed): [move_anim_name, spawner_open_anim_name].
## Both animations in each pair play simultaneously via an additive blend tree.
const BRANCH_ANIM_PAIRS: Array[Array] = [
	["MoveBranch1", "Spawner1Open"],
	["MoveBranch2", "Spawner2Open"],
	["MoveBranch3", "Spawner3Open"],
]

const MAX_PLAYER_COLOR_RETRIES := 60

@export_range(0.0, 20.0, 0.1) var petals_inner_emission_energy: float = 4.0
## How much the petal colour is mixed toward white (0 = full player colour, 1 = white).
@export_range(0.0, 1.0, 0.01) var petals_tint_mix: float = 0.5

var _spawner_markers: Array[Node3D] = []
var _next_branch_idx: int = 0
var _reserved_branch_by_unit_id: Dictionary = {}
var _branch_tweens_by_idx: Dictionary = {}
var _anim_tree: AnimationTree = null
var _anim_length: float = 1.0
var _petals_materials: Array[StandardMaterial3D] = []
var _petals_inner_materials: Array[StandardMaterial3D] = []
var _player_color_retry_count: int = 0
var _prod_time: float = 0.0
var _prod_length: float = 0.0
var _prod_playing: bool = false
var _prod_stopping: bool = false


func _ready() -> void:
	super()
	_cache_spawner_markers()
	call_deferred("_setup_animation_tree")
	call_deferred("_connect_production_queue")


func _setup_color() -> void:
	_apply_spire_player_color()


func _apply_spire_player_color() -> void:
	if player == null:
		if _player_color_retry_count < MAX_PLAYER_COLOR_RETRIES:
			_player_color_retry_count += 1
			call_deferred("_apply_spire_player_color")
		return
	_player_color_retry_count = 0
	if not player.changed.is_connected(_on_player_changed):
		player.changed.connect(_on_player_changed)
	var geometry: Node = find_child("Geometry")
	if geometry == null:
		push_warning("Spire: no 'Geometry' child found for player color")
		return
	_petals_materials = _apply_color_to_named_surface(
		geometry, "petals", _petals_color(), 0.0, false, false
	)
	_petals_inner_materials = _apply_color_to_named_surface(
		geometry, "petals inner", player.color, petals_inner_emission_energy, false
	)


func _on_player_changed() -> void:
	if player == null:
		return
	for mat: StandardMaterial3D in _petals_materials:
		if mat == null:
			continue
		mat.albedo_color = _petals_color()
	RadixPlayerColor.refresh_materials(
		_petals_inner_materials, player.color, petals_inner_emission_energy
	)


func _petals_color() -> Color:
	return player.color.lerp(Color.WHITE, petals_tint_mix)


func _apply_color_to_named_surface(
	root: Node,
	surface_name_lower: String,
	color: Color,
	emission_energy: float,
	unshaded: bool = true,
	emit: bool = true
) -> Array[StandardMaterial3D]:
	var results: Array[StandardMaterial3D] = []
	for mesh: MeshInstance3D in _collect_mesh_instances(root):
		if mesh.mesh == null:
			continue
		for i: int in range(mesh.mesh.get_surface_count()):
			if mesh.mesh.surface_get_name(i).to_lower() == surface_name_lower:
				var mat := StandardMaterial3D.new()
				if unshaded:
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color = color
				if emit:
					mat.emission_enabled = true
					mat.emission = color
					mat.emission_energy_multiplier = emission_energy
				mesh.set_surface_override_material(i, mat)
				results.append(mat)
	return results


func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var results: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		results.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		results.append_array(_collect_mesh_instances(child))
	return results


func get_parallel_production_count() -> int:
	return max(1, _spawner_markers.size())


func get_custom_spawn_transform_for_unit(produced_unit: Node):
	var branch_idx: int = _pick_branch()
	if branch_idx < 0:
		return null
	_reserved_branch_by_unit_id[produced_unit.get_instance_id()] = branch_idx
	return Transform3D(Basis(), _spawner_markers[branch_idx].global_position)


func handle_produced_unit_spawn(produced_unit: Node) -> bool:
	var unit_id: int = produced_unit.get_instance_id()
	var branch_idx: int = _reserved_branch_by_unit_id.get(unit_id, -1)
	if _reserved_branch_by_unit_id.has(unit_id):
		_reserved_branch_by_unit_id.erase(unit_id)
	if branch_idx < 0:
		branch_idx = _pick_branch()
	if branch_idx < 0:
		return false
	_play_branch_spawn_sequence(produced_unit, branch_idx)
	return true


func _cache_spawner_markers() -> void:
	_spawner_markers.clear()
	for i: int in range(1, 4):
		var marker: Node3D = get_node_or_null("Spawner%d" % i)
		if marker != null:
			_spawner_markers.append(marker)


func _pick_branch() -> int:
	if _spawner_markers.is_empty():
		return -1
	if _next_branch_idx >= _spawner_markers.size():
		_next_branch_idx = 0
	var idx: int = _next_branch_idx
	_next_branch_idx = (_next_branch_idx + 1) % _spawner_markers.size()
	return idx


func _find_glb_root() -> Node:
	var model_holder: Node = get_node_or_null("Geometry/Model")
	if model_holder == null:
		return null
	if model_holder.get_child_count() > 0:
		return model_holder.get_child(0)
	return null


func _setup_animation_tree() -> void:
	if _anim_tree != null:
		return
	var glb_root: Node = _find_glb_root()
	if glb_root == null:
		push_warning("Spire: _find_glb_root() returned null — no child under Geometry/Model")
		return
	var anim_player: AnimationPlayer = glb_root.get_node_or_null("AnimationPlayer")
	if anim_player == null:
		push_warning("Spire: no AnimationPlayer found under glb_root '%s'" % glb_root.name)
		return

	# Log all available animations to help diagnose name mismatches.
	var available: Array[String] = []
	for lib_name: StringName in anim_player.get_animation_library_list():
		var lib: AnimationLibrary = anim_player.get_animation_library(lib_name)
		for anim_name: StringName in lib.get_animation_list():
			available.append(
				"%s/%s" % [lib_name, anim_name] if not lib_name.is_empty() else str(anim_name)
			)
	push_warning("Spire: available animations: %s" % str(available))

	# Determine the longest animation to use as the normalised length
	_anim_length = 1.0
	for pair: Array in BRANCH_ANIM_PAIRS:
		for anim_short: String in pair:
			var full: StringName = _find_full_anim_name(anim_player, anim_short)
			if anim_player.has_animation(full):
				var anim: Animation = anim_player.get_animation(full)
				_anim_length = maxf(_anim_length, anim.length)
			else:
				push_warning(
					"Spire: animation '%s' not found (resolved to '%s')" % [anim_short, full]
				)

	# Build a blend tree: one TimeSeek per animation, all combined additively.
	# Order: [MoveBranch1, Spawner1Open, MoveBranch2, Spawner2Open, MoveBranch3, Spawner3Open]
	# Seek indices: branch 0 → seek_0 + seek_1
	#               branch 1 → seek_2 + seek_3
	#               branch 2 → seek_4 + seek_5
	var blend_tree := AnimationNodeBlendTree.new()
	var all_anims: Array[String] = []
	for pair: Array in BRANCH_ANIM_PAIRS:
		for anim_short: String in pair:
			all_anims.append(anim_short)

	var prev_output: String = ""
	for i: int in range(all_anims.size()):
		var anim_full: StringName = _find_full_anim_name(anim_player, all_anims[i])

		var anim_node := AnimationNodeAnimation.new()
		anim_node.animation = anim_full
		blend_tree.add_node("anim_%d" % i, anim_node)

		var seek_node := AnimationNodeTimeSeek.new()
		blend_tree.add_node("seek_%d" % i, seek_node)
		blend_tree.connect_node("seek_%d" % i, 0, "anim_%d" % i)

		if i == 0:
			prev_output = "seek_0"
		else:
			var add_name := "add_%d" % i
			var add_node := AnimationNodeAdd2.new()
			blend_tree.add_node(add_name, add_node)
			blend_tree.connect_node(add_name, 0, prev_output)
			blend_tree.connect_node(add_name, 1, "seek_%d" % i)
			prev_output = add_name

	# Add Production as a seek-driven additive layer. add_amount stays 0.0 until
	# production is active; _process manually scrubs _prod_time each frame.
	var prod_full: StringName = _find_full_anim_name(anim_player, "Production")
	if anim_player.has_animation(prod_full):
		_prod_length = anim_player.get_animation(prod_full).length
		var prod_anim_node := AnimationNodeAnimation.new()
		prod_anim_node.animation = prod_full
		blend_tree.add_node("anim_prod", prod_anim_node)
		var prod_seek := AnimationNodeTimeSeek.new()
		blend_tree.add_node("seek_prod", prod_seek)
		blend_tree.connect_node("seek_prod", 0, "anim_prod")
		var prod_add := AnimationNodeAdd2.new()
		blend_tree.add_node("add_prod", prod_add)
		blend_tree.connect_node("add_prod", 0, prev_output)
		blend_tree.connect_node("add_prod", 1, "seek_prod")
		prev_output = "add_prod"
	else:
		push_warning("Spire: 'Production' animation not found in GLB")

	blend_tree.connect_node("output", 0, prev_output)

	_anim_tree = AnimationTree.new()
	_anim_tree.name = "SpireAnimTree"
	_anim_tree.tree_root = blend_tree
	_anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	glb_root.add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(anim_player)

	# Add2 blend amount defaults to 0.0 — set all to 1.0 so every additive layer is fully applied.
	for i: int in range(1, all_anims.size()):
		_anim_tree.set("parameters/add_%d/add_amount" % i, 1.0)

	_anim_tree.active = true


func _connect_production_queue() -> void:
	if production_queue == null:
		return
	if not production_queue.element_enqueued.is_connected(_on_production_queue_changed):
		production_queue.element_enqueued.connect(_on_production_queue_changed)
	if not production_queue.element_removed.is_connected(_on_production_queue_changed):
		production_queue.element_removed.connect(_on_production_queue_changed)


func _on_production_queue_changed(_element = null) -> void:
	_update_production_animation()


func _process(delta: float) -> void:
	if _anim_tree == null or _prod_length <= 0.0:
		return
	if not _prod_playing and not _prod_stopping:
		return
	_prod_time += delta
	if _prod_time >= _prod_length:
		if _prod_stopping:
			_prod_time = 0.0
			_prod_stopping = false
			_anim_tree.set("parameters/add_prod/add_amount", 0.0)
			return
		_prod_time = fmod(_prod_time, _prod_length)
	_anim_tree.set("parameters/seek_prod/seek_request", _prod_time)
	_anim_tree.advance(0.0)


func _has_active_production() -> bool:
	if production_queue == null:
		return false
	for el in production_queue.get_elements():
		if not el.paused and not el.completed and not el.is_tracking_only:
			return true
	return false


func _update_production_animation() -> void:
	if _prod_length <= 0.0:
		return
	if _has_active_production():
		_prod_stopping = false
		if not _prod_playing:
			_prod_playing = true
			_anim_tree.set("parameters/add_prod/add_amount", 1.0)
	elif _prod_playing:
		_prod_playing = false
		_prod_stopping = true


func _find_full_anim_name(anim_player: AnimationPlayer, short_name: String) -> StringName:
	for lib_name: StringName in anim_player.get_animation_library_list():
		var lib: AnimationLibrary = anim_player.get_animation_library(lib_name)
		if lib.has_animation(short_name):
			if lib_name.is_empty():
				return StringName(short_name)
			return StringName("%s/%s" % [lib_name, short_name])
	return StringName(short_name)


## Sets both animations for the given branch to the frame corresponding to
## progress (0.0 = start, 1.0 = end) and flushes the tree.
func _set_branch_progress(branch_idx: int, progress: float) -> void:
	if _anim_tree == null:
		_setup_animation_tree()
	if _anim_tree == null or _anim_length <= 0.0:
		return
	var seek_time: float = progress * _anim_length
	var base: int = branch_idx * 2
	for offset: int in range(2):
		_anim_tree.set("parameters/seek_%d/seek_request" % (base + offset), seek_time)
	_anim_tree.advance(0.0)


func _play_branch_spawn_sequence(produced_unit: Node, branch_idx: int) -> void:
	if branch_idx < 0 or branch_idx >= _spawner_markers.size():
		return

	# Kill any in-progress tween for this branch so overlapping spawns don't fight
	if _branch_tweens_by_idx.has(branch_idx):
		var prev: Tween = _branch_tweens_by_idx[branch_idx]
		if is_instance_valid(prev):
			prev.kill()

	_set_branch_progress(branch_idx, 0.0)
	var tween := create_tween()
	_branch_tweens_by_idx[branch_idx] = tween

	tween.tween_method(
		func(p: float) -> void: _set_branch_progress(branch_idx, p), 0.0, 1.0, BRANCH_OPEN_DURATION
	)
	tween.tween_interval(BRANCH_HOLD_OPEN_DURATION)
	tween.tween_callback(
		func() -> void:
			if is_instance_valid(produced_unit):
				var rally_point: Node = find_child("RallyPoint")
				if rally_point != null:
					MatchSignals.navigate_unit_to_rally_point.emit(produced_unit, rally_point)
	)
	tween.tween_method(
		func(p: float) -> void: _set_branch_progress(branch_idx, p), 1.0, 0.0, BRANCH_CLOSE_DURATION
	)

	await tween.finished
	if _branch_tweens_by_idx.get(branch_idx) == tween:
		_branch_tweens_by_idx.erase(branch_idx)
