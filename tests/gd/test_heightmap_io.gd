extends RefCounted
## CRC32 / Adler-32 vectors, 16-bit PNG encode, export→import bit-exact
## round-trip, 8-bit import scaling, size-mismatch refusal, undo.


func run(t) -> void:
	_test_checksums(t)
	_test_png_header_and_godot_downconvert(t)
	_test_round_trip_all_raw(t)
	_test_filters(t)
	_test_8bit_import(t)
	_test_size_mismatch(t)
	_test_sidecar_and_files(t)
	_test_import_command_undo(t)
	_test_session_io_mismatch_log(t)


func _test_checksums(t) -> void:
	t.eq(HeightmapIO.crc32(PackedByteArray()), 0x00000000, "CRC32 empty")
	t.eq(HeightmapIO.crc32("123456789".to_utf8_buffer()), 0xCBF43926, "CRC32 123456789")
	t.eq(
		HeightmapIO.crc32("The quick brown fox jumps over the lazy dog".to_utf8_buffer()),
		0x414FA339,
		"CRC32 fox",
	)
	t.eq(HeightmapIO.adler32(PackedByteArray()), 0x00000001, "Adler32 empty")
	t.eq(HeightmapIO.adler32("123456789".to_utf8_buffer()), 0x091E01DE, "Adler32 123456789")
	t.eq(HeightmapIO.adler32("Wikipedia".to_utf8_buffer()), 0x11E60398, "Adler32 Wikipedia")


func _test_png_header_and_godot_downconvert(t) -> void:
	var heights := PackedInt32Array([0, 1, 4095, 256])
	var png := HeightmapIO.encode_gray16_png(2, 2, heights)
	t.ok(png.size() > 33, "encoded a PNG")
	t.eq(png[0], 0x89, "PNG signature")
	t.eq(png[1], 0x50)
	t.eq(png[24], 16, "IHDR bit depth 16")
	t.eq(png[25], 0, "IHDR color type 0")
	var idat := _find_chunk(png, "IDAT")
	t.ok(idat.size() >= 6, "has IDAT")
	t.eq(idat[0], 0x78, "IDAT zlib CMF")
	t.eq(idat[1], 0x9C, "IDAT zlib FLG")
	var img := Image.new()
	var err: Error = img.load_png_from_buffer(png)
	t.eq(err, OK, "Godot can open the 16-bit PNG")
	t.eq(img.get_format(), Image.FORMAT_L8, "Godot downconverts 16-bit gray to L8")
	# High byte of (1 << 4) = 16 is 0; high byte of (4095 << 4) = 65520 is 255.
	t.eq(img.get_pixel(1, 0).r8, 0, "lossy: raw 1 becomes 8-bit 0")
	t.eq(img.get_pixel(0, 1).r8, 255, "lossy: raw 4095 becomes 8-bit 255")


func _test_round_trip_all_raw(t) -> void:
	var gx := 64
	var gz := 64
	var n := gx * gz
	var heights := PackedInt32Array()
	heights.resize(n)
	for i in n:
		heights[i] = (i % 4095) + 1
	var png := HeightmapIO.encode_gray16_png(gx, gz, heights)
	var decoded := HeightmapIO.decode_png(png)
	t.ok(bool(decoded.get("ok", false)), "decode ok")
	t.eq(int(decoded["grid_x"]), gx)
	t.eq(int(decoded["grid_z"]), gz)
	t.eq(int(decoded["bit_depth"]), 16)
	var got: PackedInt32Array = decoded["heights"]
	t.eq(got.size(), n, "decoded cell count")
	var mismatch := -1
	for i in n:
		if int(got[i]) != int(heights[i]):
			mismatch = i
			break
	t.eq(mismatch, -1, "export→import is bit-exact for raw 1..4095")
	t.eq(HeightmapIO.raw_to_sample16(4095), 65520, "4095 << 4 = 65520")
	t.eq(HeightmapIO.sample16_to_raw(65520), 4095)
	t.eq(HeightmapIO.sample16_to_raw(0), 1, "sample 0 clamps to 1")
	t.eq(HeightmapIO.sample16_to_raw(65535), 4095, "0xFFFF >> 4 clamps to 4095")


