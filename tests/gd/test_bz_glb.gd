extends RefCounted
## GLB writer tests. The no-image triangle golden was produced by
## `write_glb` in formats/glb.py (PIL mocked; images=[]). Chunk layout
## follows the glTF 2.0 binary container (magic, version, padded chunks).


func run(t) -> void:
	var dir := _tmp_dir()
	_test_write_parse_triangle(t, dir)
	_test_byte_identical_python_golden(t, dir)
	_test_alignment_and_json(t, dir)
	_test_custom_colour(t, dir)
	_test_uint32_indices(t, dir)
	_test_with_image(t, dir)
	_test_skips_empty_and_errors(t, dir)


func _test_write_parse_triangle(t, dir: String) -> void:
	var path := dir.path_join("tri.glb")
	var r: Dictionary = BzGlb.write_glb(path, [_triangle_prim()], [])
	t.ok(bool(r.get("ok", false)), "write_glb ok")
	t.eq(r.get("path"), path)
	var data := FileAccess.get_file_as_bytes(path)
	var parsed: Dictionary = _parse_glb(data)
	t.ok(bool(parsed.get("ok", false)), "parse written GLB")
	t.eq(parsed.get("magic"), "glTF")
	t.eq(parsed.get("version"), 2)
	t.eq(parsed.get("total"), data.size(), "header total == file size")
	t.eq(int(parsed.get("json_len", -1)) % 4, 0, "JSON chunk 4-aligned")
	t.eq(int(parsed.get("bin_len", -1)) % 4, 0, "BIN chunk 4-aligned")
	t.eq(parsed.get("json_type"), "JSON")
	t.eq(parsed.get("bin_type"), "BIN")
	var root: Variant = JSON.parse_string(parsed["json_text"])
	t.ok(root is Dictionary, "JSON chunk is an object")
	var doc: Dictionary = root
	t.eq((doc.get("asset", {}) as Dictionary).get("generator"), "bzmap")
	t.eq((doc.get("asset", {}) as Dictionary).get("version"), "2.0")
	t.eq(doc.get("scene"), 0)
	var accessors: Array = doc.get("accessors", [])
	t.eq(accessors.size(), 4, "pos/nrm/uv/idx accessors")
	t.eq((accessors[0] as Dictionary).get("type"), "VEC3")
	t.eq((accessors[0] as Dictionary).get("count"), 3)
	t.eq((accessors[0] as Dictionary).get("componentType"), 5126)
	t.eq((accessors[3] as Dictionary).get("type"), "SCALAR")
	t.eq((accessors[3] as Dictionary).get("componentType"), 5123)
	var views: Array = doc.get("bufferViews", [])
	t.eq(views.size(), 4)
	for v in views:
		t.eq(int((v as Dictionary).get("byteOffset", 1)) % 4, 0, "view offset aligned")
	var prims: Array = ((doc.get("meshes", [{}]) as Array)[0] as Dictionary).get("primitives", [])
	t.eq(prims.size(), 1)
	t.eq((prims[0] as Dictionary).get("mode"), 4)
	var factor: Array = (
		((doc.get("materials", [{}]) as Array)[0] as Dictionary)
		.get("pbrMetallicRoughness", {}) as Dictionary
	).get("baseColorFactor", [])
	t.eq(factor.size(), 4)
	t.near(float(factor[0]), 180.0 / 255.0, 0.0000001, "default colour r")
	t.near(float(factor[3]), 1.0, 0.0000001, "default colour a")
	# BIN: 36+36+24+8 = 104
	t.eq(parsed.get("bin_len"), 104)
	var bin: PackedByteArray = parsed["bin"]
	t.near(bin.decode_float(0), 0.0)
	t.near(bin.decode_float(12), 1.0)
	t.near(bin.decode_float(16), 0.0)
	t.eq(bin.decode_u16(96), 0)
	t.eq(bin.decode_u16(98), 1)
	t.eq(bin.decode_u16(100), 2)
	t.eq(bin.decode_u16(102), 0, "index pad")


