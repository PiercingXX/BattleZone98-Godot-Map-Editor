extends RefCounted
class_name ScatterMask
## The authoritative scatter record: one greyscale byte per heightfield cell.
##
## 0 is empty; any other value quantises to a species slot, so painting adds
## and painting black erases. Nothing else is stored — no transform list, no
## per-instance record — because the instances are re-derived from this image
## plus a seed (see ScatterField).
##
## Sixteen slots, FIXED. Quantising against the live species count would
## re-mean every stored byte the moment a species is added or removed, which
## silently repaints the map; pinning the divisor keeps a painted byte
## meaning what it meant when it was painted. Sixteen also mirrors the
## material word's 16 slots, so the two masks read alike.
##
## Chunk bookkeeping rides along with every write: an exact per-chunk,
## per-slot count (a bitmap alone cannot be maintained under erase without
## rescanning) whose derived bit says "this chunk holds something". An empty
## chunk is then skipped outright by cull and rebuild.

const SLOTS := 16
## Cells per preview/generation chunk. 32 cells = 160 m at the fixed 5 m grid.
const CHUNK_CELLS := 32
const EMPTY := 0

var grid_x: int = 0
var grid_z: int = 0
var chunks_x: int = 0
var chunks_z: int = 0
## Row-major, grid_x * grid_z. This is the file that ships in masks/<stem>.u8.
var values: PackedByteArray = PackedByteArray()

var _counts: PackedInt32Array = PackedInt32Array()
var _totals: PackedInt32Array = PackedInt32Array()
var _bits: PackedByteArray = PackedByteArray()
var _dirty: Dictionary = {}


## Byte a slot paints as. Slots land on 16, 32 ... 255, which stay distinct
## after a lossy image round-trip and read as visible steps of grey.
static func encode(slot: int) -> int:
	if slot < 0 or slot >= SLOTS:
		return EMPTY
	return int(round(float(slot + 1) * 255.0 / float(SLOTS)))


## Slot a byte means, or -1 for empty.
static func decode(value: int) -> int:
	var v := value & 0xFF
	if v == EMPTY:
		return -1
	return clampi(int(round(float(v) * float(SLOTS) / 255.0)) - 1, 0, SLOTS - 1)


static func chunk_key(cx: int, cz: int) -> int:
	return (cz << 16) | (cx & 0xFFFF)


static func key_x(key: int) -> int:
	return key & 0xFFFF


static func key_z(key: int) -> int:
	return key >> 16


func resize(p_grid_x: int, p_grid_z: int) -> void:
	grid_x = maxi(p_grid_x, 0)
	grid_z = maxi(p_grid_z, 0)
	chunks_x = int(ceil(float(grid_x) / float(CHUNK_CELLS))) if grid_x > 0 else 0
	chunks_z = int(ceil(float(grid_z) / float(CHUNK_CELLS))) if grid_z > 0 else 0
	values = PackedByteArray()
	values.resize(grid_x * grid_z)
	values.fill(EMPTY)
	_reset_chunk_state()
	mark_all_dirty()


func is_empty() -> bool:
	return grid_x < 1 or grid_z < 1


## Take a full-grid byte array (a loaded masks/<stem>.u8) and recount.
func adopt(bytes: PackedByteArray) -> bool:
	if bytes.size() != grid_x * grid_z or grid_x < 1:
		return false
	values = bytes.duplicate()
	recount()
	mark_all_dirty()
	return true


func recount() -> void:
	_reset_chunk_state()
	for z in grid_z:
		var row := z * grid_x
		var cz := z / CHUNK_CELLS
		for x in grid_x:
			var v := values[row + x]
			if v == EMPTY:
				continue
			var c := cz * chunks_x + (x / CHUNK_CELLS)
			_counts[c * SLOTS + decode(v)] += 1
			_totals[c] += 1
	for c in _totals.size():
		_set_bit(c, _totals[c] > 0)


