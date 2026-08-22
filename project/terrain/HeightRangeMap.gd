extends RefCounted
class_name HeightRangeMap
## Chunked min/max range map over the heightfield.
##
## One texel per BLOCK_CELLS×BLOCK_CELLS cell block, but each block reads
## (BLOCK_CELLS+1)² samples so neighbouring blocks overlap by one row and
## column. The overlap is what makes the bound sound: every triangle of the
## rendered surface lies inside the block that owns its lower-left cell.
##
## Kept as a min/max mip chain. Without it a query over a level-5 clipmap
## tile would touch 4096 blocks; with it, any rect costs at most a few
## dozen lookups (mip k texels span BLOCK_CELLS << k cells).
##
## Uses: reject blocks during heightfield raycasts, and give each clipmap ring
## its vertical extent — a flat XZ mesh displaced in the vertex shader has no
## mesh AABB worth culling against, so the range map supplies one.

const BLOCK_CELLS := 16
## Cell rect a single query is allowed to expand to before it drops a mip.
const QUERY_TEXELS := 4

var grid_x: int = 0
var grid_z: int = 0
var blocks_x: int = 0
var blocks_z: int = 0
## RG float image of mip 0: R = block minimum (m), G = block maximum (m).
var image: Image
var texture: ImageTexture

var _mins: Array[PackedFloat32Array] = []
var _maxs: Array[PackedFloat32Array] = []
var _dims: Array[Vector2i] = []
var _image_dirty: bool = false


func valid() -> bool:
	return blocks_x > 0 and blocks_z > 0


func rebuild(field: HeightField) -> void:
	_mins.clear()
	_maxs.clear()
	_dims.clear()
	image = null
	texture = null
	grid_x = 0
	grid_z = 0
	blocks_x = 0
	blocks_z = 0
	if field == null or field.grid_x < 2 or field.grid_z < 2:
		return
	grid_x = field.grid_x
	grid_z = field.grid_z
	blocks_x = maxi(1, int(ceil(float(grid_x - 1) / float(BLOCK_CELLS))))
	blocks_z = maxi(1, int(ceil(float(grid_z - 1) / float(BLOCK_CELLS))))
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(blocks_x * blocks_z)
	hi.resize(blocks_x * blocks_z)
	_mins.append(lo)
	_maxs.append(hi)
	_dims.append(Vector2i(blocks_x, blocks_z))
	_build_mip_levels()
	for bz in blocks_z:
		for bx in blocks_x:
			_scan_block(field, bx, bz)
	_reduce_rect(0, 0, blocks_x - 1, blocks_z - 1)
	_image_dirty = true


## Recompute only the blocks that intersect an inclusive cell rect.
func update_rect(field: HeightField, x0: int, z0: int, x1: int, z1: int) -> void:
	if not valid() or field == null or field.grid_x != grid_x or field.grid_z != grid_z:
		rebuild(field)
		return
	# A cell on a block boundary belongs to two blocks; step one block back
	# rather than special-casing the modulo.
	var b0x := clampi(int(floor(float(mini(x0, x1)) / float(BLOCK_CELLS))) - 1, 0, blocks_x - 1)
	var b0z := clampi(int(floor(float(mini(z0, z1)) / float(BLOCK_CELLS))) - 1, 0, blocks_z - 1)
	var b1x := clampi(int(floor(float(maxi(x0, x1)) / float(BLOCK_CELLS))), 0, blocks_x - 1)
	var b1z := clampi(int(floor(float(maxi(z0, z1)) / float(BLOCK_CELLS))), 0, blocks_z - 1)
	for bz in range(b0z, b1z + 1):
		for bx in range(b0x, b1x + 1):
			_scan_block(field, bx, bz)
	_reduce_rect(b0x, b0z, b1x, b1z)
	_image_dirty = true


## Inclusive min/max (metres) over a cell rect, as Vector2(min, max).
## Returns Vector2(0, 0) when the map has no range map yet.
func range_over(x0: int, z0: int, x1: int, z1: int) -> Vector2:
	if not valid():
		return Vector2.ZERO
	var ax := clampi(mini(x0, x1), 0, grid_x - 1)
	var az := clampi(mini(z0, z1), 0, grid_z - 1)
	var bx := clampi(maxi(x0, x1), 0, grid_x - 1)
	var bz := clampi(maxi(z0, z1), 0, grid_z - 1)
	var i0 := ax / BLOCK_CELLS
	var j0 := az / BLOCK_CELLS
	var i1 := mini(bx / BLOCK_CELLS, blocks_x - 1)
	var j1 := mini(bz / BLOCK_CELLS, blocks_z - 1)
	var k := 0
	while k + 1 < _dims.size() \
			and (i1 - i0 + 1 > QUERY_TEXELS or j1 - j0 + 1 > QUERY_TEXELS):
		i0 >>= 1
		j0 >>= 1
		i1 >>= 1
		j1 >>= 1
		k += 1
	var dim: Vector2i = _dims[k]
	i1 = mini(i1, dim.x - 1)
	j1 = mini(j1, dim.y - 1)
	var lo: PackedFloat32Array = _mins[k]
	var hi: PackedFloat32Array = _maxs[k]
	var out_lo := INF
	var out_hi := -INF
	for j in range(j0, j1 + 1):
		var row := j * dim.x
		for i in range(i0, i1 + 1):
			out_lo = minf(out_lo, lo[row + i])
			out_hi = maxf(out_hi, hi[row + i])
	if out_hi < out_lo:
		return Vector2.ZERO
	return Vector2(out_lo, out_hi)


