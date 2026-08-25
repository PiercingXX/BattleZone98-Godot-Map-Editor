extends RefCounted
class_name BzMat
## Port of backend/bzmap/formats/mat.py — MaterialGrid + encode/auto-paint.
##
## On-disk tiles are zone-major at 64 tiles/zone (same scheme as HG2, F1 §4 /
## F2 §3). In-memory `MaterialGrid.data` is world row-major, index
## `z * grid_x + x`.
##
## Python-vs-spec (F2) discrepancies — Python wins:
## - Tile-word bit layout is the WorldBuilder-inferred pack used by
##   `encode_entry` / `decode` (matA:4, matB:4, cap:1, flip:1, rot:2,
##   unused:2, variant:2). F2 §2 specifies orientation:4, variant:4, base:4,
##   transition:4 and a diagonal-mirror remap. Read/write is verbatim uint16
##   either way — the layout only matters for auto-paint and for the viewport,
##   which both follow the measured table below.
##
## Axis order (settled 2026-08-24): plain zone interleave, no mirror — disk
## tile 0 of the first zone is world x=0, z=0. See the BzHg2 header for the
## measurement that settled it; `.mat` follows its `.hg2` exactly.
##
## Tile orientation (settled 2026-08-24 against 57 stock maps, 155k transition
## tiles, cross-checked against the Mars / Elysium / Io atlas art). `rot` turns
## clockwise in grid space and the `flip` bit does not change the topology at
## all — it only picks a mirrored cut of the same art:
##
##   cap  (bit 7 clear): `mat_b` fills the half toward rot 0=-Z 1=+X 2=+Z 3=-X,
##                       `mat_a` fills the other half.
##   diag (bit 7 set):   `mat_a` is the ONE corner, `mat_b` fills the other
##                       three; the corner is rot 0=(-X,+Z) 1=(-X,-Z)
##                       2=(+X,-Z) 3=(+X,+Z).
##
## Which cell carries the transition (measured 2026-08-24 by tabulating every
## stock cell against its neighbours). A boundary gets ONE transition tile, and
## the two kinds sit on opposite sides of it:
##
##   a cell with one HIGHER neighbour      -> cap    64%, solid 36%
##   a cell with one LOWER neighbour       -> solid  86%, diag 10%
##   a cell with two adjacent LOWER ones   -> diag   69%, solid 30%
##
## So a CAP belongs to the LOWER cell — mostly its own material, with the
## higher one fringing in from the side rot names — and a DIAGONAL belongs to
## the HIGHER cell at its convex corner, where the lower material cuts the
## corner off. That is the only direction the atlas ships, every tile being
## base<trans. `fill_of_entry` reads a cap's fill out of `mat_a` and a
## diagonal's out of `mat_b` for that reason.
##
## The ~30% that stay solid are not a further rule: only a sixth of them lack a
## shipped tile for the pair, and the rest is hand-authoring. A consistent
## editor is the better behaviour there.


## Corner index: 0=(-X,-Z) 1=(+X,-Z) 2=(+X,+Z) 3=(-X,+Z). Side index:
## 0=-Z 1=+X 2=+Z 3=-X. A cap's `rot` IS its side; a diagonal's `rot` is
## DIAG_ROT of the corner its `mat_a` occupies.
const DIAG_ROT: Array[int] = [1, 2, 3, 0]

const TILE_CELLS: int = 4
const ZONE_TILES: int = 64
const TILE_M: float = 20.0
const MATERIAL_MASK: int = 0xF


static func _fail(message: String, hint: String = "") -> Dictionary:
	return {
		"ok": false,
		"error": {"code": "value_error", "message": message, "hint": hint},
	}


static func _closest_factor_pair(n: int) -> Vector2i:
	## Return (rows, cols) of n with the least difference; rows <= cols.
	var root: int = int(sqrt(float(n)))
	var rows: int = root
	while rows > 0:
		if n % rows == 0:
			return Vector2i(rows, n / rows)
		rows -= 1
	push_error("%d has no factor pair (should not happen)" % n)
	return Vector2i(1, n)


