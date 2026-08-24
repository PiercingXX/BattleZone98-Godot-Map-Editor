extends RefCounted
class_name BzHg2
## Port of backend/bzmap/formats/hg2.py — HeightMap + module functions.
##
## On-disk samples are zone-major (F1 §4). In-memory `HeightMap.data` is world
## row-major, index `z * grid_x + x`, same as the Python 2-D array `[z, x]`.
##
## Axis order (settled 2026-08-24 against 57 stock maps): disk sample 0 of the
## first zone is world x=0, z=0, and the sample index walks +X then +Z inside a
## zone. There is no mirror. Read and write are plain zone interleave.
##
## The earlier "disk X runs east->west" note was wrong. It was inferred from an
## in-game paint test whose real fault was the .mat tile-orientation table
## (BzMat / terrain.gdshader), which drew half of every map's cap and corner
## tiles turned 180 degrees. Mirroring X moved the whole heightfield out from
## under the BZN object positions and the minimap instead.
##
## Proof, if it is ever doubted again: BZN `pos` y is the height the object was
## placed at, so |y - sample_m(x, z)| is near zero on the right axis order.
## Over 57 stock maps / 1674 objects, plain zone-major gives a median error of
## 0.54 m and X-mirrored gives 7.28 m; per map, 51 of 55 discriminating maps
## pick plain, none pick mirrored.
##
## Python-vs-spec (F1) discrepancies — Python wins:
## - Header bytes 8–11 are two uint16s `unknownA`/`unknownB`, not F1's uint32
##   `map_version`. Typical stock files have unknownA=10, unknownB=0 (= 10).
## - `read` rejects `depth != 8` (zone size must be 256). F1 says the version
##   fields are not validated by any known reader.
## - `data` / `sample_m` / `slope` use the raw uint16 word, flag bits included.
##   F1 §6's masked `terrain.r16` interchange is the session layer, not this
##   module. The module docstring's "12-bit 0–4095" claim is also wrong; the
##   code never masks, so 13-bit heights and upper flag bits survive.

const ZONE_SIZE: int = 256
const GRID_M: float = 5.0
const HEIGHT_SCALE: float = 0.1
const ZONE_M: float = 1280.0


static func _fail(message: String, hint: String = "") -> Dictionary:
	return {
		"ok": false,
		"error": {"code": "value_error", "message": message, "hint": hint},
	}


static func _ok_heightmap(heightmap: HeightMap) -> Dictionary:
	return {"ok": true, "heightmap": heightmap}


class HeightMap:
	extends RefCounted

	var version: int = 1
	var depth: int = 8
	var zonesX: int = 1
	var zonesZ: int = 1
	var unknownA: int = 10
	var unknownB: int = 0
	## Row-major raw uint16 words (held in PackedInt32Array). Flag bits kept.
	var data: PackedInt32Array = PackedInt32Array()

	func _init(
		p_zonesX: int,
		p_zonesZ: int,
		p_data: PackedInt32Array,
		p_version: int = 1,
		p_depth: int = 8,
		p_unknownA: int = 10,
		p_unknownB: int = 0
	) -> void:
		version = p_version
		depth = p_depth
		zonesX = int(p_zonesX)
		zonesZ = int(p_zonesZ)
		unknownA = int(p_unknownA)
		unknownB = int(p_unknownB)
		data = p_data
		var expected: int = zonesZ * BzHg2.ZONE_SIZE * zonesX * BzHg2.ZONE_SIZE
		if data.size() != expected:
			push_error(
				"data shape %d does not match header %dx%d zones (expected %d)"
				% [data.size(), zonesX, zonesZ, expected]
			)

	var grid_x: int:
		get:
			return zonesX * BzHg2.ZONE_SIZE

	var grid_z: int:
		get:
			return zonesZ * BzHg2.ZONE_SIZE

	var width_m: float:
		get:
			return float(zonesX) * BzHg2.ZONE_M

	var depth_m: float:
		get:
			return float(zonesZ) * BzHg2.ZONE_M

	static func read(path: String) -> Dictionary:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return BzHg2._fail(
				"%s: cannot open (%s)" % [path, error_string(FileAccess.get_open_error())]
			)
		var buf: PackedByteArray = file.get_buffer(file.get_length())
		file.close()
		if buf.size() < 12:
			return BzHg2._fail("%s: truncated header (%d bytes)" % [path, buf.size()])
		var p_version: int = buf.decode_u16(0)
		var p_depth: int = buf.decode_u16(2)
		var p_zones_x: int = buf.decode_u16(4)
		var p_zones_z: int = buf.decode_u16(6)
		var p_unknown_a: int = buf.decode_u16(8)
		var p_unknown_b: int = buf.decode_u16(10)
		var zone_size: int = 1 << p_depth
		if zone_size != BzHg2.ZONE_SIZE:
			return BzHg2._fail(
				"%s: unsupported zone size %d (depth=%d); only %d is supported"
				% [path, zone_size, p_depth, BzHg2.ZONE_SIZE]
			)
		var raw_bytes: int = buf.size() - 12
		var sample_count: int = raw_bytes / 2
		var expected: int = p_zones_x * p_zones_z * zone_size * zone_size
		if raw_bytes < 0 or raw_bytes % 2 != 0 or sample_count != expected:
			return BzHg2._fail(
				"%s: expected %d height samples, got %d" % [path, expected, sample_count]
			)
		var gx: int = p_zones_x * zone_size
		var gz: int = p_zones_z * zone_size
		var words := PackedInt32Array()
		words.resize(gx * gz)
		var off: int = 12
		for zy in p_zones_z:
			for zx in p_zones_x:
				for sub_z in zone_size:
					var world_z: int = zy * zone_size + sub_z
					var row: int = world_z * gx
					var col: int = zx * zone_size
					for sub_x in zone_size:
						words[row + col + sub_x] = buf.decode_u16(off)
						off += 2
		return BzHg2._ok_heightmap(
			HeightMap.new(
				p_zones_x, p_zones_z, words, p_version, p_depth, p_unknown_a, p_unknown_b
			)
		)

	func write(path: String) -> Dictionary:
		var zone_size: int = 1 << depth
		var gx: int = grid_x
		var gz: int = grid_z
		var out := PackedByteArray()
		out.resize(12 + gx * gz * 2)
		out.encode_u16(0, version)
		out.encode_u16(2, depth)
		out.encode_u16(4, zonesX)
		out.encode_u16(6, zonesZ)
		out.encode_u16(8, unknownA)
		out.encode_u16(10, unknownB)
		var off: int = 12
		for zy in zonesZ:
			for zx in zonesX:
				for sub_z in zone_size:
					var world_z: int = zy * zone_size + sub_z
					var row: int = world_z * gx
					var col: int = zx * zone_size
					for sub_x in zone_size:
						out.encode_u16(off, data[row + col + sub_x] & 0xFFFF)
						off += 2
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return BzHg2._fail(
				"%s: cannot write (%s)" % [path, error_string(FileAccess.get_open_error())]
			)
		file.store_buffer(out)
		file.close()
		return {"ok": true}


