class_name UnitHelper


static func is_structure(scene_path: String) -> bool:
	var tab = UnitConstants.DEFAULT_PROPERTIES.get(scene_path, {}).get("production_tab_type", -1)
	return tab == Enums.ProductionTabType.STRUCTURE or tab == Enums.ProductionTabType.DEFENCES