class MaterialGrid:
	extends RefCounted

	var data: PackedInt32Array = PackedInt32Array()
	var grid_x: int = 0
	var grid_z: int = 0

	func _init(p_data: PackedInt32Array, p_grid_z: int = -1, p_grid_x: int = -1) -> void:
		data = p_data
		if p_grid_z >= 0 and p_grid_x >= 0:
			grid_z = p_grid_z
			grid_x = p_grid_x
		else:
			var pair: Vector2i = BzMat._closest_factor_pair(p_data.size())
			grid_z = pair.x
			grid_x = pair.y
		if grid_x > 0 and grid_z > 0 and data.size() != grid_z * grid_x:
			push_error(
				"data length %d does not match %dx%d" % [data.size(), grid_x, grid_z]
			)

	var width_m: float:
		get:
			return float(grid_x) * BzMat.TILE_M

	var depth_m: float:
		get:
			return float(grid_z) * BzMat.TILE_M

	static func read(path: String, expect_rows: int = -1, expect_cols: int = -1) -> Dictionary:
		## `expect_rows` / `expect_cols` come from the companion `.hg2` zone
		## counts. Without them the shape is guessed from the sample count, and
		## the guess transposes every non-square map (a 2×3-zone map reads as
		## 3×2) — pass them whenever the heightmap is in hand.
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return BzMat._fail(
				"%s: cannot open (%s)" % [path, error_string(FileAccess.get_open_error())]
			)
		var buf: PackedByteArray = file.get_buffer(file.get_length())
		file.close()
		# numpy fromfile(uint16) keeps whole samples and drops a trailing odd byte.
		var n: int = buf.size() / 2
		if n == 0:
			return BzMat._fail("%s: empty MAT file" % path)
		var raw := PackedInt32Array()
		raw.resize(n)
		for i in n:
			raw[i] = buf.decode_u16(i * 2)
		var rows: int
		var cols: int
		if expect_rows > 0 and expect_cols > 0:
			# F2 §8.4 size guard: a .mat that does not match its .hg2 belongs to
			# another map. Refuse it by name rather than reading it crookedly.
			if expect_rows * expect_cols != n:
				return BzMat._fail(
					"%s: %d tiles, but the heightmap wants %dx%d = %d"
					% [path, n, expect_cols, expect_rows, expect_rows * expect_cols],
					"The .mat belongs to a different map than the .hg2 next to it."
				)
			rows = expect_rows
			cols = expect_cols
		else:
			var pair: Vector2i = BzMat._closest_factor_pair(n)
			rows = pair.x
			cols = pair.y
		var zz_count: int = rows / ZONE_TILES
		var zx_count: int = cols / ZONE_TILES
		if rows % ZONE_TILES != 0 or cols % ZONE_TILES != 0:
			return {"ok": true, "grid": MaterialGrid.new(raw, rows, cols)}
		var words := PackedInt32Array()
		words.resize(rows * cols)
		var src: int = 0
		for zzi in zz_count:
			for zxi in zx_count:
				for sub_z in ZONE_TILES:
					var world_z: int = zzi * ZONE_TILES + sub_z
					var row: int = world_z * cols
					var col: int = zxi * ZONE_TILES
					for sub_x in ZONE_TILES:
						words[row + col + sub_x] = raw[src]
						src += 1
		return {"ok": true, "grid": MaterialGrid.new(words, rows, cols)}

	func write(path: String) -> Dictionary:
		var rows: int = grid_z
		var cols: int = grid_x
		var out := PackedByteArray()
		out.resize(data.size() * 2)
		if rows % ZONE_TILES != 0 or cols % ZONE_TILES != 0:
			for i in data.size():
				out.encode_u16(i * 2, data[i] & 0xFFFF)
		else:
			var zz_count: int = rows / ZONE_TILES
			var zx_count: int = cols / ZONE_TILES
			var off: int = 0
			for zzi in zz_count:
				for zxi in zx_count:
					for sub_z in ZONE_TILES:
						var world_z: int = zzi * ZONE_TILES + sub_z
						var row: int = world_z * cols
						var col: int = zxi * ZONE_TILES
						for sub_x in ZONE_TILES:
							out.encode_u16(off, data[row + col + sub_x] & 0xFFFF)
							off += 2
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return BzMat._fail(
				"%s: cannot write (%s)" % [path, error_string(FileAccess.get_open_error())]
			)
		file.store_buffer(out)
		file.close()
		return {"ok": true}

	func decode() -> PackedInt32Array:
		## Flat (grid_z * grid_x * 6) of (mat_a, mat_b, cap, flip, rot, variant).
		var n: int = grid_z * grid_x
		var out := PackedInt32Array()
		out.resize(n * 6)
		for i in n:
			var d: int = data[i]
			var base: int = i * 6
			out[base] = (d >> 12) & MATERIAL_MASK
			out[base + 1] = (d >> 8) & MATERIAL_MASK
			out[base + 2] = (d >> 7) & 1
			out[base + 3] = (d >> 6) & 1
			out[base + 4] = (d >> 4) & 0x3
			out[base + 5] = d & 0x3
		return out


