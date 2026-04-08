class_name ResourceUtils


static func find_resource_unit_closest_to_unit_yet_no_further_than(
	unit, distance_max, filter_predicate = null
):
	var resource_units = unit.get_tree().get_nodes_in_group("resource_units")
	resource_units = resource_units.filter(
		func(ru):
			return (
				ru.is_harvestable()
				if ru.has_method("is_harvestable")
				else ("resource" in ru and ru.resource > 0)
			)
	)
	if filter_predicate != null:
		resource_units = resource_units.filter(filter_predicate)
	# TODO: Make anonymous-inline again once GDToolkit and Godot bugs are fixed.
	var mapper = func(resource_unit):
		var dist = (unit.global_position * Vector3(1, 0, 1)).distance_to(
			resource_unit.global_position * Vector3(1, 0, 1)
		)
		# Prefer fuller resources: empty vines get up to 2x effective distance penalty.
		var fullness = 1.0
		if "resource_max" in resource_unit and resource_unit.resource_max > 0:
			fullness = float(resource_unit.resource) / float(resource_unit.resource_max)
		var score = dist * (2.0 - fullness)
		return {"distance": dist, "score": score, "unit": resource_unit}
	var resource_units_sorted_by_distance = resource_units.map(mapper).filter(
		func(tuple): return tuple["distance"] <= distance_max
	)
	resource_units_sorted_by_distance.sort_custom(func(a, b): return a["score"] < b["score"])
	return (
		resource_units_sorted_by_distance[0]["unit"]
		if not resource_units_sorted_by_distance.is_empty()
		else null
	)
