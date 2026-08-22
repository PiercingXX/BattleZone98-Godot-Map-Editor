extends RefCounted
## BzMat: parse, zone interleave, encode/decode, auto-paint, byte-identical RT.


func run(t) -> void:
	var tmp: String = _tmp_dir()
	_test_encode_decode(t)
	_test_march_square(t)
	_test_autotile_neighbors(t)
	_test_factor_pair(t)
	_test_parse_one_zone(t, tmp)
	_test_parse_two_zone(t, tmp)
	_test_roundtrip_bytes(t, tmp)
	_test_write_then_parse(t, tmp)
	_test_flat_non_zone(t, tmp)
	_test_auto_paint(t)
	_test_expected_shape(t, tmp)
	_test_errors(t, tmp)


func _test_expected_shape(t, tmp: String) -> void:
	## A 2x3-zone map: the factor-pair guess transposes it, the .hg2 shape does not.
	var cols: int = 128  # 2 zones of X
	var rows: int = 192  # 3 zones of Z
	var words := PackedInt32Array()
	words.resize(rows * cols)
	words[5 * cols + 3] = 0xBEEF
	var g := BzMat.MaterialGrid.new(words, rows, cols)
	var path: String = tmp.path_join("two_by_three.mat")
	t.ok(bool(g.write(path).get("ok")))
	var guessed: Dictionary = BzMat.read_mat(path)
	var gg: BzMat.MaterialGrid = guessed.get("grid") as BzMat.MaterialGrid
	t.eq(gg.grid_x, 192, "no hint: the guess transposes a 2x3-zone map")
	var told: Dictionary = BzMat.read_mat(path, rows, cols)
	var tg: BzMat.MaterialGrid = told.get("grid") as BzMat.MaterialGrid
	t.eq(tg.grid_x, cols, "told the .hg2 shape, X is 2 zones")
	t.eq(tg.grid_z, rows, "told the .hg2 shape, Z is 3 zones")
	t.eq(tg.data[5 * cols + 3], 0xBEEF, "round-trips in place at the right shape")
	var wrong: Dictionary = BzMat.read_mat(path, 64, 64)
	t.eq(wrong.get("ok"), false, "a .mat that does not match the .hg2 is refused")
	t.ok(str(wrong.get("error", {}).get("message", "")).contains("heightmap wants"))


func _test_encode_decode(t) -> void:
	t.eq(BzMat.encode_entry(2, 3, 1, 0, 2, 1), 0x23A1)
	t.eq(BzMat.encode_entry(4, 4), 0x4400)
	t.eq(BzMat.encode_entry(5, 1, 0, 1, 3, 2), 0x5172)
	t.eq(BzMat.encode_entry(0xFF, 0xFF, 3, 3, 7, 7), 0xFFF3, "fields masked")
	var decoded: Dictionary = BzMat.decode_entry(0x23A1)
	t.eq(int(decoded["mat_a"]), 2)
	t.eq(int(decoded["mat_b"]), 3)
	t.eq(int(decoded["cap"]), 1)
	t.eq(int(decoded["flip"]), 0)
	t.eq(int(decoded["rot"]), 2)
	t.eq(int(decoded["variant"]), 1)
	t.eq(BzMat.kind_of_entry(0x4400), "solid")
	t.eq(BzMat.kind_of_entry(BzMat.encode_entry(5, 1, 0, 1, 3, 0)), "cap")
	t.eq(BzMat.kind_of_entry(0x23A1), "diag")
	var words := PackedInt32Array()
	words.resize(64 * 64)
	words[0] = 0x23A1
	words[10 * 64 + 20] = 0x5172
	var g := BzMat.MaterialGrid.new(words, 64, 64)
	t.eq(g.grid_x, 64)
	t.eq(g.grid_z, 64)
	t.near(g.width_m, 1280.0)
	t.near(g.depth_m, 1280.0)
	var dec: PackedInt32Array = g.decode()
	t.eq(dec[0], 2)
	t.eq(dec[1], 3)
	t.eq(dec[2], 1)
	t.eq(dec[3], 0)
	t.eq(dec[4], 2)
	t.eq(dec[5], 1)
	var base: int = (10 * 64 + 20) * 6
	t.eq(dec[base], 5)
	t.eq(dec[base + 1], 1)
	t.eq(dec[base + 2], 0)
	t.eq(dec[base + 3], 1)
	t.eq(dec[base + 4], 3)
	t.eq(dec[base + 5], 2)