func block_range(bx: int, bz: int) -> Vector2:
	if not valid() or bx < 0 or bz < 0 or bx >= blocks_x or bz >= blocks_z:
		return Vector2.ZERO
	var i := bz * blocks_x + bx
	return Vector2(_mins[0][i], _maxs[0][i])


## Min/max over the whole map — the coarsest mip is a single texel.
func map_range() -> Vector2:
	if not valid():
		return Vector2.ZERO
	var k := _dims.size() - 1
	var lo := INF
	var hi := -INF
	for i in _mins[k].size():
		lo = minf(lo, _mins[k][i])
		hi = maxf(hi, _maxs[k][i])
	if hi < lo:
		return Vector2.ZERO
	return Vector2(lo, hi)


## RG-float texture of mip 0, built lazily — nothing samples it every frame,
## so the upload is deferred until a consumer actually asks.
func gpu_texture() -> ImageTexture:
	if not valid():
		return null
	if texture != null and not _image_dirty:
		return texture
	var buf := PackedByteArray()
	buf.resize(blocks_x * blocks_z * 8)
	var lo: PackedFloat32Array = _mins[0]
	var hi: PackedFloat32Array = _maxs[0]
	for i in lo.size():
		buf.encode_float(i * 8, lo[i])
		buf.encode_float(i * 8 + 4, hi[i])
	image = Image.create_from_data(blocks_x, blocks_z, false, Image.FORMAT_RGF, buf)
	if texture == null or texture.get_width() != blocks_x or texture.get_height() != blocks_z:
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	_image_dirty = false
	return texture


func _build_mip_levels() -> void:
	var w := blocks_x
	var h := blocks_z
	while w > 1 or h > 1:
		w = maxi(1, (w + 1) >> 1)
		h = maxi(1, (h + 1) >> 1)
		var lo := PackedFloat32Array()
		var hi := PackedFloat32Array()
		lo.resize(w * h)
		hi.resize(w * h)
		_mins.append(lo)
		_maxs.append(hi)
		_dims.append(Vector2i(w, h))


func _scan_block(field: HeightField, bx: int, bz: int) -> void:
	var x0 := bx * BLOCK_CELLS
	var z0 := bz * BLOCK_CELLS
	var x1 := mini(x0 + BLOCK_CELLS, grid_x - 1)
	var z1 := mini(z0 + BLOCK_CELLS, grid_z - 1)
	var heights := field.heights
	var lo := 0x7FFFFFFF
	var hi := -0x7FFFFFFF
	for z in range(z0, z1 + 1):
		var row := z * grid_x
		for x in range(x0, x1 + 1):
			var v := heights[row + x]
			if v < lo:
				lo = v
			if v > hi:
				hi = v
	var i := bz * blocks_x + bx
	_mins[0][i] = float(lo) * HeightField.HEIGHT_SCALE
	_maxs[0][i] = float(hi) * HeightField.HEIGHT_SCALE


## Push a changed mip-0 rect up the chain. Each mip texel is the min/max of
## the 2×2 below it, so the affected rect simply halves each step.
func _reduce_rect(x0: int, z0: int, x1: int, z1: int) -> void:
	for k in range(1, _dims.size()):
		x0 >>= 1
		z0 >>= 1
		x1 >>= 1
		z1 >>= 1
		var dim: Vector2i = _dims[k]
		var src: Vector2i = _dims[k - 1]
		var lo: PackedFloat32Array = _mins[k]
		var hi: PackedFloat32Array = _maxs[k]
		var slo: PackedFloat32Array = _mins[k - 1]
		var shi: PackedFloat32Array = _maxs[k - 1]
		var ex := mini(x1, dim.x - 1)
		var ez := mini(z1, dim.y - 1)
		for j in range(maxi(z0, 0), ez + 1):
			for i in range(maxi(x0, 0), ex + 1):
				var a := INF
				var b := -INF
				for dz in 2:
					var sz := (j << 1) + dz
					if sz >= src.y:
						continue
					var srow := sz * src.x
					for dx in 2:
						var sx := (i << 1) + dx
						if sx >= src.x:
							continue
						a = minf(a, slo[srow + sx])
						b = maxf(b, shi[srow + sx])
				if b < a:
					a = 0.0
					b = 0.0
				lo[j * dim.x + i] = a
				hi[j * dim.x + i] = b
