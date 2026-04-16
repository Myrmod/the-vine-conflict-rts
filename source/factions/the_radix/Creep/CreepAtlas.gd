class_name CreepAtlas

## Defines the orthogonal-neighbour tile layout for creep_terrain8x3.png.
##
## The atlas is 4096×1536: 8 columns × 3 rows of 512×512 px tiles.
##
## ── Left half (columns 0–2): outer boundary tiles ────────────────────────
## Selected by a 4-bit orthogonal bitmask (bit SET = that neighbour has creep):
##
##   N neighbour → bit 0 (value 1)
##   E neighbour → bit 1 (value 2)
##   S neighbour → bit 2 (value 4)
##   W neighbour → bit 3 (value 8)
##
##   (col, row) │ Tile          │ Ortho mask (present neighbours)
##   ───────────┼───────────────┼─────────────────────────────────
##   (0, 0)     │ NW outer      │ E + S          (mask 6)
##   (1, 0)     │ N  outer edge │ E + S + W      (mask 14)
##   (2, 0)     │ NE outer      │ S + W          (mask 12)
##   (0, 1)     │ W  outer edge │ N + E + S      (mask 7)
##   (1, 1)     │ (fallback)    │ aliased to ALL
##   (2, 1)     │ E  outer edge │ N + S + W      (mask 13)
##   (0, 2)     │ SW outer      │ N + E          (mask 3)
##   (1, 2)     │ S  outer edge │ N + E + W      (mask 11)
##   (2, 2)     │ SE outer      │ N + W          (mask 9)
##
## Rare mask (0, 5, 10) falls back to the ALL tile at (4, 1).
##
## ── End tiles (columns 6–7): single-neighbour tiles ──────────────────────
## Used when a cell has exactly one orthogonal creep neighbour.
##
##   (col, row) │ Tile    │ Ortho mask (present neighbour)
##   ───────────┼─────────┼────────────────────────────────
##   (6, 0)     │ E end   │ E only  (mask 2)
##   (7, 0)     │ N end   │ N only  (mask 1)
##   (6, 1)     │ W end   │ W only  (mask 8)
##   (7, 1)     │ S end   │ S only  (mask 4)
##
## ── Right half (columns 3–5): inner corner tiles ─────────────────────────
## Used only when all four orthogonal neighbours have creep (mask 15).
## The specific tile is chosen by which diagonal neighbours are absent.
##
##   (col, row) │ Tile          │ Absent diagonal(s)
##   ───────────┼───────────────┼────────────────────────────
##   (3, 0)     │ NW inner      │ NW only
##   (4, 0)     │ N  inner edge │ NW + NE
##   (5, 0)     │ NE inner      │ NE only
##   (3, 1)     │ W  inner edge │ NW + SW
##   (4, 1)     │ ALL (center)  │ none absent (fully covered)
##   (5, 1)     │ E  inner edge │ NE + SE
##   (3, 2)     │ SW inner      │ SW only
##   (4, 2)     │ S  inner edge │ SW + SE
##   (5, 2)     │ SE inner      │ SE only
##
## The shader selects the right-half column/row via:
##   atlas_col = 4 + sign(right_absent) - sign(left_absent)
##   atlas_row = 1 + sign(bot_absent)   - sign(top_absent)
## where *_absent counts how many of the two diagonals on that side are missing.
##
## See TerrainSystemTerrainMesh.gdshader for the GLSL implementation.

## Tile enum — value encodes atlas position as col + row * 8.
## Decode with tile_coords(): col = value % 8, row = value / 8.
enum Tile {
	NW_OUTER = 0,  ## (0, 0) outer corner facing NW
	N_OUTER = 1,  ## (1, 0) outer edge facing N
	NE_OUTER = 2,  ## (2, 0) outer corner facing NE
	NW_INNER = 3,  ## (3, 0) inner corner, NW diagonal absent
	N_INNER = 4,  ## (4, 0) inner N edge, NW+NE diagonals absent
	NE_INNER = 5,  ## (5, 0) inner corner, NE diagonal absent
	E_END = 6,  ## (6, 0) end tile, E neighbour only
	N_END = 7,  ## (7, 0) end tile, N neighbour only
	W_OUTER = 8,  ## (0, 1) outer edge facing W
	E_OUTER = 10,  ## (2, 1) outer edge facing E
	W_INNER = 11,  ## (3, 1) inner W edge, NW+SW diagonals absent
	ALL = 12,  ## (4, 1) fully covered, no absent diagonals
	E_INNER = 13,  ## (5, 1) inner E edge, NE+SE diagonals absent
	W_END = 14,  ## (6, 1) end tile, W neighbour only
	S_END = 15,  ## (7, 1) end tile, S neighbour only
	SW_OUTER = 16,  ## (0, 2) outer corner facing SW
	S_OUTER = 17,  ## (1, 2) outer edge facing S
	SE_OUTER = 18,  ## (2, 2) outer corner facing SE
	SW_INNER = 19,  ## (3, 2) inner corner, SW diagonal absent
	S_INNER = 20,  ## (4, 2) inner S edge, SW+SE diagonals absent
	SE_INNER = 21,  ## (5, 2) inner corner, SE diagonal absent
	SW_CORNER = 22,  ## (6, 2) SW outer at inward L-corner (SE diagonal has creep)
	W_CORNER = 23,  ## (7, 2) W outer at inward L-corner (NW diagonal has creep)
}

## Orthogonal neighbour bit weights used to build the selection mask.
const BIT_N: int = 1
const BIT_E: int = 2
const BIT_S: int = 4
const BIT_W: int = 8


## Decode a Tile into its atlas (col, row) coordinates.
static func tile_coords(tile: Tile) -> Vector2i:
	return Vector2i(int(tile) % 8, int(tile) / 8)


## Return the outer boundary tile for a cell given which orthogonal neighbours
## have creep. Returns ALL for mask 15 or any rare/degenerate mask.
static func ortho_tile(n: bool, e: bool, s: bool, w: bool) -> Tile:
	var mask: int = (int(n) * BIT_N) | (int(e) * BIT_E) | (int(s) * BIT_S) | (int(w) * BIT_W)
	match mask:
		6:
			return Tile.NW_OUTER
		14:
			return Tile.N_OUTER
		12:
			return Tile.NE_OUTER
		7:
			return Tile.W_OUTER
		13:
			return Tile.E_OUTER
		3:
			return Tile.SW_OUTER
		11:
			return Tile.S_OUTER
		9:
			return Tile.SE_OUTER
		2:
			return Tile.W_END
		1:
			return Tile.S_END
		8:
			return Tile.E_END
		4:
			return Tile.N_END
		_:
			return Tile.ALL
