extends RefCounted
## HeightField GPU path: RF bytes + coalesced flush match a full rebuild.


func run(t) -> void:
	var field := HeightField.new()
	field.grid_x = 8
	field.grid_z = 8
	field.heights.resize(64)
	field.heights.fill(100)
	field.upload_rect(0, 0, 8, 8)
	t.ok(field.image != null, "first upload builds the RF image")
	t.near(field.image.get_pixel(2, 3).r, 10.0, 0.001, "raw 100 → 10 m")

	field.heights[3 * 8 + 2] = 250
	field.upload_rect(2, 3, 1, 1)
	field.flush_upload()
	t.ok(field.last_uploaded > 0, "flush reports dirty bytes")
	t.near(field.image.get_pixel(2, 3).r, 25.0, 0.001, "dirty cell after flush")
	t.near(field.image.get_pixel(0, 0).r, 10.0, 0.001, "untouched cell stays")

	field.flush_upload()
	t.eq(field.last_uploaded, 0, "second flush is a no-op")

	var tmp := OS.get_temp_dir().path_join("bz_hf_%d.r16" % Time.get_ticks_usec())
	t.eq(field.write_r16(tmp), OK, "write_r16")
	var loaded := HeightField.new()
	t.eq(loaded.load_r16(tmp, 8, 8), OK, "load_r16")
	t.eq(loaded.heights[3 * 8 + 2], 250, "bulk r16 round-trip")
	t.eq(loaded.heights[0], 100)
	t.near(loaded.image.get_pixel(2, 3).r, 25.0, 0.001, "loaded texture matches")
	DirAccess.remove_absolute(tmp)

	var values := PackedInt32Array([400])
	loaded.write_rect(1, 1, 1, 1, values)
	t.eq(loaded.heights[1 * 8 + 1], 400, "write_rect mutates")
	t.near(loaded.image.get_pixel(1, 1).r, 40.0, 0.001, "write_rect flushes immediately")