static func encode_entry(
	mat_a: int, mat_b: int = 0, cap: int = 0, flip: int = 0, rot: int = 0, variant: int = 0
) -> int:
	var entry: int = 0
	entry |= variant & 0x3
	entry |= (rot & 0x3) << 4
	entry |= (flip & 0x1) << 6
	entry |= (cap & 0x1) << 7
	entry |= (mat_b & MATERIAL_MASK) << 8
	entry |= (mat_a & MATERIAL_MASK) << 12
	return entry


static func decode_entry(word: int) -> Dictionary:
	return {
		"mat_a": (word >> 12) & MATERIAL_MASK,
		"mat_b": (word >> 8) & MATERIAL_MASK,
		"cap": (word >> 7) & 1,
		"flip": (word >> 6) & 1,
		"rot": (word >> 4) & 0x3,
		"variant": word & 0x3,
	}


## The material the cell is filled with. A cap belongs to the lower cell and
## keeps its own fill in `mat_a`; a diagonal belongs to the higher cell at a
## convex corner, so its fill is the three-corner field in `mat_b`.
static func fill_of_entry(word: int) -> int:
	var mat_a: int = (word >> 12) & MATERIAL_MASK
	var mat_b: int = (word >> 8) & MATERIAL_MASK
	if mat_a != mat_b and ((word >> 7) & 1) != 0:
		return mat_b
	return mat_a


static func kind_of_entry(word: int) -> String:
	var d: Dictionary = decode_entry(word)
	if int(d["mat_a"]) == int(d["mat_b"]):
		return "solid"
	if int(d["cap"]) != 0:
		return "diag"
	return "cap"


