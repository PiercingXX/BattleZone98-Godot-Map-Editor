extends RefCounted
## BzLgt: copy-only parse, size formula, multi-zone, byte-identical RT.


func run(t) -> void:
	var tmp: String = _tmp_dir()
	_test_parse_one_zone(t, tmp)
	_test_parse_two_zone(t, tmp)
	_test_roundtrip_bytes(t, tmp)
	_test_write_then_parse(t, tmp)
	_test_errors(t, tmp)


func _test_parse_one_zone(t, tmp: String) -> void:
	var buf: PackedByteArray = _build_one_zone_lgt()
	t.eq(buf.size(), 131072)
	var path: String = tmp.path_join("one_zone.lgt")
	t.ok(_write_bytes(path, buf))
	var result: Dictionary = BzLgt.read_lgt(path, 1, 1)
	t.ok(bool(result.get("ok")), "read 1x1")
	var lm: BzLgt.LightMap = result.get("lightmap") as BzLgt.LightMap
	t.eq(lm.zonesX, 1)
	t.eq(lm.zonesZ, 1)
	t.eq(lm.plane_count, 2)
	t.eq(lm.data.size(), 131072)
	t.eq(lm.data[0], 0)
	t.eq(lm.data[255], 255)
	t.eq(lm.data[256], 0)
	t.eq(lm.data[65535], 255)
	t.eq(lm.data[65536], 0xA5, "extra plane")
	t.eq(lm.data[131071], 0xA5)


func _test_parse_two_zone(t, tmp: String) -> void:
	var buf: PackedByteArray = _build_two_zone_lgt()
	t.eq(buf.size(), (4 + 1) * 65536, "2x2 size formula")
	var path: String = tmp.path_join("two_zone.lgt")
	t.ok(_write_bytes(path, buf))
	var result: Dictionary = BzLgt.LightMap.read(path, 2, 2)
	t.ok(bool(result.get("ok")), "read 2x2")
	var lm: BzLgt.LightMap = result.get("lightmap") as BzLgt.LightMap
	t.eq(lm.plane_count, 5)
	t.eq(lm.data.size(), 327680)
	for p in 5:
		t.eq(lm.data[p * 65536], p + 1, "plane %d first byte" % p)
		t.eq(lm.data[p * 65536 + 65535], p + 1, "plane %d last byte" % p)


func _test_roundtrip_bytes(t, tmp: String) -> void:
	for pair in [
		["one_zone.lgt", _build_one_zone_lgt(), 1, 1],
		["two_zone.lgt", _build_two_zone_lgt(), 2, 2],
	]:
		var name: String = pair[0]
		var original: PackedByteArray = pair[1]
		var zx: int = pair[2]
		var zz: int = pair[3]
		var src: String = tmp.path_join("rt_src_" + name)
		var dst: String = tmp.path_join("rt_dst_" + name)
		_write_bytes(src, original)
		var result: Dictionary = BzLgt.read_lgt(src, zx, zz)
		t.ok(bool(result.get("ok")), "rt read " + name)
		var lm: BzLgt.LightMap = result.get("lightmap") as BzLgt.LightMap
		var wr: Dictionary = BzLgt.write_lgt(dst, lm)
		t.ok(bool(wr.get("ok")), "rt write " + name)
		var back: PackedByteArray = FileAccess.get_file_as_bytes(dst)
		t.ok(back == original, "byte-identical round-trip " + name)


func _test_write_then_parse(t, tmp: String) -> void:
	var data := PackedByteArray()
	data.resize(2 * 65536)
	data.fill(0x3C)
	data[10] = 0x01
	var lm := BzLgt.LightMap.new(data, 1, 1)
	var path: String = tmp.path_join("authored.lgt")
	t.ok(bool(lm.write(path).get("ok")))
	var rd: Dictionary = BzLgt.read_lgt(path, 1, 1)
	var back: BzLgt.LightMap = rd.get("lightmap") as BzLgt.LightMap
	t.eq(back.data[10], 0x01)
	t.eq(back.data[11], 0x3C)
	t.eq(back.plane_count, 2)


func _test_errors(t, tmp: String) -> void:
	var path: String = tmp.path_join("bad_size.lgt")
	_write_bytes(path, PackedByteArray([1, 2, 3, 4]))
	var bad: Dictionary = BzLgt.read_lgt(path, 1, 1)
	t.eq(bad.get("ok"), false)
	var msg: String = str(bad.get("error", {}).get("message", ""))
	t.ok(msg.contains("LGT size 4"), msg)
	t.ok(msg.contains("1x1"), msg)
	t.ok(msg.contains("131072"), msg)
	var mismatch: Dictionary = BzLgt.read_lgt(path, 2, 2)
	t.eq(mismatch.get("ok"), false)
	t.ok(str(mismatch.get("error", {}).get("message", "")).contains("2x2"))


func _build_one_zone_lgt() -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(2 * 65536)
	for i in 65536:
		buf[i] = i & 0xFF
	for i in range(65536, 131072):
		buf[i] = 0xA5
	return buf


func _build_two_zone_lgt() -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(5 * 65536)
	for p in 5:
		var fill: int = p + 1
		var base: int = p * 65536
		for i in 65536:
			buf[base + i] = fill
	return buf


func _tmp_dir() -> String:
	var d: String = OS.get_temp_dir().path_join("bz98_gd_lgt")
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _write_bytes(path: String, buf: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(buf)
	f.close()
	return true