func _test_byte_identical_python_golden(t, dir: String) -> void:
	var path := dir.path_join("golden.glb")
	var r: Dictionary = BzGlb.write_glb(path, [_triangle_prim()], [])
	t.ok(bool(r.get("ok", false)))
	var got := FileAccess.get_file_as_bytes(path)
	var want := _python_triangle_glb()
	t.eq(got.size(), want.size(), "golden size")
	t.eq(got, want, "write_glb matches Python glb.py triangle golden")


func _test_alignment_and_json(t, dir: String) -> void:
	# A colour that produces a JSON length not already % 4, if possible,
	# plus a 1-vertex-less... use two primitives so JSON is longer.
	var p0 := _triangle_prim()
	var p1 := _triangle_prim()
	p1["colour"] = [10, 20, 30]
	var path := dir.path_join("two.glb")
	var r: Dictionary = BzGlb.write_glb(path, [p0, p1], [])
	t.ok(bool(r.get("ok", false)), "two prims")
	var parsed: Dictionary = _parse_glb(FileAccess.get_file_as_bytes(path))
	t.ok(bool(parsed.get("ok", false)))
	t.eq(int(parsed.get("json_len", -1)) % 4, 0)
	t.eq(int(parsed.get("bin_len", -1)) % 4, 0)
	var js: String = parsed["json_text"]
	# padding uses spaces (0x20), never NULs, per glb.py _pad(..., fill=b" ").
	var raw_json: PackedByteArray = parsed["json_raw"]
	var pad_ok := true
	var i: int = raw_json.size() - 1
	while i >= 0 and raw_json[i] == 0x20:
		i -= 1
	# bytes after the last non-space must all be spaces (already walked)
	for j in range(i + 1, raw_json.size()):
		if raw_json[j] != 0x20:
			pad_ok = false
	t.ok(pad_ok, "JSON padding is spaces")
	t.ok(JSON.parse_string(js) is Dictionary, "padded JSON still parses")


func _test_custom_colour(t, dir: String) -> void:
	var prim := _triangle_prim()
	prim["colour"] = [255, 0, 128]
	var path := dir.path_join("red.glb")
	t.ok(bool(BzGlb.write_glb(path, [prim], []).get("ok", false)))
	var parsed: Dictionary = _parse_glb(FileAccess.get_file_as_bytes(path))
	var doc: Dictionary = JSON.parse_string(parsed["json_text"])
	var factor: Array = (
		((doc.get("materials", [{}]) as Array)[0] as Dictionary)
		.get("pbrMetallicRoughness", {}) as Dictionary
	).get("baseColorFactor", [])
	t.near(float(factor[0]), 1.0, 0.0000001)
	t.near(float(factor[1]), 0.0, 0.0000001)
	t.near(float(factor[2]), 128.0 / 255.0, 0.0000001)


func _test_uint32_indices(t, dir: String) -> void:
	var prim := _triangle_prim()
	prim["indices"] = [0, 1, 70000]
	var path := dir.path_join("i32.glb")
	t.ok(bool(BzGlb.write_glb(path, [prim], []).get("ok", false)))
	var parsed: Dictionary = _parse_glb(FileAccess.get_file_as_bytes(path))
	var doc: Dictionary = JSON.parse_string(parsed["json_text"])
	var acc: Dictionary = (doc.get("accessors", [{}]) as Array)[3]
	t.eq(acc.get("componentType"), 5125, "uint32 indices")
	t.eq(int((doc.get("bufferViews", [{}]) as Array)[3].get("byteLength", 0)) % 4, 0)