func _test_filters(t) -> void:
	var heights := PackedInt32Array([12, 80, 400, 2000, 4095, 1])
	for filt in range(0, 5):
		var png := HeightmapIO.encode_gray16_png(3, 2, heights, filt)
		var decoded := HeightmapIO.decode_png(png)
		t.ok(bool(decoded.get("ok", false)), "filter %d decodes" % filt)
		t.eq(decoded["heights"], heights, "filter %d reconstructs" % filt)


func _test_8bit_import(t) -> void:
	var img := Image.create_empty(2, 2, false, Image.FORMAT_L8)
	img.set_pixel(0, 0, Color8(0, 0, 0))
	img.set_pixel(1, 0, Color8(1, 1, 1))
	img.set_pixel(0, 1, Color8(128, 128, 128))
	img.set_pixel(1, 1, Color8(255, 255, 255))
	var png: PackedByteArray = img.save_png_to_buffer()
	t.eq(png[24], 8, "Godot 8-bit PNG")
	var decoded := HeightmapIO.decode_png(png)
	t.ok(bool(decoded.get("ok", false)), "8-bit decode ok")
	t.eq(int(decoded["bit_depth"]), 8)
	var got: PackedInt32Array = decoded["heights"]
	t.eq(int(got[0]), 1, "8-bit 0 → raw 1")
	t.eq(int(got[1]), HeightmapIO.sample8_to_raw(1), "8-bit 1 scales")
	t.eq(int(got[2]), HeightmapIO.sample8_to_raw(128), "8-bit 128 scales")
	t.eq(int(got[3]), 4095, "8-bit 255 → raw 4095")
	t.ok(int(got[2]) > 2000 and int(got[2]) < 2200, "mid gray lands near mid height")


func _test_size_mismatch(t) -> void:
	var png := HeightmapIO.encode_gray16_png(2, 3, PackedInt32Array([1, 2, 3, 4, 5, 6]))
	var tmp := OS.get_temp_dir().path_join("bz_hmap_mismatch_%d.png" % Time.get_ticks_usec())
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_buffer(png)
	f.close()
	var decoded := HeightmapIO.import_png_file(tmp, 4, 4)
	t.ok(not bool(decoded.get("ok", false)), "size mismatch refused")
	var msg := str(decoded.get("message", ""))
	t.ok("2x3" in msg, "message names PNG size")
	t.ok("4x4" in msg, "message names map size")
	DirAccess.remove_absolute(tmp)


