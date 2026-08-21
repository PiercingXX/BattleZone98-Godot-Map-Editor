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
##   transition:4 and a diagonal-mirror remap; this module does not implement
##   that remap. Read/write is verbatim uint16 either way — the layout only
##   matters for auto-paint.
## - `read` infers (rows, cols) via closest factor pair (`rows <= cols`). A
##   tall 3×2-zone map is therefore read as 2×3. Companion HG2 size-guard
##   (F2 §8.4) is not in this module.

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

	static func read(path: String) -> Dictionary:
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
		var pair: Vector2i = BzMat._closest_factor_pair(n)
		var rows: int = pair.x
		var cols: int = pair.y
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
					var row: int = world_z * cols + zxi * ZONE_TILES
					for sub_x in ZONE_TILES:
						words[row + sub_x] = raw[src]
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
						var row: int = world_z * cols + zxi * ZONE_TILES
						for sub_x in ZONE_TILES:
							out.encode_u16(off, data[row + sub_x] & 0xFFFF)
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


static func kind_of_entry(word: int) -> String:
	var d: Dictionary = decode_entry(word)
	if int(d["mat_a"]) == int(d["mat_b"]):
		return "solid"
	if int(d["cap"]) != 0:
		return "diag"
	return "cap"


static func _march_square(colors: PackedInt32Array) -> int:
	var uniq: Array[int] = []
	for c in colors:
		if not uniq.has(int(c)):
			uniq.append(int(c))
	uniq.sort()
	var base: int = uniq[0]
	if uniq.size() == 1:
		return encode_entry(base, base)
	var nxt: int = uniq[uniq.size() - 1]
	var mask: int = 0
	if colors[0] == nxt:
		mask |= 8
	if colors[1] == nxt:
		mask |= 4
	if colors[2] == nxt:
		mask |= 2
	if colors[3] == nxt:
		mask |= 1
	var cap: int = 0
	var flip: int = 0
	var rot: int = 0
	if mask == 15:
		var tmp: int = base
		base = nxt
		nxt = tmp
	elif mask == 8:
		cap = 0
		flip = 0
		rot = 0
	elif mask == 4:
		cap = 0
		flip = 0
		rot = 3
	elif mask == 2:
		cap = 0
		flip = 0
		rot = 2
	elif mask == 1:
		cap = 0
		flip = 0
		rot = 1
	elif mask == 12:
		cap = 0
		flip = 1
		rot = 0
	elif mask == 6:
		cap = 0
		flip = 1
		rot = 3
	elif mask == 3:
		cap = 0
		flip = 1
		rot = 2
	elif mask == 9:
		cap = 0
		flip = 1
		rot = 1
	elif mask == 10:
		cap = 1
		flip = 0
		rot = 0
	elif mask == 5:
		cap = 1
		flip = 1
		rot = 0
	elif mask == 7 or mask == 11 or mask == 13 or mask == 14:
		var swap_b: int = base
		base = nxt
		nxt = swap_b
		var inv: int = (~mask) & 15
		if inv == 8:
			cap = 0
			flip = 0
			rot = 0
		elif inv == 4:
			cap = 0
			flip = 0
			rot = 3
		elif inv == 2:
			cap = 0
			flip = 0
			rot = 2
		elif inv == 1:
			cap = 0
			flip = 0
			rot = 1
	return encode_entry(base, nxt, cap, flip, rot)


## F2 §5 painter: a 2×2 of vertex colours → tile word, with 1-vertex corners
## promoted to diagonals (cap bit). Edges stay caps (flip bit). Height-based
## auto_paint keeps `_march_square` unchanged.
static func autotile_quad(colors: PackedInt32Array) -> int:
	var word: int = _march_square(colors)
	var mat_a: int = (word >> 12) & MATERIAL_MASK
	var mat_b: int = (word >> 8) & MATERIAL_MASK
	if mat_a == mat_b:
		return word
	var cap: int = (word >> 7) & 1
	var flip: int = (word >> 6) & 1
	if cap == 0 and flip == 0:
		return word | (1 << 7)
	return word


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
			return _autotile_owned(self_m, other, _autotile_cap(self_m, other, 0))
		if not es:
			return _autotile_owned(self_m, other, _autotile_cap(self_m, other, 1))
		if not ss:
			return _autotile_owned(self_m, other, _autotile_cap(self_m, other, 2))
		return _autotile_owned(self_m, other, _autotile_cap(self_m, other, 3))
	if k == 2:
		if ns and ss:
			return _autotile_owned(self_m, other, _autotile_cap(self_m, other, 1 if not es else 3))
		if es and ws:
			return _autotile_owned(self_m, other, _autotile_cap(self_m, other, 0 if not ns else 2))
		# Adjacent same-neighbours: this cell is an outer corner of `self_m`.
		# The foreign vertex is opposite the two same sides (F2 §5.3).
		# Atlas D tiles face left at identity; rotate onto NW/NE/SE/SW.
		if es and ss:
			return encode_diag(self_m, other, 0)
		if ss and ws:
			return encode_diag(self_m, other, 1)
		if ws and ns:
			return encode_diag(self_m, other, 2)
		return encode_diag(self_m, other, 3)
	if ns:
		return _autotile_owned(self_m, other, _autotile_cap(self_m, other, 2))
	if es:
		return _autotile_owned(self_m, other, _autotile_cap(self_m, other, 3))
	if ss:
		return _autotile_owned(self_m, other, _autotile_cap(self_m, other, 0))
	return _autotile_owned(self_m, other, _autotile_cap(self_m, other, 1))


static func _autotile_owned(self_m: int, other: int, word: int) -> int:
	var cap: int = (word >> 7) & 1
	var flip: int = (word >> 6) & 1
	var rot: int = (word >> 4) & 0x3
	var variant: int = word & 0x3
	return encode_entry(self_m, other, cap, flip, rot, variant)


static func _autotile_cap(self_m: int, other: int, side: int) -> int:
	var c := PackedInt32Array([self_m, self_m, self_m, self_m])
	match side:
		0:
			c[0] = other
			c[1] = other
		1:
			c[1] = other
			c[2] = other
		2:
			c[2] = other
			c[3] = other
		_:
			c[0] = other
			c[3] = other
	return autotile_quad(c)


## Atlas `*D*` tiles face left. `corner`: 0=NW (identity / left), 1=NE, 2=SE, 3=SW.
## Packs F2 orientation 14, 13, 12, 15 (unmirrored quartet).
static func encode_diag(self_m: int, other: int, corner: int, variant: int = 0) -> int:
	var packed_rot: PackedInt32Array = PackedInt32Array([2, 1, 0, 3])
	var rot: int = packed_rot[clampi(corner, 0, 3)]
	return encode_entry(self_m, other, 1, 1, rot, variant)


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


static func read_mat(path: String) -> Dictionary:
	return MaterialGrid.read(path)


static func write_mat(path: String, grid: MaterialGrid) -> Dictionary:
	return grid.write(path)
