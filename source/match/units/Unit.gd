class_name Unit

extends Area3D

signal selected
signal deselected
signal hp_changed
signal action_changed(new_action)
signal action_updated

const MATERIAL_ALBEDO_TO_REPLACE = Color(1.0, 0.8144, 0.4877)
const MATERIAL_ALBEDO_TO_REPLACE_EPSILON = 0.05

const UnitCommandQueue = preload("res://source/match/units/UnitCommandQueue.gd")

const PRODUCTION_TYPE_FALLBACK_MODELS := {
	Enums.ProductionTabType.INFANTRY: "models/FallbackInfantry/soldier_final_animations_fbx.glb",
}

var hp = null:
	set = _set_hp
var hp_max = null:
	set = _set_hp_max
var attack_damage = null
var attack_interval = null
var attack_range = null
var attack_type: String = ""
var attack_domains = []
var armor: Dictionary = {}
var projectile_type: int = -1
var projectile_config: Dictionary = {}
var projectile_origin: Vector3 = Vector3.ZERO
var can_reverse_move: bool = false
var movement_domains: Array[Enums.MovementTypes] = []
var _player_ref

var radius:
	get = _get_radius
var movement_speed:
	get = _get_movement_speed
var sight_range = null
var unit_name: String = ""
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

## When set (>= 0), the entity will be registered with this specific ID
## instead of getting a new sequential one. Used during save restoration.
var _saved_id: int = -1

var _action_locked = false
## When true, unit is "stopped" — no default idle action will be assigned.
## Set by the STOP command, cleared when any explicit command is given.
var _stopped: bool = false
## Script to instantiate as the default idle action (e.g., WaitingForTargets).
## Set by subclass _ready() or by UnitConstants default_idle_action_scene property.
var default_idle_action_scene: Script = null

@onready var _match = find_parent("Match")


func _ready():
	if not _match:
		return
	if not _match.is_node_ready():
		await _match.ready
	_player_ref = get_parent()
	_setup_color()
	_setup_default_properties_from_constants()
	_setup_model_fallback()
	assert(_safety_checks())
	if _saved_id >= 0:
		id = _saved_id
		EntityRegistry.entities[id] = self
		if EntityRegistry._next_id <= id:
			EntityRegistry._next_id = id + 1
	else:
		id = EntityRegistry.register(self)
	# Add command queue for shift-queued orders
	var queue = UnitCommandQueue.new()
	queue.name = "UnitCommandQueue"
	add_child(queue)


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


func _setup_model_fallback():
	var props = UnitConstants.DEFAULT_PROPERTIES.get(
		get_script().resource_path.replace(".gd", ".tscn"), {}
	)
	var tab_type = props.get("production_tab_type", -1)
	if not PRODUCTION_TYPE_FALLBACK_MODELS.has(tab_type):
		return
	var fallback_path: String = PRODUCTION_TYPE_FALLBACK_MODELS[tab_type]
	for child in get_children():
		if child is ModelHolder:
			var source: String = child.get_loaded_source()
			if source == "" or source == "fallback":
				child.load_model(fallback_path)


func _setup_default_properties_from_constants():
	var default_properties = UnitConstants.DEFAULT_PROPERTIES[get_script().resource_path.replace(
		".gd", ".tscn"
	)]
	## UnitConstants is the highest authority for all default properties.
	## If hp was pre-set to less than hp_max (e.g. in the map editor),
	## the unit/structure spawns damaged with that lower hp value.
	var pre_set_hp = hp
	# Apply non-hp properties via Object.set()
	for property in default_properties:
		if property == "hp" or property == "hp_max":
			continue
		set(property, default_properties[property])
	# Explicitly assign hp_max before hp through self. to guarantee
	# setters fire and the HealthBar can compute the correct ratio.
	if "hp_max" in default_properties:
		self.hp_max = default_properties["hp_max"]
	if "hp" in default_properties:
		self.hp = default_properties["hp"]
	if pre_set_hp != null and pre_set_hp < hp_max:
		self.hp = pre_set_hp


func _on_action_node_tree_exited(action_node):
	assert(action_node == action, "unexpected action released")
	action = null
	_assign_default_action()


## Assigns the default idle action if the unit has one and isn't stopped.
## Called when an action completes (queue_free) and the unit becomes idle.
func _assign_default_action():
	if _stopped:
		return
	# Check command queue first — execute next queued order if available
	var queue_node = get_node_or_null("UnitCommandQueue")
	if queue_node != null and queue_node.size() > 0:
		_execute_queued_command(queue_node.dequeue())
		return
	if default_idle_action_scene != null and action == null:
		action = default_idle_action_scene.new()


## Enqueue a command for later execution (shift-queue).
func _enqueue_command(cmd_type: int, data: Dictionary) -> void:
	var queue_node = get_node_or_null("UnitCommandQueue")
	if queue_node != null:
		queue_node.enqueue({"type": cmd_type, "data": data})


## Execute a queued command by instantiating the appropriate action.
func _execute_queued_command(cmd: Dictionary) -> void:
	if cmd.is_empty():
		return
	_stopped = false
	match cmd.type:
		Enums.CommandType.MOVE:
			action = Actions.Moving.new(cmd.data.pos)
		Enums.CommandType.ATTACK_MOVE:
			action = Actions.AttackMoving.new(cmd.data.pos)
		Enums.CommandType.HOLD_POSITION:
			action = Actions.HoldPosition.new()
		Enums.CommandType.MOVE_NO_ATTACK:
			_stopped = true
			action = Actions.Moving.new(cmd.data.pos)
		Enums.CommandType.PATROL:
			var origin = cmd.data.get("patrol_origin", global_position)
			action = Actions.Patrolling.new(origin, cmd.data.pos)
		Enums.CommandType.REVERSE_MOVE:
			action = Actions.ReverseMoving.new(cmd.data.pos)
		Enums.CommandType.STOP:
			_stopped = true
			var queue_node = get_node_or_null("UnitCommandQueue")
			if queue_node != null:
				queue_node.clear()
		_:
			push_warning("Unit: unknown queued command type %s" % cmd.type)
