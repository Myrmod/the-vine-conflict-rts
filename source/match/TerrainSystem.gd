class_name TerrainSystem

extends Node3D


#func apply_map(map: MapResource):
	#self.map = map
	#_build_mesh()
	#_build_index_texture()
#
#
#func _build_mesh():
	#var plane := PlaneMesh.new()
	#plane.size = Vector2(map.size.x, map.size.y)
#
	## If you want one quad per tile:
	#plane.subdivide_width = map.size.x - 1
	#plane.subdivide_depth = map.size.y - 1
#
	#terrain_mesh.mesh = plane
#
#func _build_index_texture():
	#print("TODO")
