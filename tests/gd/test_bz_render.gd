extends RefCounted
## BzRender: north-up PNG, session verb payload, error paths.


func run(t) -> void:
	var tmp: String = _tmp_dir("bz98_gd_render")
	_test_heightmap_north_up(t)
	_test_point_overlay_north_up(t)
	_test_write_thumbnail(t, tmp)
	_test_render_session_success(t, tmp)
	_test_render_session_errors(t, tmp)
	_test_render_preview_regions(t, tmp)


func _test_heightmap_north_up(t) -> void:
	# 8×8 plateau: high cells only in the north-west quadrant (high z, low x).
	# After flipud, that plateau must sit at the TOP-LEFT of the image.
	var data := PackedInt32Array()
	data.resize(64)
	data.fill(1000)
	for z in range(4, 8):
		for x in range(0, 4):
			data[z * 8 + x] = 4000
	var hm := {
		"data": data,
		"grid_x": 8,
		"grid_z": 8,
		"width_m": 40.0,
		"depth_m": 40.0,
	}
	var img: Image = BzRender.render_heightmap(hm, Vector2i(8, 8))
	t.ok(img != null, "render_heightmap returns Image")
	t.eq(img.get_width(), 8, "native width")
	t.eq(img.get_height(), 8, "native height")
	var nw: Color = img.get_pixel(1, 1)
	var se: Color = img.get_pixel(6, 6)
	t.ok(_lum(nw) > _lum(se), "north-west high plateau is brighter and at top-left")
	# Mirror check: a south-west-only peak must land at the BOTTOM-left, not top.
	var data_s := PackedInt32Array()
	data_s.resize(64)
	data_s.fill(1000)
	for z2 in range(0, 4):
		for x2 in range(0, 4):
			data_s[z2 * 8 + x2] = 4000
	var img_s: Image = BzRender.render_heightmap({
		"data": data_s,
		"grid_x": 8,
		"grid_z": 8,
		"width_m": 40.0,
		"depth_m": 40.0,
	}, Vector2i(8, 8))
	var sw_bottom: Color = img_s.get_pixel(1, 6)
	var nw_top: Color = img_s.get_pixel(1, 1)
	t.ok(_lum(sw_bottom) > _lum(nw_top), "south-west high plateau is at bottom-left (not mirrored)")


func _test_point_overlay_north_up(t) -> void:
	var data := PackedInt32Array()
	data.resize(64)
	data.fill(1000)
	var hm := {
		"data": data,
		"grid_x": 8,
		"grid_z": 8,
		"width_m": 40.0,
		"depth_m": 40.0,
	}
	var pv: BzRender.Preview = BzRender.Preview.new(hm, Vector2i(8, 8))
	pv.draw_points([[0.0, 40.0]], [255, 0, 0], 0)
	pv.draw_points([[40.0, 0.0]], [0, 255, 0], 0)
	var nw: Color = pv.image.get_pixel(0, 0)
	var se: Color = pv.image.get_pixel(7, 7)
	t.eq(nw.r8, 255, "world (0, +z max) is the TOP-LEFT pixel")
	t.eq(nw.g8, 0)
	t.eq(se.g8, 255, "world (+x max, z=0) is the BOTTOM-RIGHT pixel")
	t.eq(se.r8, 0)
	# render_preview wires the same overlay path.
	var pv2: BzRender.Preview = BzRender.render_preview(hm, [[0.0, 40.0]], null, null, Vector2i(8, 8))
	t.ok(pv2.image.get_pixel(0, 0).r8 >= 200, "render_preview draws objects north-up")


func _test_write_thumbnail(t, tmp: String) -> void:
	var data := PackedInt32Array()
	data.resize(16)
	data.fill(1200)
	var img: Image = BzRender.render_heightmap({
		"data": data,
		"grid_x": 4,
		"grid_z": 4,
		"width_m": 20.0,
		"depth_m": 20.0,
	}, Vector2i(4, 4))
	var png: String = tmp.path_join("thumb.png")
	var bmp: String = tmp.path_join("thumb.BMP")
	var wr: Dictionary = BzRender.write_thumbnail(img, png, bmp, Vector2i(32, 32))
	t.eq(wr.get("ok"), true, "write_thumbnail ok")
	t.ok(FileAccess.file_exists(png), "png exists")
	t.ok(FileAccess.file_exists(bmp), "bmp exists")
	var loaded: Image = Image.load_from_file(png)
	t.ok(loaded != null, "png loads")
	t.eq(loaded.get_width(), 32)
	t.eq(loaded.get_height(), 32)
	var bmp_bytes: PackedByteArray = FileAccess.get_file_as_bytes(bmp)
	t.ok(bmp_bytes.size() > 54, "bmp has a header")
	t.eq(bmp_bytes[0], 0x42, "BM magic B")
	t.eq(bmp_bytes[1], 0x4D, "BM magic M")
	t.eq(bmp_bytes.decode_s32(18), 32, "bmp width")
	t.eq(bmp_bytes.decode_s32(22), 32, "bmp height")


