extends RefCounted
## Synthetic .map / .act tests. Fixtures are hand-packed per F6 and maptex.py.
## How they were made: 2×2 images packed as little-endian header + payload
## (no game/corpus bytes). Expected RGBA was computed from maptex.py's loops
## without importing PIL.


func run(t) -> void:
	var dir := _tmp_dir()
	_test_act(t, dir)
	_test_indexed(t, dir)
	_test_indexed_greyscale(t, dir)
	_test_argb4444(t, dir)
	_test_rgb565(t, dir)
	_test_argb8888(t, dir)
	_test_xrgb8888(t, dir)
	_test_size_arithmetic(t, dir)
	_test_write_parse_argb8888(t, dir)
	_test_errors(t, dir)


func _test_act(t, dir: String) -> void:
	var pal := _make_palette()
	var path := dir.path_join("pal.act")
	_write(path, pal)
	var r: Dictionary = BzMaptex.read_act(path)
	t.ok(bool(r.get("ok", false)), "read_act ok")
	var entries: Array = r.get("palette", [])
	t.eq(entries.size(), 256, "256 ACT entries")
	t.eq(entries[0], Vector3i(255, 0, 0))
	t.eq(entries[1], Vector3i(0, 255, 0))
	t.eq(entries[2], Vector3i(0, 0, 255))
	t.eq(entries[3], Vector3i(255, 255, 255))
	# write→parse byte-identical: re-emit the 768-byte file from the parsed palette.
	var again := PackedByteArray()
	again.resize(768)
	for i in entries.size():
		var rgb: Vector3i = entries[i]
		again[i * 3] = rgb.x
		again[i * 3 + 1] = rgb.y
		again[i * 3 + 2] = rgb.z
	t.eq(again, pal, "ACT parse→pack byte-identical")


func _test_indexed(t, dir: String) -> void:
	# header: row_b=2, fmt=0, height=2, unknown=0xABCD; indices 0,1 / 2,3
	var raw := "020000000200cdab00010203".hex_decode()
	var path := dir.path_join("fmt0.map")
	_write(path, raw)
	var act: Dictionary = BzMaptex.read_act(dir.path_join("pal.act"))
	var r: Dictionary = BzMaptex.read_map(path, act.get("palette", []))
	t.ok(bool(r.get("ok", false)), "indexed parse ok")
	t.eq(r.get("width"), 2)
	t.eq(r.get("height"), 2)
	t.eq(r.get("pixel_format"), BzMaptex.FMT_INDEXED)
	t.eq(r.get("row_byte_size"), 2)
	t.eq(r.get("unknown"), 0xABCD, "unknown header preserved in result")
	var img: Image = r["image"]
	_expect_rgba(t, img, 0, 0, 255, 0, 0, 255, "idx0 red")
	_expect_rgba(t, img, 1, 0, 0, 255, 0, 255, "idx1 green")
	_expect_rgba(t, img, 0, 1, 0, 0, 255, 255, "idx2 blue")
	_expect_rgba(t, img, 1, 1, 255, 255, 255, 255, "idx3 white")


func _test_indexed_greyscale(t, dir: String) -> void:
	var path := dir.path_join("fmt0.map")
	var r: Dictionary = BzMaptex.read_map(path, null)
	t.ok(bool(r.get("ok", false)), "greyscale fallback")
	var img: Image = r["image"]
	# Python default palette is (i,i,i) for index i.
	_expect_rgba(t, img, 0, 0, 0, 0, 0, 255, "grey 0")
	_expect_rgba(t, img, 1, 0, 1, 1, 1, 255, "grey 1")
	_expect_rgba(t, img, 0, 1, 2, 2, 2, 255, "grey 2")
	_expect_rgba(t, img, 1, 1, 3, 3, 3, 255, "grey 3")
	var empty: Array = []
	var r2: Dictionary = BzMaptex.read_map(path, empty)
	t.ok(bool(r2.get("ok", false)), "empty palette is falsy → greyscale")
	_expect_rgba(t, r2["image"], 1, 1, 3, 3, 3, 255, "empty pal grey 3")


