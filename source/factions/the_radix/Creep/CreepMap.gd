class_name CreepMap

enum CellType {
	EMPTY,
	FULL,
}

var width: int
var height: int
## 0 means empty, 1 means full, see CellType enum above
var cells: PackedByteArray


func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(pos.x / 1.0), int(pos.z / 1.0))
