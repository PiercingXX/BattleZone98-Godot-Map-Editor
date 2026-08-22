extends RefCounted
## BzHg2: parse F8/Python vectors, zone interleave, sample/slope, byte-identical RT.


func run(t) -> void:
	var tmp: String = _tmp_dir()
	_test_parse_one_zone(t, tmp)
	_test_parse_two_zone(t, tmp)
	_test_roundtrip_bytes(t, tmp)
	_test_write_then_parse(t, tmp)
	_test_edit_isolation(t, tmp)
	_test_sample_and_slope(t, tmp)
	_test_errors(t, tmp)


func _test_parse_one_zone(t, tmp: String) -> void:
	var buf: PackedByteArray = _build_one_zone_hg2()
	t.eq(_sha256(buf), "b69d62d04b42963e5cac261c174513984c67c3cec671e47d59c3155ab06858b1",
		"1x1 fixture matches Python reference sha256")
	var path: String = tmp.path_join("one_zone.hg2")
	t.ok(_write_bytes(path, buf), "write 1x1 fixture")
	var result: Dictionary = BzHg2.read_hg2(path)
	t.ok(bool(result.get("ok")), "read 1x1 ok")
	var hm: BzHg2.HeightMap = result.get("heightmap") as BzHg2.HeightMap
	t.ok(hm != null, "heightmap instance")
	t.eq(hm.version, 1)
	t.eq(hm.depth, 8)
	t.eq(hm.zonesX, 1)
	t.eq(hm.zonesZ, 1)
	t.eq(hm.unknownA, 10)
	t.eq(hm.unknownB, 0)
	t.eq(hm.grid_x, 256)
	t.eq(hm.grid_z, 256)
	t.near(hm.width_m, 1280.0)
	t.near(hm.depth_m, 1280.0)
	t.eq(hm.data.size(), 256 * 256)
	# Disk X runs east→west, so disk sample x lands at world 255 - x (F1 §4.1).
	t.eq(hm.data[255], 100, "disk (0,0) is world (255,0)")
	t.eq(hm.data[254], 57394, "disk (1,0) is world (254,0), flag bits kept")
	t.eq(hm.data[20 * 256 + 245], 48590, "disk (10,20) is world (245,20)")
	t.eq(hm.data[20 * 256 + 245] & 0x1FFF, 7630, "13-bit height above 4095")
	t.eq(hm.data[20 * 256 + 245] >> 13, 5, "flag bits 5")
	t.eq(hm.data[255 * 256 + 0], 2000, "disk (255,255) is world (0,255)")
	t.eq(hm.data[0], 1000, "world (0,0) is the plateau, not disk (0,0)")
	t.eq(hm.data[128 * 256 + 128], 1000, "untouched plateau")


func _test_parse_two_zone(t, tmp: String) -> void:
	var buf: PackedByteArray = _build_two_zone_hg2()
	t.eq(_sha256(buf), "1531bb63434331223e41c0e44aeaa45a1d8f09332f6d719c6e15c3392664cbf2",
		"2x2 fixture matches Python reference sha256")
	var path: String = tmp.path_join("two_zone.hg2")
	t.ok(_write_bytes(path, buf), "write 2x2 fixture")
	var result: Dictionary = BzHg2.HeightMap.read(path)
	t.ok(bool(result.get("ok")), "read 2x2 ok")
	var hm: BzHg2.HeightMap = result.get("heightmap") as BzHg2.HeightMap
	t.eq(hm.zonesX, 2)
	t.eq(hm.zonesZ, 2)
	t.eq(hm.unknownB, 7, "unknownB preserved (F1 map_version split)")
	t.eq(hm.grid_x, 512)
	t.eq(hm.grid_z, 512)
	# The X mirror is global across zones: disk x → world 511 - x.
	t.eq(hm.data[511], 1111, "disk (0,0) is world (511,0)")
	t.eq(hm.data[5 * 512 + 211], 7777, "disk (300,5) is world (211,5)")
	t.eq(hm.data[300 * 512 + 501], 3333, "disk (10,300) is world (501,300)")
	t.eq(hm.data[400 * 512 + 111], 4444, "disk (400,400) is world (111,400)")
	t.eq(hm.data[256 * 512 + 255], 24776, "flagged cell, disk (256,256)")
	t.eq(hm.data[5 * 512 + 212], 1000, "neighbour untouched")
	# A row-major reader would place (300,5) at disk index 5*512+300=2860,
	# not 66860. Confirm the file is not row-major at that slot.
	t.eq(buf.decode_u16(12 + 2860 * 2), 1000, "row-major slot is the plateau")
	t.eq(buf.decode_u16(12 + 66860 * 2), 7777, "zone-major slot holds (300,5)")


