class_name UnitHelper


static func is_structure(scene_ref: Variant) -> bool:
	var tab = UnitConstants.get_default_properties(scene_ref).get("production_tab_type", -1)
	return tab == Enums.ProductionTabType.STRUCTURE or tab == Enums.ProductionTabType.DEFENCES