static func read_hg2(path: String) -> Dictionary:
	return HeightMap.read(path)


static func write_hg2(path: String, heightmap: HeightMap) -> Dictionary:
	return heightmap.write(path)


static func _cell(raw: PackedInt32Array, gx: int, gz: int, x: int, z: int) -> int:
	x = maxi(0, mini(gx - 1, x))
	z = maxi(0, mini(gz - 1, z))
	return int(raw[z * gx + x])


static func sample_m(heightmap: HeightMap, x: float, z: float) -> float:
	var raw: PackedInt32Array = heightmap.data
	var gx: int = heightmap.grid_x
	var gz: int = heightmap.grid_z
	var fgx: float = x / GRID_M
	var fgz: float = z / GRID_M
	var x0: int = int(floor(fgx))
	var z0: int = int(floor(fgz))
	var fx: float = fgx - float(x0)
	var fz: float = fgz - float(z0)
	x0 = maxi(0, mini(gx - 2, x0))
	z0 = maxi(0, mini(gz - 2, z0))
	var h00: float = float(_cell(raw, gx, gz, x0, z0))
	var h10: float = float(_cell(raw, gx, gz, x0 + 1, z0))
	var h01: float = float(_cell(raw, gx, gz, x0, z0 + 1))
	var h11: float = float(_cell(raw, gx, gz, x0 + 1, z0 + 1))
	var top: float = h00 + fx * (h10 - h00)
	var bottom: float = h01 + fx * (h11 - h01)
	return (top + fz * (bottom - top)) * HEIGHT_SCALE


static func slope(heightmap: HeightMap) -> PackedFloat64Array:
	## numpy.gradient central differences over GRID_M, then hypot(dx, dz).
	var gx: int = heightmap.grid_x
	var gz: int = heightmap.grid_z
	var n: int = gx * gz
	var h := PackedFloat64Array()
	h.resize(n)
	for i in n:
		h[i] = float(heightmap.data[i]) * HEIGHT_SCALE
	var d_ax0 := PackedFloat64Array()
	var d_ax1 := PackedFloat64Array()
	d_ax0.resize(n)
	d_ax1.resize(n)
	if gz == 1:
		for x in gx:
			d_ax0[x] = 0.0
	else:
		for x in gx:
			d_ax0[x] = (h[gx + x] - h[x]) / GRID_M
			d_ax0[(gz - 1) * gx + x] = (
				h[(gz - 1) * gx + x] - h[(gz - 2) * gx + x]
			) / GRID_M
		for z in range(1, gz - 1):
			var row: int = z * gx
			for x in gx:
				d_ax0[row + x] = (h[(z + 1) * gx + x] - h[(z - 1) * gx + x]) / (2.0 * GRID_M)
	if gx == 1:
		for z in gz:
			d_ax1[z] = 0.0
	else:
		for z in gz:
			var row: int = z * gx
			d_ax1[row] = (h[row + 1] - h[row]) / GRID_M
			d_ax1[row + gx - 1] = (h[row + gx - 1] - h[row + gx - 2]) / GRID_M
			for x in range(1, gx - 1):
				d_ax1[row + x] = (h[row + x + 1] - h[row + x - 1]) / (2.0 * GRID_M)
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		out[i] = sqrt(d_ax1[i] * d_ax1[i] + d_ax0[i] * d_ax0[i])
	return out


static func buildable_mask(heightmap: HeightMap, max_slope: float = 0.25) -> PackedByteArray:
	var s: PackedFloat64Array = slope(heightmap)
	var out := PackedByteArray()
	out.resize(s.size())
	for i in s.size():
		out[i] = 1 if s[i] <= max_slope else 0
	return out
