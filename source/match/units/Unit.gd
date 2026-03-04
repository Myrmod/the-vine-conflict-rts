class_name Unit

extends Area3D

signal selected
signal deselected
signal hp_changed
signal action_changed(new_action)
signal action_updated

const MATERIAL_ALBEDO_TO_REPLACE = Color(0.99, 0.81, 0.48)
const MATERIAL_ALBEDO_TO_REPLACE_EPSILON = 0.05

var hp = null:
	set = _set_hp
var hp_max = null:
	set = _set_hp_max
var attack_damage = null
var attack_interval = null
var attack_range = null
var attack_domains = []
var movement_domains: Array[Enums.MovementTypes] = []
var _player_ref

var radius:
	get = _get_radius
var movement_speed:
	get = _get_movement_speed
var sight_range = null
## Player or AI
var player:
	get:
		return _player_ref
var color:
	get:
		return player.color
var action = null:
	set = _set_action
var global_position_yless:
	get:
		return global_position * Vector3(1, 0, 1)
var type:
	get = _get_type

var id: int

var _action_locked = false

@onready var _match = find_parent("Match")


func _ready():
	if not _match:
		return
	if not _match.is_node_ready():
		await _match.ready
	_player_ref = get_parent()
	_setup_color()
	_setup_default_properties_from_constants()
	assert(_safety_checks())
	id = EntityRegistry.register(self)


func is_revealing():
	return is_in_group("revealed_units") and visible


func _set_hp(value):
	var old_hp = hp
	hp = max(0, value)
	if hp != old_hp:
		hp_changed.emit()
	if hp == 0:
		_handle_unit_death()


func _set_hp_max(value):
	hp_max = value
	hp_changed.emit()


func _get_radius():
	if find_child("Movement") != null:
		return find_child("Movement").radius
	if find_child("MovementObstacle") != null:
		return find_child("MovementObstacle").radius
	return null


func get_nav_domain():
	"""Derive the NavigationConstants.Domain from movement_domains,
	with fallback to Movement/MovementObstacle child node domain."""
	if not movement_domains.is_empty():
		if Enums.MovementTypes.AIR in movement_domains:
			return NavigationConstants.Domain.AIR
		return NavigationConstants.Domain.TERRAIN
	# Fallback for units that don't explicitly set movement_domains
	if find_child("Movement") != null:
		return find_child("Movement").domain
	if find_child("MovementObstacle") != null:
		return find_child("MovementObstacle").domain
	return NavigationConstants.Domain.TERRAIN


func get_effective_movement_types() -> Array:
	"""Return the effective movement types for this unit.
	Used for attack-domain targeting (can an attacker with LAND attack this unit?).
	Falls back to deriving from Movement/MovementObstacle domain when
	movement_domains is not explicitly set."""
	if not movement_domains.is_empty():
		return movement_domains
	var domain = get_nav_domain()
	if domain == NavigationConstants.Domain.AIR:
		return [Enums.MovementTypes.AIR]
	return [Enums.MovementTypes.LAND]


func _get_movement_speed():
	if find_child("Movement") != null:
		return find_child("Movement").speed
	return 0.0


func _is_movable():
	return _get_movement_speed() > 0.0


func _setup_color():
	var material = player.get_color_material()
	MatchUtils.traverse_node_tree_and_replace_materials_matching_albedo(
		find_child("Geometry"),
		MATERIAL_ALBEDO_TO_REPLACE,
		MATERIAL_ALBEDO_TO_REPLACE_EPSILON,
		material
	)


func _set_action(action_node):
	if not is_inside_tree() or _action_locked:
		if action_node != null:
			action_node.queue_free()
		return
	_action_locked = true
	_teardown_current_action()
	action = action_node
	if action != null:
		var action_copy = action  # bind() performs copy itself, but lets force copy just in case
		action.tree_exited.connect(_on_action_node_tree_exited.bind(action_copy))
		add_child(action_node)
	_action_locked = false
	action_changed.emit(action)


func _get_type():
	var unit_script_path = get_script().resource_path
	var unit_file_name = unit_script_path.substr(unit_script_path.rfind("/") + 1)
	var unit_name = unit_file_name.split(".")[0]
	return unit_name


func _teardown_current_action():
	if action != null and action.is_inside_tree():
		action.queue_free()
		remove_child(action)  # triggers _on_action_node_tree_exited immediately


func _safety_checks():
	var nav_domain = get_nav_domain()
	if nav_domain == NavigationConstants.Domain.AIR:
		assert(
			radius < Air.MAX_AGENT_RADIUS or is_equal_approx(radius, Air.MAX_AGENT_RADIUS),
			"Unit radius exceeds the established limit"
		)
	elif nav_domain == NavigationConstants.Domain.TERRAIN:
		assert(
			(
				not _is_movable()
				or (
					radius < Terrain.MAX_AGENT_RADIUS
					or is_equal_approx(radius, Terrain.MAX_AGENT_RADIUS)
				)
			),
			"Unit radius exceeds the established limit"
		)
	return true


func _handle_unit_death():
	# Unregister from EntityRegistry so get_unit() returns null for dead units
	# and the entities dict doesn't grow unbounded during a match.
	EntityRegistry.unregister(self)
	tree_exited.connect(func(): MatchSignals.unit_died.emit(self))
	queue_free()


func _setup_default_properties_from_constants():
	var default_properties = UnitConstants.DEFAULT_PROPERTIES[get_script().resource_path.replace(
		".gd", ".tscn"
	)]
	for property in default_properties:
		set(property, default_properties[property])


func _on_action_node_tree_exited(action_node):
	assert(action_node == action, "unexpected action released")
	action = null
