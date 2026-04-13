@tool
extends Node3D

## Controls how far all leaf-opening animations play (0.0 = closed, 1.0 = fully open).
@export_range(0.0, 1.0, 0.01) var open_progress: float = 0.0:
	set(value):
		open_progress = value
		_apply_progress()

@export_group("Player Color")
## The player/faction color applied to UnitPlaceholder with glow.
@export var player_color: Color = Color.BLUE:
	set(value):
		player_color = value
		_apply_player_color()
@export_range(0.0, 20.0, 0.1) var emission_energy: float = 10.0:
	set(value):
		emission_energy = value
		_apply_player_color()

@export_group("Per-Animation Overrides", "override_")
## Set to >= 0 to override open_progress for this animation. Negative = use open_progress.
@export_range(-0.01, 1.0, 0.01) var override_m1open: float = -0.01:
	set(v):
		override_m1open = v
		_apply_progress()
@export_range(-0.01, 1.0, 0.01) var override_m2open: float = -0.01:
	set(v):
		override_m2open = v
		_apply_progress()
@export_range(-0.01, 1.0, 0.01) var override_m3open: float = -0.01:
	set(v):
		override_m3open = v
		_apply_progress()
@export_range(-0.01, 1.0, 0.01) var override_m4open: float = -0.01:
	set(v):
		override_m4open = v
		_apply_progress()
@export_range(-0.01, 1.0, 0.01) var override_l1open: float = -0.01:
	set(v):
		override_l1open = v
		_apply_progress()
@export_range(-0.01, 1.0, 0.01) var override_l2open: float = -0.01:
	set(v):
		override_l2open = v
		_apply_progress()
@export_range(-0.01, 1.0, 0.01) var override_l3open: float = -0.01:
	set(v):
		override_l3open = v
		_apply_progress()
@export_range(-0.01, 1.0, 0.01) var override_l4open: float = -0.01:
	set(v):
		override_l4open = v
		_apply_progress()

var _anim_tree: AnimationTree = null
var _animation_length: float = 0.0
var _anim_names: Array[String] = []
var _placeholder_material: StandardMaterial3D = null
var _player_color_materials: Array[StandardMaterial3D] = []

## Maps animation short name (e.g. "m1open") to its override property name.
var _override_map: Dictionary = {}


func _ready() -> void:
	# Defer to ensure instanced GLB children are fully available
	_deferred_init.call_deferred()


func _deferred_init() -> void:
	var glb_root: Node = get_node_or_null("SpawningFlowerBulb")
	if glb_root == null:
		push_warning(
			(
				"SpawningFlowerBulb: glb_root 'SpawningFlowerBulb' not found. Children: %s"
				% str(_get_child_names())
			)
		)
		return
	push_warning("SpawningFlowerBulb: glb_root found with %d children" % glb_root.get_child_count())
	_setup_animation_tree()
	_apply_progress()
	_apply_player_color()


func _get_child_names() -> Array[String]:
	var names: Array[String] = []
	for child: Node in get_children():
		names.append(child.name)
	return names


func _get_override_for(anim_short_name: String) -> float:
	var prop: String = "override_" + anim_short_name
	if prop in _override_map:
		var val: float = get(prop)
		if val >= 0.0:
			return val
	return open_progress