static func _march_square(colors: PackedInt32Array) -> int:
	## Four corner materials → one tile word. `colors` is corner-ordered:
	## (-X,-Z), (+X,-Z), (+X,+Z), (-X,+Z).
	##
	## Every transition tile any world ships is base<trans (64 of 64 across the
	## nine stock atlases), so the lower material is always `mat_a`. That is
	## also the only material a diagonal can put in its lone corner, which is
	## what decides the shapes below.
	var uniq: Array[int] = []
	for c in colors:
		if not uniq.has(int(c)):
			uniq.append(int(c))
	uniq.sort()
	var base: int = uniq[0]
	if uniq.size() == 1:
		return encode_entry(base, base)
	var nxt: int = uniq[uniq.size() - 1]
	var hi: Array[int] = []
	var lo: Array[int] = []
	for i in 4:
		if int(colors[i]) == nxt:
			hi.append(i)
		else:
			lo.append(i)
	if hi.size() == 4:
		return encode_entry(nxt, nxt)
	if lo.size() == 1:
		# One corner of the lower material in a field of the higher — the
		# diagonal tile's own shape.
		return encode_diag(base, nxt, lo[0])
	if hi.size() == 1:
		# The mirror image of that — one corner of the HIGHER material — has no
		# tile in any shipped atlas, and a cap would spread it over a whole
		# half. The cell is three-quarters `base`; leave it solid.
		return encode_entry(base, base)
	# Two corners. Adjacent is a straight edge and caps exactly; the two
	# diagonal pairs are a saddle no single tile can show, so cap one edge.
	var side: int = _side_of_corner_pair(hi[0], hi[1])
	return encode_entry(base, nxt, 0, 0, side)


static func _side_of_corner_pair(a: int, b: int) -> int:
	## The side whose two corners are {a, b}; a diagonal pair has no side, so
	## it falls back to the lower corner's own side.
	for side in 4:
		var c0: int = side
		var c1: int = (side + 1) & 3
		if (a == c0 and b == c1) or (a == c1 and b == c0):
			return side
	return mini(a, b)


## F2 §5 painter: a 2×2 of corner materials → tile word. `_march_square` now
## picks the diagonal shape itself, so this is the plain call; it stays a named
## entry point because auto-paint and the tests both reach for it.
static func autotile_quad(colors: PackedInt32Array) -> int:
	return _march_square(colors)


## Face-centred match (F2 §5): `self_m` vs four orthogonal neighbour fills.
## Out-of-range neighbours should be passed as `self_m` so map borders autotile.
static func autotile_neighbors(self_m: int, n: int, e: int, s: int, w: int) -> int:
	self_m &= MATERIAL_MASK
	n &= MATERIAL_MASK
	e &= MATERIAL_MASK
	s &= MATERIAL_MASK
	w &= MATERIAL_MASK
	var ns := n == self_m
	var es := e == self_m
	var ss := s == self_m
	var ws := w == self_m
	var k: int = int(ns) + int(es) + int(ss) + int(ws)
	if k == 4 or k == 0:
		return encode_entry(self_m, self_m)
	var other: int = self_m
	if not ns:
		other = n
	elif not es:
		other = e
	elif not ss:
		other = s
	else:
		other = w
	if k == 3:
		if not ns:
			return _autotile_cap(self_m, other, 0)
		if not es:
			return _autotile_cap(self_m, other, 1)
		if not ss:
			return _autotile_cap(self_m, other, 2)
		return _autotile_cap(self_m, other, 3)
	if k == 2:
		if ns and ss:
			return _autotile_cap(self_m, other, 1 if not es else 3)
		if es and ws:
			return _autotile_cap(self_m, other, 0 if not ns else 2)
		# Adjacent same-neighbours: this cell is an outer corner of `self_m`.
		# The foreign corner is opposite the two same sides (F2 §5.3).
		if es and ss:
			return _autotile_corner(self_m, other, 0)
		if ss and ws:
			return _autotile_corner(self_m, other, 1)
		if ws and ns:
			return _autotile_corner(self_m, other, 2)
		return _autotile_corner(self_m, other, 3)
	if ns:
		return _autotile_cap(self_m, other, 2)
	if es:
		return _autotile_cap(self_m, other, 3)
	if ss:
		return _autotile_cap(self_m, other, 0)
	return _autotile_cap(self_m, other, 1)


static func _autotile_cap(self_m: int, other: int, side: int) -> int:
	## `other` is the differing fill across `side` (0=-Z 1=+X 2=+Z 3=-X).
	##
	## A cap belongs to the LOWER cell: mostly its own material, with the
	## higher one fringing in from `side`, which is exactly what rot names. So
	## when `self_m` is the higher material the neighbour owns this boundary
	## and this cell stays solid — see the table in the header.
	if self_m >= other:
		return encode_entry(self_m, self_m)
	return encode_entry(self_m, other, 0, 0, side & 3)