func _test_argb4444(t, dir: String) -> void:
	# words LE: F000, F800, 0F00, 00F0
	var raw := "040001000200000000f000f8000ff000".hex_decode()
	var path := dir.path_join("fmt1.map")
	_write(path, raw)
	var r: Dictionary = BzMaptex.read_map(path)
	t.ok(bool(r.get("ok", false)), "4444 parse")
	t.eq(r.get("pixel_format"), BzMaptex.FMT_ARGB4444)
	var img: Image = r["image"]
	_expect_rgba(t, img, 0, 0, 0, 0, 0, 255, "4444 opaque black")
	_expect_rgba(t, img, 1, 0, 136, 0, 0, 255, "4444 R=8 → 136")
	_expect_rgba(t, img, 0, 1, 255, 0, 0, 0, "4444 A=0 R=15")
	_expect_rgba(t, img, 1, 1, 0, 255, 0, 0, "4444 A=0 G=15")


func _test_rgb565(t, dir: String) -> void:
	# words LE: F800, 07E0, 001F, 8410
	var raw := "040002000200010000f8e0071f001084".hex_decode()
	var path := dir.path_join("fmt2.map")
	_write(path, raw)
	var r: Dictionary = BzMaptex.read_map(path)
	t.ok(bool(r.get("ok", false)), "565 parse")
	t.eq(r.get("unknown"), 1)
	var img: Image = r["image"]
	_expect_rgba(t, img, 0, 0, 255, 0, 0, 255, "565 red")
	_expect_rgba(t, img, 1, 0, 0, 255, 0, 255, "565 green")
	_expect_rgba(t, img, 0, 1, 0, 0, 255, 255, "565 blue")
	# int(16*255/31)=131, int(32*255/63)=129 — Python true-division then trunc.
	_expect_rgba(t, img, 1, 1, 131, 129, 131, 255, "565 mid grey 0x8410")


func _test_argb8888(t, dir: String) -> void:
	# BGRA on disk: (0x10,0x20,0x30,0x40), (0,255,0,128), (255,0,0,255), (0,0,255,0)
	var raw := "08000300020000001020304000ff0080ff0000ff0000ff00".hex_decode()
	var path := dir.path_join("fmt3.map")
	_write(path, raw)
	var r: Dictionary = BzMaptex.read_map(path)
	t.ok(bool(r.get("ok", false)), "8888 parse")
	var img: Image = r["image"]
	_expect_rgba(t, img, 0, 0, 48, 32, 16, 64, "8888 BGRA swap")
	_expect_rgba(t, img, 1, 0, 0, 255, 0, 128, "8888 green")
	_expect_rgba(t, img, 0, 1, 0, 0, 255, 255, "8888 blue")
	_expect_rgba(t, img, 1, 1, 255, 0, 0, 0, "8888 red A=0")


func _test_xrgb8888(t, dir: String) -> void:
	var raw := "08000400020000001020304000ff0080ff0000ff0000ff00".hex_decode()
	var path := dir.path_join("fmt4.map")
	_write(path, raw)
	var r: Dictionary = BzMaptex.read_map(path)
	t.ok(bool(r.get("ok", false)), "XRGB parse")
	var img: Image = r["image"]
	_expect_rgba(t, img, 0, 0, 48, 32, 16, 255, "XRGB alpha forced")
	_expect_rgba(t, img, 1, 0, 0, 255, 0, 255, "XRGB green opaque")
	_expect_rgba(t, img, 1, 1, 255, 0, 0, 255, "XRGB red opaque")


func _test_size_arithmetic(t, dir: String) -> void:
	for name in ["fmt0.map", "fmt1.map", "fmt2.map", "fmt3.map", "fmt4.map"]:
		var data := FileAccess.get_file_as_bytes(dir.path_join(name))
		var row_b: int = data.decode_u16(0)
		var height: int = data.decode_u16(4)
		t.eq(data.size(), 8 + row_b * height, "size arithmetic %s" % name)


func _test_write_parse_argb8888(t, dir: String) -> void:
	# Write a 2×2 ARGB8888 .map from known RGBA, parse, re-emit, compare bytes.
	var rgba := [
		[10, 20, 30, 40],
		[50, 60, 70, 80],
		[90, 100, 110, 120],
		[130, 140, 150, 160],
	]
	var packed := _pack_argb8888(2, 2, 0x1111, rgba)
	var path := dir.path_join("roundtrip.map")
	_write(path, packed)
	var r: Dictionary = BzMaptex.read_map(path)
	t.ok(bool(r.get("ok", false)), "round-trip parse")
	t.eq(r.get("unknown"), 0x1111)
	var img: Image = r["image"]
	_expect_rgba(t, img, 0, 0, 10, 20, 30, 40, "rt 00")
	_expect_rgba(t, img, 1, 0, 50, 60, 70, 80, "rt 10")
	_expect_rgba(t, img, 0, 1, 90, 100, 110, 120, "rt 01")
	_expect_rgba(t, img, 1, 1, 130, 140, 150, 160, "rt 11")
	var again := _pack_image_argb8888(img, int(r.get("unknown", 0)))
	t.eq(again, packed, "ARGB8888 write→parse→write byte-identical")


