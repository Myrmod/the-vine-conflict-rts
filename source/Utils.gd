extends Node

const MatchUtils = preload("res://source/match/MatchUtils.gd")


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

func _detect_potential_recursion(value, visited: Dictionary, path: String) -> bool:
	# Detect circular references
	if typeof(value) == TYPE_OBJECT or typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_DICTIONARY:
		var id = value.get_instance_id() if value is Object else hash(value)
		if visited.has(id):
			push_error("Replay recursion detected at: " + path)
			return false
		visited[id] = true

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true

		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR:
			return true

		TYPE_ARRAY:
			for i in value.size():
				if not _detect_potential_recursion(value[i], visited, path + "[" + str(i) + "]"):
					return false
			return true

		TYPE_DICTIONARY:
			for k in value.keys():
				if not _detect_potential_recursion(value[k], visited, path + "." + str(k)):
					return false
			return true

		TYPE_OBJECT:
			# ❌ Nodes are forbidden
			if value is Node:
				push_error("Replay contains Node at: " + path)
				return false

			# ⚠️ Resources — validate their properties
			if value is Resource:
				for prop in value.get_property_list():
					if prop.usage & PROPERTY_USAGE_STORAGE == 0:
						continue
					var prop_value = value.get(prop.name)
					if not _detect_potential_recursion(prop_value, visited, path + "." + prop.name):
						return false
				return true

			# ❌ Other objects forbidden
			push_error("Replay contains unsupported Object type at: " + path + " -> " + str(value))
			return false

		_:
			push_error("Replay contains unsupported type at: " + path)
			return false
