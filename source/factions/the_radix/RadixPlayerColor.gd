class_name RadixPlayerColor

## Shared player-color tinting logic for Radix entities.
##
## Radix GLBs use a dedicated material slot named "PlayerColor" (or, as a
## fallback, a slot whose albedo matches the authoring color below). This
## helper finds those slots under any subtree and replaces them with a flat,
## unshaded, emissive `StandardMaterial3D` so the player color stays a solid
## recognizable tint with only a soft glow halo on top.

## Default emission multiplier used by Radix entities. Kept low so the flat
## player color stays recognizable; the glow is just a soft bloom halo.
const DEFAULT_EMISSION_ENERGY: float = 1.5

## Authoring albedo of the GLB "PlayerColor" slot, used as a fallback match
## when the material's resource name was stripped during import.
const PLAYER_COLOR_ALBEDO_FALLBACK := Color(1.0, 0.8144, 0.4877)
const PLAYER_COLOR_ALBEDO_EPSILON: float = 0.05


## Walk `root` and return every PlayerColor surface as a flat unshaded
## `StandardMaterial3D` set as a surface override. The returned materials are
## live — mutate them later via [method refresh_materials] (or directly) and
## the change shows up on screen with no further work.
static func apply(
	root: Node, color: Color, emission_energy: float = DEFAULT_EMISSION_ENERGY
) -> Array[StandardMaterial3D]:
	var materials: Array[StandardMaterial3D] = []
	if root == null:
		return materials
	for mesh in _collect_mesh_instances(root):
		if mesh.mesh == null:
			continue
		for surface_idx in range(mesh.mesh.get_surface_count()):
			if not is_player_color_surface(mesh, surface_idx):
				continue
			var mat := _build_flat_glow_material(color, emission_energy)
			mesh.set_surface_override_material(surface_idx, mat)
			materials.append(mat)
	return materials


## Update a previously-built list of player-color materials in place.
static func refresh_materials(
	materials: Array[StandardMaterial3D],
	color: Color,
	emission_energy: float = DEFAULT_EMISSION_ENERGY
) -> void:
	for mat in materials:
		if mat == null:
			continue
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission_energy


## Build a single flat unshaded emissive material with the given color.
static func build_material(
	color: Color, emission_energy: float = DEFAULT_EMISSION_ENERGY
) -> StandardMaterial3D:
	return _build_flat_glow_material(color, emission_energy)


static func is_player_color_surface(mesh: MeshInstance3D, surface_idx: int) -> bool:
	if mesh == null or mesh.mesh == null:
		return false
	var surface_name: String = mesh.mesh.surface_get_name(surface_idx).to_lower()
	if surface_name.contains("playercolor") or surface_name.contains("player_color"):
		return true
	var src: Material = mesh.mesh.surface_get_material(surface_idx)
	if _material_indicates_player_color(src):
		return true
	var active: Material = mesh.get_active_material(surface_idx)
	if _material_indicates_player_color(active):
		return true
	# Fallback: source material albedo matches the GLB's PlayerColor slot color.
	if src is StandardMaterial3D:
		var sm := src as StandardMaterial3D
		if (
			absf(sm.albedo_color.r - PLAYER_COLOR_ALBEDO_FALLBACK.r) <= PLAYER_COLOR_ALBEDO_EPSILON
			and (
				absf(sm.albedo_color.g - PLAYER_COLOR_ALBEDO_FALLBACK.g)
				<= PLAYER_COLOR_ALBEDO_EPSILON
			)
			and (
				absf(sm.albedo_color.b - PLAYER_COLOR_ALBEDO_FALLBACK.b)
				<= PLAYER_COLOR_ALBEDO_EPSILON
			)
		):
			return true
	return false


static func _material_indicates_player_color(material: Material) -> bool:
	if material == null:
		return false
	var name_lower := material.resource_name.to_lower()
	if name_lower.contains("playercolor") or name_lower.contains("player_color"):
		return true
	var path_lower := material.resource_path.to_lower()
	return path_lower.contains("playercolor") or path_lower.contains("player_color")


static func _build_flat_glow_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = emission_energy
	return mat


static func _collect_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var results: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		results.append(root)
	for child in root.get_children():
		results.append_array(_collect_mesh_instances(child))
	return results