func _test_with_image(t, dir: String) -> void:
	var img := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color8(255, 0, 0, 255))
	img.set_pixel(1, 0, Color8(0, 255, 0, 255))
	img.set_pixel(0, 1, Color8(0, 0, 255, 255))
	img.set_pixel(1, 1, Color8(255, 255, 0, 255))
	var prim := _triangle_prim()
	prim["image"] = 0
	var path := dir.path_join("tex.glb")
	var r: Dictionary = BzGlb.write_glb(path, [prim], [img])
	t.ok(bool(r.get("ok", false)), "write with image")
	var parsed: Dictionary = _parse_glb(FileAccess.get_file_as_bytes(path))
	t.ok(bool(parsed.get("ok", false)))
	var doc: Dictionary = JSON.parse_string(parsed["json_text"])
	t.eq((doc.get("images", []) as Array).size(), 1)
	t.eq((doc.get("textures", []) as Array).size(), 1)
	var view_i: int = int(((doc.get("images", [{}]) as Array)[0] as Dictionary).get("bufferView", -1))
	var view: Dictionary = (doc.get("bufferViews", [{}]) as Array)[view_i]
	var off: int = int(view.get("byteOffset", 0))
	var ln: int = int(view.get("byteLength", 0))
	var bin: PackedByteArray = parsed["bin"]
	var png := bin.slice(off, off + ln)
	# strip trailing pad zeros that belong to the bufferView length
	while png.size() > 8 and png[png.size() - 1] == 0:
		png = png.slice(0, png.size() - 1)
	# PNG signature
	t.eq(png[0], 0x89, "png sig 0")
	t.eq(png[1], 0x50, "png sig P")
	var loaded := Image.new()
	var err: Error = loaded.load_png_from_buffer(png)
	t.eq(err, OK, "embedded PNG loads")
	if err == OK:
		t.eq(loaded.get_width(), 2)
		t.eq(loaded.get_height(), 2)
		var c: Color = loaded.get_pixel(0, 0)
		t.near(c.r, 1.0, 0.01, "embedded red")


func _test_skips_empty_and_errors(t, dir: String) -> void:
	var empty_prim := {"positions": [], "indices": []}
	var path := dir.path_join("empty.glb")
	var r: Dictionary = BzGlb.write_glb(path, [empty_prim], [])
	t.eq(r.get("ok"), false, "no primitives")
	t.eq((r.get("error", {}) as Dictionary).get("code"), "no_primitives")
	var good := _triangle_prim()
	var mixed: Dictionary = BzGlb.write_glb(dir.path_join("mixed.glb"), [empty_prim, good], [])
	t.ok(bool(mixed.get("ok", false)), "empty prim skipped, other kept")


func _triangle_prim() -> Dictionary:
	return {
		"positions": [
			Vector3(0.0, 0.0, 0.0),
			Vector3(1.0, 0.0, 0.0),
			Vector3(0.0, 1.0, 0.0),
		],
		"normals": [
			Vector3(0.0, 0.0, 1.0),
			Vector3(0.0, 0.0, 1.0),
			Vector3(0.0, 0.0, 1.0),
		],
		"uvs": [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)],
		"indices": [0, 1, 2],
		"colour": [180, 180, 180],
	}


func _parse_glb(data: PackedByteArray) -> Dictionary:
	if data.size() < 20:
		return {"ok": false}
	if data[0] != 0x67 or data[1] != 0x6C or data[2] != 0x54 or data[3] != 0x46:
		return {"ok": false, "magic": "bad"}
	var version: int = data.decode_u32(4)
	var total: int = data.decode_u32(8)
	var jlen: int = data.decode_u32(12)
	var jtype := PackedByteArray([data[16], data[17], data[18], data[19]]).get_string_from_ascii()
	if 20 + jlen + 8 > data.size():
		return {"ok": false}
	var json_raw := data.slice(20, 20 + jlen)
	var json_text := json_raw.get_string_from_utf8().strip_edges()
	var boff: int = 20 + jlen
	var blen: int = data.decode_u32(boff)
	var btype := PackedByteArray([
		data[boff + 4], data[boff + 5], data[boff + 6]
	]).get_string_from_ascii()
	var bin := data.slice(boff + 8, boff + 8 + blen)
	return {
		"ok": true,
		"magic": "glTF",
		"version": version,
		"total": total,
		"json_len": jlen,
		"json_type": jtype,
		"json_raw": json_raw,
		"json_text": json_text,
		"bin_len": blen,
		"bin_type": btype,
		"bin": bin,
	}


