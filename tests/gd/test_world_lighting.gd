extends RefCounted
## Sun clock + fog: the TRN model, the .act palette, the save path, the panel.


func run(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz_world_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_test_clock(t)
	_test_sun_arc(t)
	_test_fog_rules(t)
	_test_act(t, tmp)
	_test_save_writes_trn(t, tmp)
	_test_save_untouched_without_flag(t, tmp)
	await _test_panel(t)
	_rm_rf(tmp)


func _test_clock(t) -> void:
	t.eq(WorldLighting.minutes_from_time(900), 540, "Time=900 is 09:00")
	t.eq(WorldLighting.minutes_from_time("0900"), 540, "zero-padded string")
	t.eq(WorldLighting.minutes_from_time(" 1100 "), 660, "whitespace")
	t.eq(WorldLighting.minutes_from_time(0), 0, "midnight")
	t.eq(WorldLighting.minutes_from_time(2345), 23 * 60 + 45)
	t.eq(WorldLighting.minutes_from_time(""), 540, "empty falls back to the default")
	t.eq(WorldLighting.time_from_minutes(540), 900, "round trip")
	t.eq(WorldLighting.time_from_minutes(0), 0)
	t.eq(WorldLighting.time_from_minutes(23 * 60 + 45), 2345)
	t.eq(WorldLighting.format_clock(540), "09:00")
	t.eq(WorldLighting.format_clock(0), "00:00")
	t.eq(WorldLighting.TIME_DEFAULT, 900, "the editor's default sun is the game's 900")


func _test_sun_arc(t) -> void:
	# Dawn in the east, noon overhead, dusk in the west. The light points the
	# other way: it is the direction light travels, not the direction to the sun.
	var dawn := WorldLighting.sun_to_light_direction(WorldLighting.DAWN_MIN)
	t.ok(dawn.x < -0.5, "dawn light travels west")
	var noon := WorldLighting.sun_to_light_direction(720)
	t.ok(noon.y < -0.95, "noon light points down")
	var dusk := WorldLighting.sun_to_light_direction(WorldLighting.DUSK_MIN)
	t.ok(dusk.x > 0.5, "dusk light travels east")
	for m in [0, 180, 540, 720, 900, 1080, 1300, 1439]:
		var d := WorldLighting.sun_to_light_direction(m)
		t.near(d.length(), 1.0, 0.0001, "unit direction at %d" % m)
		t.ok(d.y <= -sin(deg_to_rad(WorldLighting.MIN_ELEVATION_DEG)) + 0.0001,
			"sun never lights from below at %d" % m)
	t.near(WorldLighting.sun_elevation_deg(720), 90.0, 0.001, "noon is overhead")
	t.near(WorldLighting.sun_elevation_deg(WorldLighting.DAWN_MIN), 0.0, 0.001, "dawn on the horizon")
	t.ok(WorldLighting.sun_elevation_deg(0) < 0.0, "midnight is below the horizon")
	t.ok(WorldLighting.sun_energy(720) > WorldLighting.sun_energy(0), "noon is brighter than midnight")


func _test_fog_rules(t) -> void:
	var pair := WorldLighting.clamp_fog(400.0, 200.0)
	t.near(pair.x, 200.0, 0.001, "start cannot pass end")
	t.near(pair.y, 200.0, 0.001)
	var wide := WorldLighting.clamp_fog(-50.0, 5000.0)
	t.near(wide.x, 0.0, 0.001, "start clamps at 0")
	t.near(wide.y, 1000.0, 0.001, "end clamps at 1000")
	t.near(WorldLighting.visibility_range(250.0), 300.0, 0.001, "VisibilityRange is FogEnd + 50")
	t.near(WorldLighting.visibility_range(1000.0), 1050.0, 0.001)


func _test_act(t, tmp: String) -> void:
	var base := PackedByteArray()
	base.resize(BzAct.SIZE)
	for i in BzAct.SIZE:
		base[i] = i % 256
	var path: String = tmp.path_join("base.act")
	t.ok(bool(BzAct.write(path, base).get("ok")), "write a 768-byte palette")
	var read: Dictionary = BzAct.read(path)
	t.ok(bool(read.get("ok")), "read it back")
	t.ok((read["palette"] as PackedByteArray) == base, "byte-identical")
	var tinted := BzAct.with_fog(base, Color8(10, 20, 30))
	t.eq(tinted.size(), BzAct.SIZE, "size unchanged")
	t.eq(int(tinted[BzAct.FOG_INDEX * 3]), 10)
	t.eq(int(tinted[BzAct.FOG_INDEX * 3 + 1]), 20)
	t.eq(int(tinted[BzAct.FOG_INDEX * 3 + 2]), 30)
	var untouched := true
	for i in range(3, BzAct.SIZE):
		if tinted[i] != base[i]:
			untouched = false
			break
	t.ok(untouched, "only the fog entry changed")
	t.ok(BzAct.fog_color(tinted).is_equal_approx(Color8(10, 20, 30)), "reads back")
	var short_p: String = tmp.path_join("short.act")
	_write_bytes(short_p, PackedByteArray([1, 2, 3]))
	t.eq(BzAct.read(short_p).get("ok"), false, "a non-768-byte .act is refused")


func _test_save_writes_trn(t, tmp: String) -> void:
	var sess: String = tmp.path_join("world_sess")
	var src: String = sess.path_join("residue").path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	_write_json(sess.path_join("manifest.json"), {
		"contract_version": 1, "stem": "wsun", "variants": [""],
		"mat_grid_x": 64, "mat_grid_z": 64,
	})
	_write_json(sess.path_join("dirty.json"), {
		"terrain": false, "materials": false, "objects": {"": []},
		"features": false, "meta": [], "trn": true,
	})
	var base := PackedByteArray()
	base.resize(BzAct.SIZE)
	base.fill(9)
	_write_bytes(src.path_join("wsun.act"), base)
	_write_bytes(src.path_join("wsun.trn"), (
		"[Size]\r\nWidth = 1280\r\nDepth = 1280\r\n\r\n"
		+ "[NormalView]\r\nTime=900\r\nFogStart= 80\r\nFogEnd= 250\r\n"
		+ "FogBreak=40\r\nVisibilityRange=250\r\nIntensity=40\r\n\r\n"
		+ "[Color]\r\nPalette=elysium.act\r\nLuma=elysium.lum\r\n"
	).to_utf8_buffer())
	_write_bytes(src.path_join("wsun.bzn"), "version [1] =\r\n2016\r\n".to_utf8_buffer())
	_write_json(sess.path_join("meta.json"), {
		"trn": {"Color": {"Palette": "elysium.act"}},
		"world": {
			"time": 1730,
			"fog_start_m": 120.0,
			"fog_end_m": 640.0,
			"fog_break_m": 55.0,
			"fog_color": "204080",
		},
	})
	var out_dir: String = tmp.path_join("world_out")
	var saved: Dictionary = BzSave.save_session(sess, out_dir)
	t.eq(saved.get("ok"), true, "save ok")
	var text: String = FileAccess.get_file_as_string(out_dir.path_join("wsun.trn"))
	t.ok(text.contains("Time = 1730"), "Time written: %s" % text)
	t.ok(text.contains("FogStart = 120"), "FogStart written")
	t.ok(text.contains("FogEnd = 640"), "FogEnd written")
	t.ok(text.contains("FogBreak = 55"), "FogBreak written")
	t.ok(text.contains("VisibilityRange = 690"), "VisibilityRange is FogEnd + 50")
	t.ok(text.contains("Intensity=40"), "untouched keys keep their own formatting")
	t.ok(text.contains("Luma=elysium.lum"), "the rest of [Color] survives")
	t.ok(text.contains("Palette = wsun.act"), "[Color] Palette points at the map's own .act")
	var act_path: String = out_dir.path_join("wsun.act")
	t.ok(FileAccess.file_exists(act_path), "the .act was written")
	var wrote: Dictionary = BzAct.read(act_path)
	t.ok(bool(wrote.get("ok")), "and it is a valid palette")
	t.ok(BzAct.fog_color(wrote["palette"]).is_equal_approx(Color("204080")), "carrying the fog colour")
	t.eq(int((wrote["palette"] as PackedByteArray)[3]), 9, "every other entry is the base palette")
	t.ok((saved.get("regenerated", []) as Array).has("wsun.trn"), "trn reported as regenerated")
	t.ok((saved.get("regenerated", []) as Array).has("wsun.act"), "act reported as regenerated")


func _test_save_untouched_without_flag(t, tmp: String) -> void:
	## The world step must not touch a file it was not asked to: no `trn` flag,
	## no rewrite, and open→save stays byte-identical.
	var sess: String = tmp.path_join("world_clean")
	var src: String = sess.path_join("residue").path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	_write_json(sess.path_join("manifest.json"), {
		"contract_version": 1, "stem": "wclean", "variants": [""],
		"mat_grid_x": 64, "mat_grid_z": 64,
	})
	_write_json(sess.path_join("dirty.json"), {
		"terrain": false, "materials": false, "objects": {"": []},
		"features": false, "meta": [], "trn": false,
	})
	_write_bytes(src.path_join("wclean.trn"), "[NormalView]\r\nTime=1200\r\n".to_utf8_buffer())
	_write_bytes(src.path_join("wclean.bzn"), "version [1] =\r\n2016\r\n".to_utf8_buffer())
	_write_json(sess.path_join("meta.json"), {"world": {"time": 300}})
	var out_dir: String = tmp.path_join("world_clean_out")
	var saved: Dictionary = BzSave.save_session(sess, out_dir)
	t.eq(saved.get("ok"), true)
	t.ok(_same_bytes(src.path_join("wclean.trn"), out_dir.path_join("wclean.trn")),
		"clean .trn ships byte-identical")
	t.ok(not (saved.get("regenerated", []) as Array).has("wclean.trn"))
	t.ok(not FileAccess.file_exists(out_dir.path_join("wclean.act")), "no .act invented")


func _test_panel(t) -> void:
	var panel: Node = load("res://project/ui/world/WorldPanel.tscn").instantiate()
	t.tree.root.add_child(panel)
	await t.tree.process_frame
	var time_slider: HSlider = panel.find_child("SunTime", true, false)
	t.ok(time_slider != null, "sun time slider")
	t.eq(time_slider.max_value, float(WorldLighting.MINUTES_PER_DAY - 1))
	var start_spin: SpinBox = panel.find_child("FogStart", true, false)
	var end_spin: SpinBox = panel.find_child("FogEnd", true, false)
	var break_spin: SpinBox = panel.find_child("FogBreak", true, false)
	t.ok(start_spin != null and end_spin != null and break_spin != null, "fog distance fields")
	t.eq(start_spin.max_value, WorldLighting.FOG_MAX_M, "fog range tops out at 1000 m")
	t.eq(start_spin.min_value, WorldLighting.FOG_MIN_M)
	t.ok(panel.find_child("FogColor", true, false) is ColorPickerButton, "fog colour picker")
	var show_fog: CheckBox = panel.find_child("ShowFog", true, false)
	t.ok(show_fog != null, "fog visibility checkbox")
	t.ok(panel.find_child("VisibilityNote", true, false) is Label, "visibility readout")
	panel.queue_free()
	await t.tree.process_frame


func _write_json(path: String, payload: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(payload, "  ") + "\n")
	f.close()


func _write_bytes(path: String, buf: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(buf)
	f.close()


func _same_bytes(a: String, b: String) -> bool:
	return FileAccess.get_file_as_bytes(a) == FileAccess.get_file_as_bytes(b)


func _rm_rf(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.include_hidden = true
	da.include_navigational = false
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		var child: String = path.path_join(fn)
		if da.current_is_dir():
			_rm_rf(child)
		else:
			DirAccess.remove_absolute(child)
		fn = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)