func _test_sidecar_and_files(t) -> void:
	var field := HeightField.new()
	field.grid_x = 3
	field.grid_z = 2
	field.heights = PackedInt32Array([1, 16, 256, 1024, 2048, 4095])
	var tmp := OS.get_temp_dir().path_join("bz_hmap_export_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var result := HeightmapIO.export_to_dir(tmp, "xtest", field)
	t.ok(bool(result.get("ok", false)), "export_to_dir ok")
	var png_path := str(result.get("png", ""))
	var txt_path := str(result.get("txt", ""))
	t.eq(png_path.get_file(), "xtest-heightmap.png")
	t.eq(txt_path.get_file(), "xtest-heightmap.txt")
	t.ok(FileAccess.file_exists(png_path))
	t.ok(FileAccess.file_exists(txt_path))
	var txt := FileAccess.get_file_as_string(txt_path)
	t.ok("grid_x=3" in txt)
	t.ok("grid_z=2" in txt)
	t.ok("raw << 4" in txt)
	var loaded := HeightmapIO.import_png_file(png_path, 3, 2)
	t.ok(bool(loaded.get("ok", false)))
	t.eq(loaded["heights"], field.heights)
	DirAccess.remove_absolute(png_path)
	DirAccess.remove_absolute(txt_path)
	DirAccess.remove_absolute(tmp)


func _test_import_command_undo(t) -> void:
	var saved_field = MapState.field
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_session := MapState.has_session
	var saved_dirty: Dictionary = MapState.dirty.duplicate(true)
	var field := HeightField.new()
	field.grid_x = 8
	field.grid_z = 8
	field.heights.resize(64)
	field.heights.fill(200)
	MapState.field = field
	MapState.has_session = true
	MapState.dirty = {}
	MapState.objects = {
		"": [{"id": "obj-1", "x": 10.0, "y": 20.0, "z": 10.0, "pinned_y": false}],
	}
	var after := field.heights.duplicate()
	# Cell (2,2) sits under the object at (10, 10) m.
	after[2 * 8 + 2] = 800
	after[2 * 8 + 3] = 800
	var cmd := HeightmapImportCommand.new()
	cmd.setup(field.heights.duplicate(), after)
	cmd.snaps_before = HeightmapImportCommand.capture_ys()
	UndoStack.clear()
	MapState.mark_saved()
	UndoStack.push(cmd)
	t.eq(int(field.heights[2 * 8 + 2]), 800, "import applied")
	t.eq(int(field.heights[2 * 8 + 3]), 800)
	t.eq(MapState.dirty.get("terrain"), true)
	t.ok(MapState.unsaved, "import dirties via undo stack")
	var y_after := float(MapState.objects[""][0]["y"])
	t.ok(absf(y_after - 20.0) > 0.001, "objects re-snapped")
	UndoStack.undo()
	t.eq(int(field.heights[2 * 8 + 2]), 200, "undo restores heights")
	t.eq(int(field.heights[2 * 8 + 3]), 200)
	t.near(float(MapState.objects[""][0]["y"]), 20.0, 0.001, "undo restores object y")
	UndoStack.redo()
	t.eq(int(field.heights[2 * 8 + 2]), 800, "redo re-applies")
	t.near(float(MapState.objects[""][0]["y"]), y_after, 0.001)
	UndoStack.undo()
	UndoStack.clear()
	MapState.field = saved_field
	MapState.objects = saved_objects
	MapState.has_session = saved_session
	MapState.dirty = saved_dirty
	if saved_session:
		MapState.mark_saved()


func _test_session_io_mismatch_log(t) -> void:
	var saved_field = MapState.field
	var saved_session := MapState.has_session
	var field := HeightField.new()
	field.grid_x = 4
	field.grid_z = 4
	field.heights.resize(16)
	field.heights.fill(100)
	MapState.field = field
	MapState.has_session = true
	var png := HeightmapIO.encode_gray16_png(2, 2, PackedInt32Array([10, 20, 30, 40]))
	var tmp := OS.get_temp_dir().path_join("bz_hmap_sess_%d.png" % Time.get_ticks_usec())
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_buffer(png)
	f.close()
	var logs: Array = []
	var io := SessionIO.new(Node.new(), func(msg): logs.append(str(msg)))
	io.import_heightmap(tmp)
	t.ok(not logs.is_empty(), "mismatch is logged")
	t.ok("2x2" in logs[logs.size() - 1], "log names PNG size")
	t.ok("4x4" in logs[logs.size() - 1], "log names map size")
	t.eq(int(field.heights[0]), 100, "refused import does not write")
	DirAccess.remove_absolute(tmp)
	MapState.field = saved_field
	MapState.has_session = saved_session


func _find_chunk(png: PackedByteArray, want: String) -> PackedByteArray:
	var pos := 8
	while pos + 12 <= png.size():
		var length := (int(png[pos]) << 24) | (int(png[pos + 1]) << 16) | (int(png[pos + 2]) << 8) | int(png[pos + 3])
		var typ := png.slice(pos + 4, pos + 8).get_string_from_ascii()
		if typ == want:
			return png.slice(pos + 8, pos + 8 + length)
		pos += 12 + length
	return PackedByteArray()