func _test_render_session_success(t, tmp: String) -> void:
	var session: String = tmp.path_join("session_ok")
	var out: String = tmp.path_join("thumbs")
	_build_session(session, "xxthmb", true)
	var result: Dictionary = BzRender.render_session(session, out)
	t.eq(result.get("ok"), true, "render_session ok")
	t.eq(result.get("north_up"), true, "north_up flag")
	t.ok(FileAccess.file_exists(str(result.get("png", ""))), "stem.png")
	t.ok(FileAccess.file_exists(str(result.get("bmp", ""))), "stem.BMP")
	t.ok(FileAccess.file_exists(str(result.get("preview", ""))), "preview.png")
	var png: Image = Image.load_from_file(str(result.get("png")))
	t.ok(png != null, "session png loads")
	t.eq(png.get_width(), 512, "workshop thumbnail width")
	t.eq(png.get_height(), 512, "workshop thumbnail height")
	var preview: Image = Image.load_from_file(str(result.get("preview")))
	t.eq(preview.get_width(), 512)
	# Yellow object at world (0, 1280) must sit at the top-left, not bottom.
	var nw: Color = png.get_pixel(1, 1)
	var se: Color = png.get_pixel(500, 500)
	t.ok(nw.r8 > se.r8, "north object marker is at the top of the thumbnail")
	t.ok(nw.g8 > 100, "marker is yellow-ish (255,220,40)")


func _test_render_session_errors(t, tmp: String) -> void:
	var missing: Dictionary = BzRender.render_session(tmp.path_join("nope"), tmp.path_join("out"))
	t.eq(missing.get("ok"), false, "missing session")
	t.eq(str(missing.get("error", {}).get("code", "")), "no_session")
	t.ok(str(missing.get("error", {}).get("message", "")).contains("no manifest.json"))

	var sess: String = tmp.path_join("session_no_terrain")
	DirAccess.make_dir_recursive_absolute(sess)
	_write_json(sess.path_join("manifest.json"), {"contract_version": 1, "stem": "xxnone"})
	var no_ter: Dictionary = BzRender.render_session(sess, tmp.path_join("out2"))
	t.eq(no_ter.get("ok"), false, "missing hg2 header")
	t.eq(str(no_ter.get("error", {}).get("code", "")), "no_terrain")


func _test_render_preview_regions(t, tmp: String) -> void:
	var data := PackedInt32Array()
	data.resize(16)
	data.fill(1000)
	var hm := {
		"data": data,
		"grid_x": 4,
		"grid_z": 4,
		"width_m": 20.0,
		"depth_m": 20.0,
	}
	var mask := PackedByteArray()
	mask.resize(16)
	mask[15] = 1 # x=3, z=3 (north-east cell) — after flip, top-right.
	var pv: BzRender.Preview = BzRender.render_preview(
		hm, null, null, [mask], Vector2i(4, 4)
	)
	var path: String = tmp.path_join("regions.png")
	var wr: Dictionary = pv.save(path)
	t.eq(wr.get("ok"), true, "preview.save")
	t.ok(FileAccess.file_exists(path))
	# Default region tint is green; top-right cell should pick it up.
	var c: Color = pv.image.get_pixel(3, 0)
	t.ok(c.g8 > c.r8, "water/region tint is north-up (NE mask at top-right)")


func _build_session(session: String, stem: String, with_north_feature: bool) -> void:
	var residue: String = session.path_join("residue")
	var src: String = residue.path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	DirAccess.make_dir_recursive_absolute(session.path_join("masks"))
	var data := PackedInt32Array()
	data.resize(BzHg2.ZONE_SIZE * BzHg2.ZONE_SIZE)
	data.fill(800)
	if with_north_feature:
		# High plateau along the north edge, west side.
		for z in range(BzHg2.ZONE_SIZE - 16, BzHg2.ZONE_SIZE):
			for x in range(0, 16):
				data[z * BzHg2.ZONE_SIZE + x] = 4000
	var hm := BzHg2.HeightMap.new(1, 1, data, 1, 8, 10, 0)
	_write_r16(session.path_join("terrain.r16"), data)
	_write_json(residue.path_join("hg2_header.json"), {
		"zonesX": 1,
		"zonesZ": 1,
		"version": 1,
		"depth": 8,
		"unknownA": 10,
		"unknownB": 0,
	})
	_write_json(session.path_join("manifest.json"), {
		"contract_version": 1,
		"stem": stem,
		"world": "mars",
		"width_m": 1280,
		"depth_m": 1280,
		"grid_x": 256,
		"grid_z": 256,
		"cell_m": 5.0,
		"height_scale": 0.1,
		"height_max_raw": 4095,
		"variants": [""],
	})
	_write_json(session.path_join("dirty.json"), {
		"terrain": false,
		"materials": false,
		"objects": {"": []},
		"features": false,
		"meta": [],
	})
	_write_json(session.path_join("objects.json"), {
		"": [{
			"id": "obj-0001",
			"origin": "source",
			"prjid": "pspwn_1",
			"x": 0.0,
			"y": 100.0,
			"z": 1280.0,
			"yaw_deg": 0.0,
			"team": 0,
		}],
	})
	hm.write(src.path_join("%s.hg2" % stem))
	_write_text(src.path_join("%s.trn" % stem), "[Size]\nMinLevel=1\nMaxLevel=1\n")
	_write_text(src.path_join("%s.bzn" % stem), "[GameObject]\nPrjID [1] =\npspwn_1\n  x [1] =\n0\n  z [1] =\n1280\n")


func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


func _write_json(path: String, payload: Variant) -> void:
	var text: String = JSON.stringify(payload, "  ")
	if not text.ends_with("\n"):
		text += "\n"
	_write_text(path, text)


func _write_r16(path: String, data: PackedInt32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_u16(i * 2, data[i] & 0x1FFF)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()


func _write_text(path: String, text: String) -> void:
	var parent: String = path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _tmp_dir(name: String) -> String:
	var d: String = OS.get_temp_dir().path_join("%s_%d" % [name, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(d)
	return d