func _test_march_square(t) -> void:
	var cases := [
		[[3, 3, 3, 3], 0x3300],
		[[2, 1, 1, 1], 0x1200],
		[[1, 2, 1, 1], 0x1230],
		[[1, 1, 2, 1], 0x1220],
		[[1, 1, 1, 2], 0x1210],
		[[2, 2, 1, 1], 0x1240],
		[[1, 2, 2, 1], 0x1270],
		[[1, 1, 2, 2], 0x1260],
		[[2, 1, 1, 2], 0x1250],
		[[2, 1, 2, 1], 0x1280],
		[[1, 2, 1, 2], 0x12C0],
		[[1, 2, 2, 2], 0x2100],
		[[2, 2, 2, 2], 0x2200],
	]
	for c in cases:
		var colors := PackedInt32Array(c[0])
		t.eq(BzMat._march_square(colors), int(c[1]), "march %s" % str(c[0]))


func _test_autotile_neighbors(t) -> void:
	t.eq(BzMat.autotile_neighbors(5, 5, 5, 5, 5), BzMat.encode_entry(5, 5), "interior is solid")
	t.eq(BzMat.autotile_neighbors(5, 0, 0, 0, 0), BzMat.encode_entry(5, 5), "island is solid")
	var edge: int = BzMat.autotile_neighbors(5, 0, 5, 5, 5)
	t.eq((edge >> 12) & 0xF, 5, "edge keeps painted base")
	t.eq((edge >> 8) & 0xF, 0, "edge transitions to the outsider")
	t.eq((edge >> 7) & 1, 0, "straight run is a cap")
	t.eq((edge >> 6) & 1, 1, "cap uses the edge (flip) packing")
	t.eq(BzMat.encode_diag(5, 0, 0), BzMat.encode_entry(5, 0, 1, 1, 2), "NW/left is identity 14")
	t.eq(BzMat.encode_diag(5, 0, 1), BzMat.encode_entry(5, 0, 1, 1, 1), "NE is +90")
	var corner: int = BzMat.autotile_neighbors(5, 0, 5, 5, 0)
	t.eq((corner >> 12) & 0xF, 5, "corner keeps painted base")
	t.eq((corner >> 8) & 0xF, 0, "corner transitions to the outsider")
	t.eq((corner >> 7) & 1, 1, "outer corner is a diagonal")
	t.eq(corner, BzMat.encode_diag(5, 0, 0), "E+S same → left-facing / NW identity")
	var inner: int = BzMat.autotile_neighbors(0, 5, 0, 0, 5)
	t.eq((inner >> 12) & 0xF, 0, "inner corner stays the background")
	t.eq((inner >> 8) & 0xF, 5, "inner corner meets the painted pair")
	t.eq((inner >> 7) & 1, 1, "inner corner is a diagonal")
	t.eq(inner, BzMat.encode_diag(0, 5, 0), "inner uses the same left-facing rotation")
	# One-vertex march without promotion is a cap; autotile_quad upgrades it.
	var raw: int = BzMat._march_square(PackedInt32Array([2, 1, 1, 1]))
	t.eq((raw >> 7) & 1, 0, "march 1-vertex is a cap")
	var promoted: int = BzMat.autotile_quad(PackedInt32Array([2, 1, 1, 1]))
	t.eq((promoted >> 7) & 1, 1, "autotile_quad promotes the corner")


func _test_factor_pair(t) -> void:
	t.eq(BzMat._closest_factor_pair(4096), Vector2i(64, 64))
	t.eq(BzMat._closest_factor_pair(16384), Vector2i(128, 128))
	t.eq(BzMat._closest_factor_pair(49152), Vector2i(192, 256), "4x3 zones")
	t.eq(BzMat._closest_factor_pair(24576), Vector2i(128, 192), "2x3 vs 3x2")
	t.eq(BzMat._closest_factor_pair(100), Vector2i(10, 10))
	t.eq(BzMat._closest_factor_pair(12), Vector2i(3, 4))
	t.eq(BzMat._closest_factor_pair(1), Vector2i(1, 1))


