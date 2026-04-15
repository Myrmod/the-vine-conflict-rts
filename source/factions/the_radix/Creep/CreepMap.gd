class_name CreepMap

## Bitmask grid tracking which Radix players have creep on each cell.
## Storage type is chosen once at initialize() based on player count:
##   ≤ 8  Radix players → PackedByteArray  (1 byte / cell)
##   ≤ 32 Radix players → PackedInt32Array (4 bytes / cell)
## Bit K represents player index (player.id - 1) % bit_width.

var width: int
var height: int
## Allocated in initialize(); type is either PackedByteArray or PackedInt32Array.
var cells
## Vitality health per cell (0 = dead / no creep, RadixConstants.CREEP_CELL_MAX_HEALTH = fully alive).
## Decays each tick when not vitalized by an owning CreepSource.
var cell_health: PackedByteArray = PackedByteArray()


func initialize(w: int, h: int, radix_player_count: int) -> void:
	width = w
	height = h
	if radix_player_count <= 8:
		cells = PackedByteArray()
		cells.resize(w * h)
	else:
		cells = PackedInt32Array()
		cells.resize(w * h)
	cell_health.resize(w * h)


func is_any_creep(cell: Vector2i) -> bool:
	return cells[_idx(cell)] != 0


func is_player_bit(cell: Vector2i, bit: int) -> bool:
	return (cells[_idx(cell)] >> bit) & 1 == 1


func set_player_bit(cell: Vector2i, bit: int, value: bool) -> void:
	var i: int = _idx(cell)
	if value:
		cells[i] = cells[i] | (1 << bit)
	else:
		cells[i] = cells[i] & ~(1 << bit)


func get_cell_health(cell: Vector2i) -> int:
	return cell_health[_idx(cell)]


func set_cell_health(cell: Vector2i, value: int) -> void:
	cell_health[_idx(cell)] = value


## Removes all creep and resets vitality for a cell (used by decay system).
func clear_cell(cell: Vector2i) -> void:
	var i: int = _idx(cell)
	cells[i] = 0
	cell_health[i] = 0


## Returns the orthogonal-neighbour index for the cell (matches the atlas and shader).
## N=bit0, E=bit1, S=bit2, W=bit3.
func ortho_index(cell: Vector2i) -> int:
	var n: bool = _has_creep_at(cell + Vector2i(0, -1))
	var e: bool = _has_creep_at(cell + Vector2i(1, 0))
	var s: bool = _has_creep_at(cell + Vector2i(0, 1))
	var w: bool = _has_creep_at(cell + Vector2i(-1, 0))
	return int(n) | (int(e) << 1) | (int(s) << 2) | (int(w) << 3)


func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.z)))


func _idx(cell: Vector2i) -> int:
	return cell.y * width + cell.x


func _has_creep_at(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return false
	return cells[_idx(cell)] != 0