func _setup_animation_tree() -> void:
	if _anim_tree != null:
		return

	var glb_root: Node = get_node_or_null("SpawningFlowerBulb")
	if glb_root == null:
		return
	var anim_player: AnimationPlayer = glb_root.get_node_or_null("AnimationPlayer")
	if anim_player == null:
		return

	# Collect animation names and max length
	_anim_names.clear()
	for lib_name: StringName in anim_player.get_animation_library_list():
		var lib: AnimationLibrary = anim_player.get_animation_library(lib_name)
		for anim_name: StringName in lib.get_animation_list():
			var full: String = anim_name if lib_name.is_empty() else "%s/%s" % [lib_name, anim_name]
			_anim_names.append(full)
			var anim: Animation = lib.get_animation(anim_name)
			_animation_length = maxf(_animation_length, anim.length)

	if _anim_names.is_empty():
		return

	# Build override map from animation names
	for anim_full: String in _anim_names:
		# Strip library prefix if present
		var short: String = anim_full
		var slash: int = short.find("/")
		if slash >= 0:
			short = short.substr(slash + 1)
		var prop: String = "override_" + short
		_override_map[prop] = short

	# Build blend tree: each animation gets its own TimeSeek, chained with Add2
	var blend_tree: AnimationNodeBlendTree = AnimationNodeBlendTree.new()

	var prev_output: String = ""
	for i: int in range(_anim_names.size()):
		var anim_node_name: String = "anim_%d" % i
		var seek_node_name: String = "seek_%d" % i

		var anim_node: AnimationNodeAnimation = AnimationNodeAnimation.new()
		anim_node.animation = _anim_names[i]
		blend_tree.add_node(anim_node_name, anim_node)

		var seek_node: AnimationNodeTimeSeek = AnimationNodeTimeSeek.new()
		blend_tree.add_node(seek_node_name, seek_node)
		blend_tree.connect_node(seek_node_name, 0, anim_node_name)

		if i == 0:
			prev_output = seek_node_name
		else:
			var add_name: String = "add_%d" % i
			var add_node: AnimationNodeAdd2 = AnimationNodeAdd2.new()
			blend_tree.add_node(add_name, add_node)
			blend_tree.connect_node(add_name, 0, prev_output)
			blend_tree.connect_node(add_name, 1, seek_node_name)
			prev_output = add_name

	blend_tree.connect_node("output", 0, prev_output)

	# Create AnimationTree as sibling of AnimationPlayer
	_anim_tree = AnimationTree.new()
	_anim_tree.name = "OpenAnimTree"
	_anim_tree.tree_root = blend_tree
	_anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	glb_root.add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(anim_player)

	# Set all Add2 blend amounts to 1.0 (fully add each animation)
	for i: int in range(1, _anim_names.size()):
		_anim_tree.set("parameters/add_%d/add_amount" % i, 1.0)

	_anim_tree.active = true


func _apply_progress() -> void:
	if _anim_tree == null:
		_setup_animation_tree()
	if _anim_tree == null or _animation_length <= 0.0:
		return

	for i: int in range(_anim_names.size()):
		var anim_full: String = _anim_names[i]
		var short: String = anim_full
		var slash: int = short.find("/")
		if slash >= 0:
			short = short.substr(slash + 1)
		var progress: float = _get_override_for(short)
		var seek_time: float = progress * _animation_length
		_anim_tree.set("parameters/seek_%d/seek_request" % i, seek_time)

	_anim_tree.advance(0.0)


func _apply_player_color() -> void:
	var glb_root: Node = get_node_or_null("SpawningFlowerBulb")
	if glb_root == null:
		return

	# Apply placeholder material
	var placeholder: MeshInstance3D = glb_root.get_node_or_null("UnitPlaceholder")
	if placeholder != null:
		if _placeholder_material == null:
			_placeholder_material = StandardMaterial3D.new()
			placeholder.material_override = _placeholder_material

		_placeholder_material.albedo_color = player_color
		_placeholder_material.emission_enabled = true
		_placeholder_material.emission = player_color
		_placeholder_material.emission_energy_multiplier = emission_energy

	# Apply player color to "PlayerColor" material surfaces on leaf meshes
	_apply_leaf_player_color(glb_root)


func _apply_leaf_player_color(glb_root: Node) -> void:
	# Find PlayerColor surfaces on first call
	if _player_color_materials.is_empty():
		var leaves: Array[MeshInstance3D] = []
		_find_leaf_meshes(glb_root, leaves)
		for leaf: MeshInstance3D in leaves:
			var surface_count: int = leaf.mesh.get_surface_count() if leaf.mesh != null else 0
			for surface_idx: int in range(surface_count):
				var mat: Material = leaf.get_active_material(surface_idx)
				if mat is StandardMaterial3D and mat.resource_name == "PlayerColor":
					var new_mat: StandardMaterial3D = mat.duplicate()
					leaf.set_surface_override_material(surface_idx, new_mat)
					_player_color_materials.append(new_mat)

	# Update all PlayerColor materials with current values
	for mat: StandardMaterial3D in _player_color_materials:
		mat.albedo_color = player_color
		mat.emission_enabled = true
		mat.emission = player_color
		mat.emission_energy_multiplier = emission_energy


func _find_leaf_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.name.begins_with("Leaf_"):
		result.append(node)
	for child: Node in node.get_children():
		_find_leaf_meshes(child, result)