func _test_errors(t, dir: String) -> void:
	var missing: Dictionary = BzMaptex.read_act(dir.path_join("nope.act"))
	t.eq(missing.get("ok"), false, "missing act")
	var short_act := dir.path_join("short.act")
	_write(short_act, PackedByteArray([1, 2, 3]))
	var bad_act: Dictionary = BzMaptex.read_act(short_act)
	t.eq(bad_act.get("ok"), false, "short act")
	var short_map := dir.path_join("short.map")
	_write(short_map, PackedByteArray([0, 1, 2]))
	var too_short: Dictionary = BzMaptex.read_map(short_map)
	t.eq(too_short.get("ok"), false, "short map")
	var hdr := PackedByteArray()
	hdr.resize(8)
	hdr.encode_u16(0, 4)
	hdr.encode_u16(2, 99)
	hdr.encode_u16(4, 1)
	hdr.encode_u16(6, 0)
	var bad_fmt := dir.path_join("badfmt.map")
	_write(bad_fmt, hdr)
	var bad: Dictionary = BzMaptex.read_map(bad_fmt)
	t.eq(bad.get("ok"), false, "unknown pixel_format")
	var trunc := PackedByteArray()
	trunc.resize(8)
	trunc.encode_u16(0, 4)
	trunc.encode_u16(2, 3)
	trunc.encode_u16(4, 2)
	trunc.encode_u16(6, 0)
	var trunc_path := dir.path_join("trunc.map")
	_write(trunc_path, trunc)
	var tr: Dictionary = BzMaptex.read_map(trunc_path)
	t.eq(tr.get("ok"), false, "truncated payload")


func _pack_argb8888(width: int, height: int, unknown: int, rgba: Array) -> PackedByteArray:
	var row_b: int = width * 4
	var out := PackedByteArray()
	out.resize(8 + row_b * height)
	out.encode_u16(0, row_b)
	out.encode_u16(2, BzMaptex.FMT_ARGB8888)
	out.encode_u16(4, height)
	out.encode_u16(6, unknown)
	var o: int = 8
	for px in rgba:
		# disk is B, G, R, A
		out[o] = int(px[2])
		out[o + 1] = int(px[1])
		out[o + 2] = int(px[0])
		out[o + 3] = int(px[3])
		o += 4
	return out


func _pack_image_argb8888(img: Image, unknown: int) -> PackedByteArray:
	var rgba: Array = []
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			rgba.append([
				clampi(int(round(c.r * 255.0)), 0, 255),
				clampi(int(round(c.g * 255.0)), 0, 255),
				clampi(int(round(c.b * 255.0)), 0, 255),
				clampi(int(round(c.a * 255.0)), 0, 255),
			])
	return _pack_argb8888(img.get_width(), img.get_height(), unknown, rgba)


func _make_palette() -> PackedByteArray:
	var act := PackedByteArray()
	act.resize(768)
	var colors := [
		Vector3i(255, 0, 0),
		Vector3i(0, 255, 0),
		Vector3i(0, 0, 255),
		Vector3i(255, 255, 255),
	]
	for i in colors.size():
		var c: Vector3i = colors[i]
		act[i * 3] = c.x
		act[i * 3 + 1] = c.y
		act[i * 3 + 2] = c.z
	return act


func _expect_rgba(t, img: Image, x: int, y: int, r: int, g: int, b: int, a: int, msg: String) -> void:
	var c: Color = img.get_pixel(x, y)
	t.near(c.r, float(r) / 255.0, 0.002, msg + " r")
	t.near(c.g, float(g) / 255.0, 0.002, msg + " g")
	t.near(c.b, float(b) / 255.0, 0.002, msg + " b")
	t.near(c.a, float(a) / 255.0, 0.002, msg + " a")


func _tmp_dir() -> String:
	var dir := OS.get_temp_dir().path_join("bz_test_maptex")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _write(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