func _test_roundtrip_bytes(t, tmp: String) -> void:
	for pair in [
		["one_zone.hg2", _build_one_zone_hg2()],
		["two_zone.hg2", _build_two_zone_hg2()],
	]:
		var name: String = pair[0]
		var original: PackedByteArray = pair[1]
		var src: String = tmp.path_join("rt_src_" + name)
		var dst: String = tmp.path_join("rt_dst_" + name)
		_write_bytes(src, original)
		var result: Dictionary = BzHg2.read_hg2(src)
		t.ok(bool(result.get("ok")), "rt read " + name)
		var hm: BzHg2.HeightMap = result.get("heightmap") as BzHg2.HeightMap
		var wr: Dictionary = BzHg2.write_hg2(dst, hm)
		t.ok(bool(wr.get("ok")), "rt write " + name)
		var back: PackedByteArray = FileAccess.get_file_as_bytes(dst)
		t.eq(back.size(), original.size(), "rt size " + name)
		t.ok(back == original, "byte-identical round-trip " + name)


func _test_write_then_parse(t, tmp: String) -> void:
	var data := PackedInt32Array()
	data.resize(256 * 256)
	data.fill(1200)
	data[3 * 256 + 7] = 4095
	var hm := BzHg2.HeightMap.new(1, 1, data, 1, 8, 10, 0)
	var path: String = tmp.path_join("authored.hg2")
	var wr: Dictionary = hm.write(path)
	t.ok(bool(wr.get("ok")), "authored write")
	var rd: Dictionary = BzHg2.read_hg2(path)
	t.ok(bool(rd.get("ok")), "authored read")
	var back: BzHg2.HeightMap = rd.get("heightmap") as BzHg2.HeightMap
	t.eq(back.data[3 * 256 + 7], 4095)
	t.eq(back.data[0], 1200)
	t.eq(back.zonesX, 1)


func _test_edit_isolation(t, tmp: String) -> void:
	var path: String = tmp.path_join("two_zone.hg2")
	_write_bytes(path, _build_two_zone_hg2())
	var result: Dictionary = BzHg2.read_hg2(path)
	var hm: BzHg2.HeightMap = result.get("heightmap") as BzHg2.HeightMap
	var flagged: int = hm.data[256 * 512 + 255]
	hm.data[5 * 512 + 300] = 8001
	var outp: String = tmp.path_join("two_zone_edit.hg2")
	hm.write(outp)
	var again: Dictionary = BzHg2.read_hg2(outp)
	var hm2: BzHg2.HeightMap = again.get("heightmap") as BzHg2.HeightMap
	t.eq(hm2.data[5 * 512 + 300], 8001, "edited cell stays put in world space")
	t.eq(hm2.data[256 * 512 + 255], flagged, "flag bits on a different cell survive")
	t.eq(hm2.data[511], 1111)
	t.eq(hm2.data[300 * 512 + 501], 3333)


func _test_sample_and_slope(t, tmp: String) -> void:
	var path: String = tmp.path_join("one_zone.hg2")
	_write_bytes(path, _build_one_zone_hg2())
	var hm: BzHg2.HeightMap = BzHg2.read_hg2(path)["heightmap"]
	# The marked samples sit at the EAST edge in world space (F1 §4.1).
	t.near(BzHg2.sample_m(hm, 0.0, 0.0), 100.0, 0.0001, "world (0,0) is the plateau")
	# Uses the raw word including flags — matches Python, not F1 masked r16.
	t.near(BzHg2.sample_m(hm, 1272.5, 0.0), 2874.7, 0.0001, "midway into the flagged cell")
	t.near(BzHg2.sample_m(hm, 1270.0, 0.0), 5739.4, 0.0001)
	t.near(BzHg2.sample_m(hm, 1275.0, 1275.0), 100.0, 0.0001)
	var s: PackedFloat64Array = BzHg2.slope(hm)
	t.eq(s.size(), 256 * 256)
	t.near(s[20 * 256 + 10], 0.0, 0.0001, "flat interior")
	t.near(s[128 * 256 + 128], 0.0, 0.0001)
	t.near(s[255], 1146.0213673400685, 0.0001, "numpy.gradient at world (255,0)")
	var mask: PackedByteArray = BzHg2.buildable_mask(hm)
	t.eq(mask[255], 0, "world (255,0) not buildable")
	t.eq(mask[128 * 256 + 128], 1, "plateau is buildable")

	var ramp := PackedInt32Array()
	ramp.resize(256 * 256)
	for z in 256:
		for x in 256:
			ramp[z * 256 + x] = 100 + x
	var hmr := BzHg2.HeightMap.new(1, 1, ramp)
	var sr: PackedFloat64Array = BzHg2.slope(hmr)
	t.near(sr[0], 0.02, 1e-12, "ramp edge")
	t.near(sr[128 * 256 + 128], 0.02, 1e-12, "ramp interior")
	t.near(sr[255 * 256 + 255], 0.02, 1e-12, "ramp far edge")
	t.near(BzHg2.sample_m(hmr, 12.5, 0.0), 10.25, 0.0001)
	var bm: PackedByteArray = BzHg2.buildable_mask(hmr, 0.01)
	t.eq(bm[128 * 256 + 128], 0, "0.02 > 0.01")
	var bm2: PackedByteArray = BzHg2.buildable_mask(hmr, 0.25)
	t.eq(bm2[128 * 256 + 128], 1, "0.02 <= 0.25")