func _test_parse_one_zone(t, tmp: String) -> void:
	var buf: PackedByteArray = _build_one_zone_mat()
	t.eq(_sha256(buf), "b6dfb650095e3905c1567d83997c4cda318407dfa0d18dd7df8b09cf3acbda66",
		"1x1 MAT matches Python sha256")
	var path: String = tmp.path_join("one_zone.mat")
	t.ok(_write_bytes(path, buf))
	var result: Dictionary = BzMat.read_mat(path)
	t.ok(bool(result.get("ok")), "read 1x1")
	var g: BzMat.MaterialGrid = result.get("grid") as BzMat.MaterialGrid
	t.eq(g.grid_x, 64)
	t.eq(g.grid_z, 64)
	# Disk X runs east→west, so disk tx lands at world 63 - tx (F2 §3.1).
	t.eq(g.data[63], 0x23A1, "disk (0,0) is world (63,0)")
	t.eq(g.data[63 * 64 + 0], 0x4400, "disk (63,63) is world (0,63)")
	t.eq(g.data[10 * 64 + 43], 0x5172, "disk (20,10) is world (43,10)")
	t.eq(g.data[0], 0, "world (0,0) is untouched")


func _test_parse_two_zone(t, tmp: String) -> void:
	var buf: PackedByteArray = _build_two_zone_mat()
	t.eq(_sha256(buf), "1bdbf3114290fc43f4aefcd61d4308a0910b2d2f1099e03fd10ff8eabc4353cd",
		"2x2 MAT matches Python sha256")
	var path: String = tmp.path_join("two_zone.mat")
	t.ok(_write_bytes(path, buf))
	var result: Dictionary = BzMat.MaterialGrid.read(path)
	t.ok(bool(result.get("ok")), "read 2x2")
	var g: BzMat.MaterialGrid = result.get("grid") as BzMat.MaterialGrid
	t.eq(g.grid_x, 128)
	t.eq(g.grid_z, 128)
	# The X mirror is global across zones: disk tx → world 127 - tx.
	t.eq(g.data[127], 0x1111, "disk (0,0) is world (127,0)")
	t.eq(g.data[10 * 128 + 57], 0xABCD, "disk (70,10) is world (57,10)")
	t.eq(g.data[70 * 128 + 117], 0x2222, "disk (10,70) is world (117,70)")
	t.eq(g.data[70 * 128 + 57], 0x3333, "disk (70,70) is world (57,70)")
	t.eq(g.data[10 * 128 + 58], 0, "neighbour untouched")
	t.eq(buf.decode_u16(1350 * 2), 0, "row-major slot for (70,10) is empty")
	t.eq(buf.decode_u16(4742 * 2), 0xABCD, "zone-major slot holds (70,10)")


func _test_roundtrip_bytes(t, tmp: String) -> void:
	for pair in [
		["one_zone.mat", _build_one_zone_mat()],
		["two_zone.mat", _build_two_zone_mat()],
	]:
		var name: String = pair[0]
		var original: PackedByteArray = pair[1]
		var src: String = tmp.path_join("rt_src_" + name)
		var dst: String = tmp.path_join("rt_dst_" + name)
		_write_bytes(src, original)
		var result: Dictionary = BzMat.read_mat(src)
		t.ok(bool(result.get("ok")), "rt read " + name)
		var g: BzMat.MaterialGrid = result.get("grid") as BzMat.MaterialGrid
		var wr: Dictionary = BzMat.write_mat(dst, g)
		t.ok(bool(wr.get("ok")), "rt write " + name)
		var back: PackedByteArray = FileAccess.get_file_as_bytes(dst)
		t.ok(back == original, "byte-identical round-trip " + name)


func _test_write_then_parse(t, tmp: String) -> void:
	var words := PackedInt32Array()
	words.resize(128 * 128)
	words.fill(0x4400)
	words[10 * 128 + 70] = 0xABCD
	var g := BzMat.MaterialGrid.new(words, 128, 128)
	var path: String = tmp.path_join("authored.mat")
	t.ok(bool(g.write(path).get("ok")))
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
	t.eq(raw.decode_u16(_disk_index(57, 10, 2, 64) * 2), 0xABCD,
		"world (70,10) writes to disk (57,10)")
	var rd: Dictionary = BzMat.read_mat(path)
	var back: BzMat.MaterialGrid = rd.get("grid") as BzMat.MaterialGrid
	t.eq(back.grid_x, 128)
	t.eq(back.grid_z, 128)
	t.eq(back.data[10 * 128 + 70], 0xABCD, "write→read is the identity in world space")
	t.eq(back.data[0], 0x4400)