static func _autotile_corner(self_m: int, other: int, corner: int) -> int:
	## `other` meets this cell at `corner` only. A diagonal is the cap's
	## opposite number: it belongs to the HIGHER cell, at its convex corner,
	## with the lower material cutting that corner off.
	if other < self_m:
		return encode_diag(other, self_m, corner)
	# This cell is the lower one, and the higher material reaches it from the
	# two sides meeting at `corner`. No tile shows a high corner, so fringe one
	# of those sides instead.
	return _autotile_cap(self_m, other, corner)


## `corner_m` fills the single corner `corner` (0=(-X,-Z) 1=(+X,-Z) 2=(+X,+Z)
## 3=(-X,+Z)) and `field_m` fills the other three — the diagonal tile's own
## shape, measured from 4712 stock corner tiles whose four diagonal neighbours
## are all solid. `corner_m` must be the lower material: no atlas ships a
## base>trans tile.
static func encode_diag(corner_m: int, field_m: int, corner: int, variant: int = 0) -> int:
	return encode_entry(corner_m, field_m, 1, 0, DIAG_ROT[clampi(corner, 0, 3)], variant)


static func auto_paint(heightmap: Variant, rules: Array) -> Variant:
	var raw: PackedInt32Array = heightmap.data
	var w: int = int(heightmap.grid_x)
	var h: int = int(heightmap.grid_z)
	if h % TILE_CELLS != 0 or w % TILE_CELLS != 0:
		push_error(
			"heightmap %dx%d is not a multiple of %d cells per MAT tile" % [w, h, TILE_CELLS]
		)
		return _fail(
			"heightmap %dx%d is not a multiple of %d cells per MAT tile" % [w, h, TILE_CELLS]
		)
	var n: int = w * h
	var heights := PackedFloat64Array()
	heights.resize(n)
	for i in n:
		heights[i] = float(raw[i]) * BzHg2.HEIGHT_SCALE
	var slopes: PackedFloat64Array = BzHg2.slope(heightmap)
	var vertex_mats := PackedByteArray()
	vertex_mats.resize(n)
	for rule_v in rules:
		var rule: Dictionary = rule_v
		var mat_id: int = int(rule["mat_id"])
		var min_h: float = float(rule["min_h"])
		var max_h: float = float(rule["max_h"])
		var min_s: float = float(rule["min_s"])
		var max_s: float = float(rule["max_s"])
		for i in n:
			if (
				heights[i] >= min_h
				and heights[i] <= max_h
				and slopes[i] >= min_s
				and slopes[i] <= max_s
			):
				vertex_mats[i] = mat_id
	var mat_h: int = h / TILE_CELLS
	var mat_w: int = w / TILE_CELLS
	var mat_data := PackedInt32Array()
	mat_data.resize(mat_h * mat_w)
	for y in mat_h:
		for x in mat_w:
			var colors := PackedInt32Array([
				int(vertex_mats[y * TILE_CELLS * w + x * TILE_CELLS]),
				int(vertex_mats[y * TILE_CELLS * w + x * TILE_CELLS + 1]),
				int(vertex_mats[(y * TILE_CELLS + 1) * w + x * TILE_CELLS + 1]),
				int(vertex_mats[(y * TILE_CELLS + 1) * w + x * TILE_CELLS]),
			])
			mat_data[y * mat_w + x] = _march_square(colors)
	return MaterialGrid.new(mat_data, mat_h, mat_w)


static func read_mat(path: String, expect_rows: int = -1, expect_cols: int = -1) -> Dictionary:
	return MaterialGrid.read(path, expect_rows, expect_cols)


static func write_mat(path: String, grid: MaterialGrid) -> Dictionary:
	return grid.write(path)
