extends Node

class Set:
	extends "res://source/utils/Set.gd"

	static func from_array(array):
		var a_set = Set.new()
		for item in array:
			a_set.add(item)
		return a_set

	static func subtracted(minuend, subtrahend):
		var difference = Set.new()
		for item in minuend.iterate():
			if not subtrahend.has(item):
				difference.add(item)
		return difference


class Dict:
	static func items(dict):
		var pairs = []
		for key in dict:
			pairs.append([key, dict[key]])
		return pairs


class Float:
	static func is_equal_approx_with_epsilon(a: float, b: float, epsilon):
		return abs(a - b) <= epsilon


class Colour:
	static func is_equal_approx_with_epsilon(a: Color, b: Color, epsilon: float):
		return (
			Float.is_equal_approx_with_epsilon(a.r, b.r, epsilon)
			and Float.is_equal_approx_with_epsilon(a.g, b.g, epsilon)
			and Float.is_equal_approx_with_epsilon(a.b, b.b, epsilon)
		)


class NodeEx:
	static func find_parent_with_group(node, group_for_parent_to_be_in):
		var ancestor = node.get_parent()
		while ancestor != null:
			if ancestor.is_in_group(group_for_parent_to_be_in):
				return ancestor
			ancestor = ancestor.get_parent()
		return null


static func sum(array):
	var total = 0
	for item in array:
		total += item
	return total


class RouletteWheel:
	var _values_w_sorted_normalized_shares = []

	func _init(value_to_share_mapping):
		var total_share = Utils.sum(value_to_share_mapping.values())
		for value in value_to_share_mapping:
			var share = value_to_share_mapping[value]
			var normalized_share = share / total_share
			_values_w_sorted_normalized_shares.append([value, normalized_share])
		for i in range(1, _values_w_sorted_normalized_shares.size()):
			_values_w_sorted_normalized_shares[i][1] += _values_w_sorted_normalized_shares[i - 1][1]

	func get_value(probability):
		for tuple in _values_w_sorted_normalized_shares:
			var value = tuple[0]
			var accumulated_share = tuple[1]
			if probability <= accumulated_share:
				return value
		assert(false, "unexpected flow")
		return -1

func _detect_potential_recursion(value, visited: Dictionary, path: String, command_context: Dictionary = {}) -> bool:
	# Only track actual objects (Nodes, Resources) for circular reference detection
	# Arrays and dictionaries are data structures, not circular references
	if typeof(value) == TYPE_OBJECT:
		var id = value.get_instance_id()
		if visited.has(id):
			var context_str = _format_command_context(command_context)
			push_error("Replay recursion detected at: " + path + context_str)
			return false
		visited[id] = true

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR, TYPE_TRANSFORM3D:
			return true

		TYPE_ARRAY:
			for i in value.size():
				if not _detect_potential_recursion(value[i], visited, path + "[" + str(i) + "]", command_context):
					return false
			return true

		TYPE_DICTIONARY:
			var new_context = command_context.duplicate()
			
			# If this is a command dict, extract tick and type
			if "tick" in value and "type" in value:
				new_context["tick"] = value.get("tick")
				new_context["type"] = value.get("type")
			
			for k in value.keys():
				if not _detect_potential_recursion(value[k], visited, path + "." + str(k), new_context):
					return false
			return true

		TYPE_OBJECT:
			# Nodes are forbidden
			if value is Node:
				var context_str = _format_command_context(command_context)
				push_error("Replay contains Node at: " + path + context_str)
				return false

			# Resources — validate their properties
			if value is Resource:
				for prop in value.get_property_list():
					if prop.usage & PROPERTY_USAGE_STORAGE == 0:
						continue
					var prop_value = value.get(prop.name)
					if not _detect_potential_recursion(prop_value, visited, path + "." + prop.name, command_context):
						return false
				return true

			# ❌ Other objects forbidden
			var context_str = _format_command_context(command_context)
			push_error("Replay contains unsupported Object type at: " + path + context_str + " -> " + str(value))
			return false

		_:
			var context_str = _format_command_context(command_context)
			print("unsupported type:", value, typeof(value))
			push_error("Replay contains unsupported type at: " + path + context_str + " -> " + value)
			return false

func _format_command_context(context: Dictionary) -> String:
	if context.is_empty():
		return ""
	
	var parts = []
	if "tick" in context:
		parts.append("tick=" + str(context["tick"]))
	if "type" in context:
		parts.append("type=" + str(context["type"]))
	
	if parts.is_empty():
		return ""
	
	return " (Command: " + ", ".join(parts) + ")"

class FileIO:
	## Save a Resource to disk, creating directories as needed.
	## Returns OK on success, or the error code on failure.
	static func save_resource(resource: Resource, path: String) -> Error:
		var dir_path = path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			var dir_err = DirAccess.make_dir_recursive_absolute(dir_path)
			if dir_err != OK:
				push_error("FileIO: failed to create directory '%s' (error %s)" % [dir_path, dir_err])
				return dir_err
		var err = ResourceSaver.save(resource, path)
		if err != OK:
			push_error("FileIO: failed to save resource to '%s' (error %s)" % [path, err])
		return err

	## Load a Resource from disk. Returns null on failure.
	static func load_resource(path: String) -> Resource:
		if not ResourceLoader.exists(path):
			push_error("FileIO: resource not found at '%s'" % path)
			return null
		var resource = ResourceLoader.load(path)
		if resource == null:
			push_error("FileIO: failed to load resource from '%s'" % path)
		return resource