func _python_triangle_glb() -> PackedByteArray:
	# formats/glb.py write_glb of the same triangle, images=[], PIL mocked.
	return (
		"676c5446020000009c040000180400004a534f4e7b226173736574223a7b22766572"
		+ "73696f6e223a22322e30222c2267656e657261746f72223a22627a6d6170227d2c22"
		+ "7363656e65223a302c227363656e6573223a5b7b226e6f646573223a5b305d7d5d2c"
		+ "226e6f646573223a5b7b226d657368223a307d5d2c226d6573686573223a5b7b2270"
		+ "72696d697469766573223a5b7b2261747472696275746573223a7b22504f53495449"
		+ "4f4e223a302c224e4f524d414c223a312c22544558434f4f52445f30223a327d2c22"
		+ "696e6469636573223a332c226d6174657269616c223a302c226d6f6465223a347d5d"
		+ "7d5d2c226163636573736f7273223a5b7b2262756666657256696577223a302c2263"
		+ "6f6d706f6e656e7454797065223a353132362c22636f756e74223a332c2274797065"
		+ "223a2256454333222c226d696e223a5b302e302c302e302c302e305d2c226d617822"
		+ "3a5b312e302c312e302c302e305d7d2c7b2262756666657256696577223a312c2263"
		+ "6f6d706f6e656e7454797065223a353132362c22636f756e74223a332c2274797065"
		+ "223a2256454333222c226d696e223a5b302e302c302e302c312e305d2c226d617822"
		+ "3a5b302e302c302e302c312e305d7d2c7b2262756666657256696577223a322c2263"
		+ "6f6d706f6e656e7454797065223a353132362c22636f756e74223a332c2274797065"
		+ "223a2256454332222c226d696e223a5b302e302c302e305d2c226d6178223a5b312e"
		+ "302c312e305d7d2c7b2262756666657256696577223a332c22636f6d706f6e656e74"
		+ "54797065223a353132332c22636f756e74223a332c2274797065223a225343414c41"
		+ "52227d5d2c226275666665725669657773223a5b7b22627566666572223a302c2262"
		+ "7974654f6666736574223a302c22627974654c656e677468223a33362c2274617267"
		+ "6574223a33343936327d2c7b22627566666572223a302c22627974654f6666736574"
		+ "223a33362c22627974654c656e677468223a33362c22746172676574223a33343936"
		+ "327d2c7b22627566666572223a302c22627974654f6666736574223a37322c226279"
		+ "74654c656e677468223a32342c22746172676574223a33343936327d2c7b22627566"
		+ "666572223a302c22627974654f6666736574223a39362c22627974654c656e677468"
		+ "223a382c22746172676574223a33343936337d5d2c2262756666657273223a5b7b22"
		+ "627974654c656e677468223a3130347d5d2c226d6174657269616c73223a5b7b2270"
		+ "62724d6574616c6c6963526f7567686e657373223a7b2262617365436f6c6f724661"
		+ "63746f72223a5b302e373035383832333532393431313736352c302e373035383832"
		+ "333532393431313736352c302e373035383832333532393431313736352c312e305d"
		+ "2c226d6574616c6c6963466163746f72223a302e302c22726f7567686e6573734661"
		+ "63746f72223a302e397d7d5d7d206800000042494e00000000000000000000000000"
		+ "0000803f0000000000000000000000000000803f0000000000000000000000000000"
		+ "803f00000000000000000000803f00000000000000000000803f0000000000000000"
		+ "0000803f00000000000000000000803f0000010002000000"
	).hex_decode()


func _tmp_dir() -> String:
	var dir := OS.get_temp_dir().path_join("bz_test_glb")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir
