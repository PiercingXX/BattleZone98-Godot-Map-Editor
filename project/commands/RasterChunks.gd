extends RefCounted
class_name RasterChunks
## 64x64 undo tiling over a raster grid (heights, material words, mask bytes).
##
## A stroke used to duplicate the whole grid on mouse-down — 4 MB per click on
## a 1024^2 map — and diff it against the stroke's bounding rect at commit, so
## a diagonal drag paid for the rect it spanned rather than the cells it wrote.
## Here a chunk's before-image is copied the first time a stamp writes into it,
## and commit emits one region per touched chunk, clipped to the touched
## bounds. Cost follows edited area.
##
## Values are copied verbatim: heights are [flags:3][height:13] words and
## inherited cells can sit outside the editor's raw 1..4095 write range, so
## nothing here masks, clamps or re-encodes.
##
## Grid-type agnostic. slice()/append_array() preserve the caller's packed
## type, so the same store serves PackedInt32Array and PackedByteArray grids.

const SIZE := 64

var grid_x: int = 0
var grid_z: int = 0

## chunk key -> dense before-image of that chunk, row-major, clipped to grid.
var _chunks: Dictionary = {}
## chunk key -> the part of that chunk the stroke has touched, in grid cells.
var _rects: Dictionary = {}


## One before/after region record. The single shape every raster command reads.
static func region(x0: int, z0: int, w: int, d: int, before: Variant, after: Variant) -> Dictionary:
	return {"x": x0, "z": z0, "w": w, "d": d, "before": before, "after": after}


## Arm the store for a stroke. Zero dimensions leave it inert (no capture).
func begin(p_grid_x: int, p_grid_z: int) -> void:
	grid_x = maxi(p_grid_x, 0)
	grid_z = maxi(p_grid_z, 0)
	_chunks.clear()
	_rects.clear()


## Capture every chunk the rect [x0..x1] x [z0..z1] overlaps. Call before the
## cells are written; chunks already held keep their first (pre-stroke) copy.
func touch(src: Variant, x0: int, z0: int, x1: int, z1: int) -> void:
	if grid_x < 1 or grid_z < 1 or src.size() != grid_x * grid_z:
		return
	x0 = maxi(x0, 0)
	z0 = maxi(z0, 0)
	x1 = mini(x1, grid_x - 1)
	z1 = mini(z1, grid_z - 1)
	if x1 < x0 or z1 < z0:
		return
	for cz in range(z0 / SIZE, z1 / SIZE + 1):
		for cx in range(x0 / SIZE, x1 / SIZE + 1):
			var k := (cz << 16) | cx
			if not _chunks.has(k):
				_chunks[k] = _copy_chunk(src, cx, cz)
			# Per-chunk touched bounds, so commit emits the cells the stroke
			# reached inside this chunk rather than the whole chunk.
			var hx0 := maxi(x0, cx * SIZE)
			var hz0 := maxi(z0, cz * SIZE)
			var hx1 := mini(x1, cx * SIZE + SIZE - 1)
			var hz1 := mini(z1, cz * SIZE + SIZE - 1)
			var hit := Rect2i(hx0, hz0, hx1 - hx0 + 1, hz1 - hz0 + 1)
			if _rects.has(k):
				var prev: Rect2i = _rects[k]
				hit = hit.merge(prev)
			_rects[k] = hit


## Widen an already-touched rect by `pad` cells on all four sides, capturing
## only the border ring. An area op that reads its neighbours writes a rect one
## cell larger than the stamp; the interior is already held.
func touch_border(src: Variant, x0: int, z0: int, x1: int, z1: int, pad: int) -> void:
	if pad < 1:
		return
	touch(src, x0 - pad, z0 - pad, x1 + pad, z0 - 1)
	touch(src, x0 - pad, z1 + 1, x1 + pad, z1 + pad)
	touch(src, x0 - pad, z0, x0 - 1, z1)
	touch(src, x1 + 1, z0, x1 + pad, z1)


## Pre-stroke value at (x, z): the captured chunk if the stroke already wrote
## there, else live — an untouched cell still holds its before value. Lets a
## clone kernel sample the pre-stroke grid without a full-grid snapshot.
func value_at(src: Variant, x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= grid_x or z >= grid_z:
		return 0
	var cx := x / SIZE
	var cz := z / SIZE
	var k := (cz << 16) | cx
	if not _chunks.has(k):
		return int(src[z * grid_x + x])
	var buf: Variant = _chunks[k]
	var cw := mini(SIZE, grid_x - cx * SIZE)
	return int(buf[(z - cz * SIZE) * cw + (x - cx * SIZE)])


## Commit: one region per touched chunk, clipped to the touched bounds, with
## unchanged chunks dropped. Empty when the stroke wrote nothing.
func regions(live: Variant) -> Array:
	var out: Array = []
	if grid_x < 1 or grid_z < 1 or _chunks.is_empty():
		return out
	if live.size() != grid_x * grid_z:
		return out
	for k_v in _chunks.keys():
		var k := int(k_v)
		var cx := k & 0xFFFF
		var cz := k >> 16
		var cw := mini(SIZE, grid_x - cx * SIZE)
		var hit: Rect2i = _rects[k]
		var bx0 := hit.position.x
		var bz0 := hit.position.y
		var bx1 := hit.end.x - 1
		var bz1 := hit.end.y - 1
		if bx1 < bx0 or bz1 < bz0:
			continue
		var w := bx1 - bx0 + 1
		var buf: Variant = _chunks[k]
		var before: Variant = live.slice(0, 0)
		var after: Variant = live.slice(0, 0)
		for z in range(bz0, bz1 + 1):
			var brow := (z - cz * SIZE) * cw + (bx0 - cx * SIZE)
			before.append_array(buf.slice(brow, brow + w))
			var lrow := z * grid_x + bx0
			after.append_array(live.slice(lrow, lrow + w))
		if before == after:
			continue
		out.append(region(bx0, bz0, w, bz1 - bz0 + 1, before, after))
	return out


func _copy_chunk(src: Variant, cx: int, cz: int) -> Variant:
	var x0 := cx * SIZE
	var z0 := cz * SIZE
	var w := mini(SIZE, grid_x - x0)
	var d := mini(SIZE, grid_z - z0)
	var out: Variant = src.slice(0, 0)
	for z in range(z0, z0 + d):
		var row := z * grid_x + x0
		out.append_array(src.slice(row, row + w))
	return out
