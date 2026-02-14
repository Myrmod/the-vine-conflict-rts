extends ResourceUnit

const MATERIAL_ALBEDO_TO_REPLACE = Color(0.4687, 0.944, 0.7938)
const MATERIAL_ALBEDO_TO_REPLACE_EPSILON = 0.05

@export var resource_a = 300:
	set(value):
		resource_a = max(0, value)
		if resource_a == 0:
			# Unregister from EntityRegistry before freeing depleted resource
			EntityRegistry.unregister(self)
			queue_free()

var color = Resources.A.COLOR:
	set(_value):
		pass


func _ready():
	super._ready()
	_setup_mesh_colors()


func _setup_mesh_colors():
	# gdlint: ignore = function-preload-variable-name
	var material = preload(Resources.A.MATERIAL_PATH)
	MatchUtils.traverse_node_tree_and_replace_materials_matching_albedo(
		self , MATERIAL_ALBEDO_TO_REPLACE, MATERIAL_ALBEDO_TO_REPLACE_EPSILON, material
	)