func _test_errors(t, tmp: String) -> void:
	var short_p: String = tmp.path_join("short.hg2")
	_write_bytes(short_p, PackedByteArray([1, 0, 8, 0, 1, 0]))
	var bad: Dictionary = BzHg2.read_hg2(short_p)
	t.eq(bad.get("ok"), false, "truncated header")
	t.ok(str(bad.get("error", {}).get("message", "")).contains("truncated header"))

	var hdr := PackedByteArray()
	hdr.resize(12)
	hdr.encode_u16(0, 1)
	hdr.encode_u16(2, 7) # depth 7 -> zone 128, rejected
	hdr.encode_u16(4, 1)
	hdr.encode_u16(6, 1)
	hdr.encode_u16(8, 10)
	hdr.encode_u16(10, 0)
	var depth_p: String = tmp.path_join("bad_depth.hg2")
	_write_bytes(depth_p, hdr)
	var dres: Dictionary = BzHg2.read_hg2(depth_p)
	t.eq(dres.get("ok"), false, "unsupported zone size")
	t.ok(str(dres.get("error", {}).get("message", "")).contains("unsupported zone size"))

	var hdr8 := _build_one_zone_hg2()
	hdr8.resize(12 + 10) # too few samples
	var few_p: String = tmp.path_join("few.hg2")
	_write_bytes(few_p, hdr8)
	var fres: Dictionary = BzHg2.read_hg2(few_p)
	t.eq(fres.get("ok"), false, "sample count")
	t.ok(str(fres.get("error", {}).get("message", "")).contains("expected"))


func _build_one_zone_hg2() -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(12 + 256 * 256 * 2)
	buf.encode_u16(0, 1)
	buf.encode_u16(2, 8)
	buf.encode_u16(4, 1)
	buf.encode_u16(6, 1)
	buf.encode_u16(8, 10)
	buf.encode_u16(10, 0)
	for i in (256 * 256):
		buf.encode_u16(12 + i * 2, 1000)
	buf.encode_u16(12 + _disk_index(0, 0, 1, 256) * 2, 100)
	buf.encode_u16(12 + _disk_index(1, 0, 1, 256) * 2, 50 | (7 << 13))
	buf.encode_u16(12 + _disk_index(10, 20, 1, 256) * 2, 7630 | (5 << 13))
	buf.encode_u16(12 + _disk_index(255, 255, 1, 256) * 2, 2000)
	return buf


func _build_two_zone_hg2() -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(12 + 512 * 512 * 2)
	buf.encode_u16(0, 1)
	buf.encode_u16(2, 8)
	buf.encode_u16(4, 2)
	buf.encode_u16(6, 2)
	buf.encode_u16(8, 10)
	buf.encode_u16(10, 7)
	for i in (512 * 512):
		buf.encode_u16(12 + i * 2, 1000)
	buf.encode_u16(12 + _disk_index(0, 0, 2, 256) * 2, 1111)
	buf.encode_u16(12 + _disk_index(300, 5, 2, 256) * 2, 7777)
	buf.encode_u16(12 + _disk_index(10, 300, 2, 256) * 2, 3333)
	buf.encode_u16(12 + _disk_index(400, 400, 2, 256) * 2, 4444)
	buf.encode_u16(12 + _disk_index(256, 256, 2, 256) * 2, 200 | (3 << 13))
	return buf


func _disk_index(x: int, z: int, map_width: int, zone_len: int) -> int:
	var zone_x: int = x / zone_len
	var sub_x: int = x % zone_len
	var zone_z: int = z / zone_len
	var sub_z: int = z % zone_len
	return ((zone_z * map_width + zone_x) * zone_len + sub_z) * zone_len + sub_x


func _tmp_dir() -> String:
	var d: String = OS.get_temp_dir().path_join("bz98_gd_hg2")
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