func value_at(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= grid_x or z >= grid_z:
		return EMPTY
	return values[z * grid_x + x]


func slot_at(x: int, z: int) -> int:
	return decode(value_at(x, z))


## Raw byte write. -1 slots and undo regions both come through here.
func set_value(x: int, z: int, value: int) -> void:
	if x < 0 or z < 0 or x >= grid_x or z >= grid_z:
		return
	var v := value & 0xFF
	var i := z * grid_x + x
	var old := values[i]
	if old == v:
		return
	values[i] = v
	var c := (z / CHUNK_CELLS) * chunks_x + (x / CHUNK_CELLS)
	if old != EMPTY:
		_counts[c * SLOTS + decode(old)] -= 1
		_totals[c] -= 1
	if v != EMPTY:
		_counts[c * SLOTS + decode(v)] += 1
		_totals[c] += 1
	_set_bit(c, _totals[c] > 0)
	_dirty[chunk_key(x / CHUNK_CELLS, z / CHUNK_CELLS)] = true


func set_slot(x: int, z: int, slot: int) -> void:
	set_value(x, z, encode(slot))


func write_rect(x0: int, z0: int, w: int, d: int, bytes: PackedByteArray) -> void:
	var i := 0
	for z in range(z0, z0 + d):
		for x in range(x0, x0 + w):
			if i >= bytes.size():
				return
			set_value(x, z, bytes[i])
			i += 1


## Inclusive cell rect a brush of `radius_m` at world (cx_m, cz_m) covers,
## clipped to the grid. Empty size means the brush missed the map.
func circle_rect(cx_m: float, cz_m: float, radius_m: float) -> Rect2i:
	if grid_x < 1 or grid_z < 1:
		return Rect2i()
	var cell := HeightField.CELL_M
	var r_cells := int(ceil(maxf(radius_m, 0.0) / cell))
	var cx := int(floor(cx_m / cell))
	var cz := int(floor(cz_m / cell))
	var x0 := maxi(0, cx - r_cells)
	var z0 := maxi(0, cz - r_cells)
	var x1 := mini(grid_x - 1, cx + r_cells)
	var z1 := mini(grid_z - 1, cz + r_cells)
	if x1 < x0 or z1 < z0:
		return Rect2i()
	return Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)


## Paint one dab. `slot` < 0 erases. Returns the cell rect written.
func stamp_circle(cx_m: float, cz_m: float, radius_m: float, slot: int) -> Rect2i:
	var rect := circle_rect(cx_m, cz_m, radius_m)
	if not rect.has_area():
		return rect
	var cell := HeightField.CELL_M
	var r2 := maxf(radius_m, 0.0) * maxf(radius_m, 0.0)
	var value := encode(slot) if slot >= 0 else EMPTY
	for z in range(rect.position.y, rect.end.y):
		var wz := (float(z) + 0.5) * cell
		for x in range(rect.position.x, rect.end.x):
			var wx := (float(x) + 0.5) * cell
			var dx := wx - cx_m
			var dz := wz - cz_m
			if dx * dx + dz * dz > r2:
				continue
			set_value(x, z, value)
	return rect


func chunk_occupied(cx: int, cz: int) -> bool:
	if cx < 0 or cz < 0 or cx >= chunks_x or cz >= chunks_z:
		return false
	return _bit(cz * chunks_x + cx)


func chunk_count(cx: int, cz: int) -> int:
	if cx < 0 or cz < 0 or cx >= chunks_x or cz >= chunks_z:
		return 0
	return _totals[cz * chunks_x + cx]


## Bitfield of the slots present in a chunk, so generation runs only the
## species that were actually painted there.
func chunk_slot_bits(cx: int, cz: int) -> int:
	if cx < 0 or cz < 0 or cx >= chunks_x or cz >= chunks_z:
		return 0
	var base := (cz * chunks_x + cx) * SLOTS
	var bits := 0
	for s in SLOTS:
		if _counts[base + s] > 0:
			bits |= 1 << s
	return bits


func occupied_chunks() -> int:
	var n := 0
	for c in _totals.size():
		if _totals[c] > 0:
			n += 1
	return n


## One bit per chunk, row-major — the cull's fast path.
func occupancy_bits() -> PackedByteArray:
	return _bits.duplicate()


func mark_all_dirty() -> void:
	_dirty.clear()
	for cz in chunks_z:
		for cx in chunks_x:
			_dirty[chunk_key(cx, cz)] = true


func mark_chunk_dirty(cx: int, cz: int) -> void:
	if cx >= 0 and cz >= 0 and cx < chunks_x and cz < chunks_z:
		_dirty[chunk_key(cx, cz)] = true


func has_dirty() -> bool:
	return not _dirty.is_empty()


## Drain the chunks written since the last drain, row-major so a rebuild
## walks the map in a stable order (C7).
func take_dirty_chunks() -> PackedInt32Array:
	var keys: Array = _dirty.keys()
	_dirty.clear()
	var out := PackedInt32Array()
	keys.sort()
	for k in keys:
		out.append(int(k))
	return out


func _reset_chunk_state() -> void:
	var n := chunks_x * chunks_z
	_counts = PackedInt32Array()
	_counts.resize(n * SLOTS)
	_totals = PackedInt32Array()
	_totals.resize(n)
	_bits = PackedByteArray()
	_bits.resize((n + 7) / 8)
	_bits.fill(0)
	_dirty.clear()


func _bit(c: int) -> bool:
	if c < 0 or c >= _totals.size():
		return false
	return (_bits[c >> 3] & (1 << (c & 7))) != 0


func _set_bit(c: int, on: bool) -> void:
	if c < 0 or c >= _totals.size():
		return
	var i := c >> 3
	var m := 1 << (c & 7)
	if on:
		_bits[i] = _bits[i] | m
	else:
		_bits[i] = _bits[i] & ~m