func _test_flat_non_zone(t, tmp: String) -> void:
	var words := PackedInt32Array()
	words.resize(100)
	for i in 100:
		words[i] = i + 1
	var g := BzMat.MaterialGrid.new(words, 10, 10)
	var path: String = tmp.path_join("flat_10x10.mat")
	t.ok(bool(g.write(path).get("ok")))
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
	t.eq(raw.size(), 200)
	t.eq(raw.decode_u16(0), 1)
	t.eq(raw.decode_u16(2 * (5 * 10 + 3)), 54, "flat row-major, no zone shuffle")
	var rd: Dictionary = BzMat.read_mat(path)
	var back: BzMat.MaterialGrid = rd.get("grid") as BzMat.MaterialGrid
	t.eq(back.grid_x, 10)
	t.eq(back.grid_z, 10)
	t.eq(back.data[5 * 10 + 3], 54)


func _test_auto_paint(t) -> void:
	var raw := PackedInt32Array()
	raw.resize(256 * 256)
	for z in 256:
		raw[z * 256] = 100
		for x in range(1, 256):
			raw[z * 256 + x] = 500
	var hm := BzHg2.HeightMap.new(1, 1, raw)
	var rules: Array = [
		{"mat_id": 1, "min_h": 0.0, "max_h": 20.0, "min_s": 0.0, "max_s": 100.0},
		{"mat_id": 2, "min_h": 20.0, "max_h": 100.0, "min_s": 0.0, "max_s": 100.0},
	]
	var grid = BzMat.auto_paint(hm, rules)
	t.ok(grid is BzMat.MaterialGrid, "auto_paint returns MaterialGrid")
	t.eq(grid.grid_x, 64)
	t.eq(grid.grid_z, 64)
	t.eq(grid.data[0], 0x1270, "tile (0,0) right-half transition")
	t.eq(grid.data[1], 0x2200, "tile (1,0) solid mat 2")
	t.eq(grid.data[64], 0x1270, "tile (0,1)")
	var dec: PackedInt32Array = grid.decode()
	t.eq(dec[0], 1)
	t.eq(dec[1], 2)
	t.eq(dec[2], 0)
	t.eq(dec[3], 1)
	t.eq(dec[4], 3)


func _test_errors(t, tmp: String) -> void:
	var empty_p: String = tmp.path_join("empty.mat")
	_write_bytes(empty_p, PackedByteArray())
	var bad: Dictionary = BzMat.read_mat(empty_p)
	t.eq(bad.get("ok"), false)
	t.ok(str(bad.get("error", {}).get("message", "")).contains("empty MAT file"))


func _build_one_zone_mat() -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(64 * 64 * 2)
	buf.encode_u16(_disk_index(0, 0, 1, 64) * 2, BzMat.encode_entry(2, 3, 1, 0, 2, 1))
	buf.encode_u16(_disk_index(63, 63, 1, 64) * 2, BzMat.encode_entry(4, 4))
	buf.encode_u16(_disk_index(20, 10, 1, 64) * 2, BzMat.encode_entry(5, 1, 0, 1, 3, 2))
	return buf


func _build_two_zone_mat() -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(128 * 128 * 2)
	buf.encode_u16(_disk_index(0, 0, 2, 64) * 2, 0x1111)
	buf.encode_u16(_disk_index(70, 10, 2, 64) * 2, 0xABCD)
	buf.encode_u16(_disk_index(10, 70, 2, 64) * 2, 0x2222)
	buf.encode_u16(_disk_index(70, 70, 2, 64) * 2, 0x3333)
	return buf


func _disk_index(tx: int, tz: int, map_width: int, zone_len: int) -> int:
	var zone_x: int = tx / zone_len
	var sub_x: int = tx % zone_len
	var zone_z: int = tz / zone_len
	var sub_z: int = tz % zone_len
	return ((zone_z * map_width + zone_x) * zone_len + sub_z) * zone_len + sub_x


func _tmp_dir() -> String:
	var d: String = OS.get_temp_dir().path_join("bz98_gd_mat")
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _write_bytes(path: String, buf: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(buf)
	f.close()
	return true


func _sha256(buf: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(buf)
	return h.finish().hex_encode()
