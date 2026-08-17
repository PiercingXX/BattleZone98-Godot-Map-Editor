extends RefCounted
## BzPackage: pack/install verbs, safety (mods/ + modEnabled.dat only).


func run(t) -> void:
	var tmp: String = _tmp_dir("bz98_gd_package")
	_test_assemble_pack_success(t, tmp)
	_test_assemble_pack_errors(t, tmp)
	_test_install_helpers(t, tmp)
	_test_package_pack(t, tmp)
	_test_package_install(t, tmp)
	_test_package_errors(t, tmp)
	_test_install_safety(t, tmp)


func _test_assemble_pack_success(t, tmp: String) -> void:
	var src: String = tmp.path_join("stage_ok")
	var dest: String = tmp.path_join("pack_ok")
	DirAccess.make_dir_recursive_absolute(src)
	_write_text(src.path_join("xxpack.trn"), "[Size]\n")
	_write_text(src.path_join("xxpack.bzn"), "[GameObject]\n")
	_write_text(src.path_join("report.json"), "{\"ok\":true}\n")
	var preview := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	preview.fill(Color8(30, 40, 50))
	var result: Dictionary = BzPackage.assemble_pack(src, dest, preview)
	t.eq(result.get("ok"), true, "assemble_pack ok")
	t.ok(FileAccess.file_exists(dest.path_join("xxpack.trn")), "trn copied flat")
	t.ok(FileAccess.file_exists(dest.path_join("xxpack.bzn")), "bzn copied flat")
	t.ok(not FileAccess.file_exists(dest.path_join("report.json")), "non-map files ignored")
	t.ok(FileAccess.file_exists(dest.path_join("preview.png")), "preview.png written")
	var img: Image = Image.load_from_file(dest.path_join("preview.png"))
	t.ok(img != null, "preview loads")
	t.eq(img.get_width(), 512, "workshop preview size")
	t.eq(img.get_height(), 512)


func _test_assemble_pack_errors(t, tmp: String) -> void:
	var empty: String = tmp.path_join("stage_empty")
	DirAccess.make_dir_recursive_absolute(empty)
	var no_maps: Dictionary = BzPackage.assemble_pack(empty, tmp.path_join("pack_empty"))
	t.eq(no_maps.get("ok"), false)
	t.eq(str(no_maps.get("error", {}).get("code", "")), "assemble_error")
	t.ok(str(no_maps.get("error", {}).get("message", "")).contains("no map files"))

	var src: String = tmp.path_join("stage_noprev")
	DirAccess.make_dir_recursive_absolute(src)
	_write_text(src.path_join("xx.trn"), "x")
	var no_prev: Dictionary = BzPackage.assemble_pack(src, tmp.path_join("pack_noprev"))
	t.eq(no_prev.get("ok"), false)
	t.ok(str(no_prev.get("error", {}).get("message", "")).contains("no preview supplied"))


func _test_install_helpers(t, tmp: String) -> void:
	var game: String = tmp.path_join("fake_game_helpers")
	DirAccess.make_dir_recursive_absolute(game)
	t.eq(BzPackage.mod_dir(game, "tid1"), game.path_join("mods").path_join("tid1"))
	t.eq(BzPackage.snapshot_mod_enabled(game), null, "absent snapshot is null")
	var prev: Variant = BzPackage.set_mod_enabled(game, "first")
	t.eq(prev, null)
	var snap: Variant = BzPackage.snapshot_mod_enabled(game)
	t.ok(snap is PackedByteArray, "snapshot is bytes")
	t.eq((snap as PackedByteArray).get_string_from_ascii(), "first")
	BzPackage.set_mod_enabled(game, "second")
	t.eq(
		FileAccess.get_file_as_string(game.path_join(BzPackage.MOD_ENABLED_NAME)),
		"second"
	)
	BzPackage.restore_mod_enabled(game, snap)
	t.eq(
		FileAccess.get_file_as_string(game.path_join(BzPackage.MOD_ENABLED_NAME)),
		"first",
		"restore writes previous bytes"
	)
	BzPackage.restore_mod_enabled(game, null)
	t.ok(
		not FileAccess.file_exists(game.path_join(BzPackage.MOD_ENABLED_NAME)),
		"restore(null) removes the file"
	)

	var src: String = tmp.path_join("one.txt")
	_write_text(src, "hello")
	var inst: Dictionary = BzPackage.install_map(game, "tid1", [src])
	t.eq(inst.get("ok"), true)
	t.ok(FileAccess.file_exists(game.path_join("mods").path_join("tid1").path_join("one.txt")))

	var missing: Dictionary = BzPackage.install_map(game, "tid2", [tmp.path_join("no-such-file.trn")])
	t.eq(missing.get("ok"), false)
	t.eq(str(missing.get("error", {}).get("code", "")), "install_error")
	t.ok(str(missing.get("error", {}).get("message", "")).contains("source file not found"))


func _test_package_pack(t, tmp: String) -> void:
	var session: String = tmp.path_join("sess_pack")
	var out: String = tmp.path_join("pack_out")
	_build_session(session, "xxpack")
	var result: Dictionary = BzPackage.package_session(session, "pack", "", "", out)
	t.eq(result.get("ok"), true, "package pack ok")
	t.eq(result.get("mode"), "pack")
	t.ok(result.has("dest"), "dest path")
	t.ok(result.has("files"), "files list from save")
	t.ok(FileAccess.file_exists(out.path_join("preview.png")), "pack preview.png")
	t.ok(
		FileAccess.file_exists(out.path_join("xxpack.trn"))
		or FileAccess.file_exists(out.path_join("xxpack.png")),
		"pack contains a map file"
	)
	# Flat layout: no nested map dir required.
	t.ok(DirAccess.dir_exists_absolute(out))


func _test_package_install(t, tmp: String) -> void:
	var session: String = tmp.path_join("sess_inst")
	var game: String = tmp.path_join("fake_game_install")
	DirAccess.make_dir_recursive_absolute(game)
	DirAccess.make_dir_recursive_absolute(game.path_join("BZ_ASSETS"))
	_write_text(game.path_join("BZ_ASSETS").path_join("keep.me"), "stock")
	_write_text(game.path_join("modEnabled.dat"), "oldmod")
	_build_session(session, "xxinst")
	var result: Dictionary = BzPackage.package_session(session, "install", game, "", "")
	t.eq(result.get("ok"), true, "package install ok")
	t.eq(result.get("mode"), "install")
	t.eq(result.get("test_id"), "bzeditor-xxinst")
	t.eq(result.get("previous_mod"), "oldmod")
	var dest: String = str(result.get("dest", ""))
	t.ok(dest.contains("mods"), "dest is under mods/")
	t.ok(dest.ends_with("bzeditor-xxinst") or dest.contains("bzeditor-xxinst"))
	t.ok(DirAccess.dir_exists_absolute(dest), "test-mod dir created")
	t.eq(
		FileAccess.get_file_as_string(game.path_join("modEnabled.dat")),
		"bzeditor-xxinst",
		"modEnabled.dat selects the test id"
	)
	t.eq(
		FileAccess.get_file_as_string(game.path_join("BZ_ASSETS").path_join("keep.me")),
		"stock",
		"stock tree is untouched"
	)
	# Custom test-id.
	var again: Dictionary = BzPackage.package_session(session, "install", game, "mytestid", "")
	t.eq(again.get("ok"), true)
	t.eq(again.get("test_id"), "mytestid")
	t.ok(DirAccess.dir_exists_absolute(game.path_join("mods").path_join("mytestid")))


func _test_package_errors(t, tmp: String) -> void:
	var no_sess: Dictionary = BzPackage.package_session(tmp.path_join("missing"), "pack", "", "", tmp)
	t.eq(no_sess.get("ok"), false)
	t.eq(str(no_sess.get("error", {}).get("code", "")), "no_session")

	var session: String = tmp.path_join("sess_err")
	_build_session(session, "xxerr")
	var no_game: Dictionary = BzPackage.package_session(session, "install")
	t.eq(no_game.get("ok"), false)
	t.eq(str(no_game.get("error", {}).get("code", "")), "no_game")
	t.ok(str(no_game.get("error", {}).get("message", "")).contains("--game-root"))

	var no_out: Dictionary = BzPackage.package_session(session, "pack")
	t.eq(no_out.get("ok"), false)
	t.eq(str(no_out.get("error", {}).get("code", "")), "no_out")

	var bad: Dictionary = BzPackage.package_session(session, "explode")
	t.eq(bad.get("ok"), false)
	t.eq(str(bad.get("error", {}).get("code", "")), "bad_mode")
	t.eq(str(bad.get("error", {}).get("hint", "")), "use install, addon, or pack")


func _test_install_safety(t, tmp: String) -> void:
	var game: String = tmp.path_join("fake_game_safe")
	DirAccess.make_dir_recursive_absolute(game.path_join("addon"))
	_write_text(game.path_join("addon").path_join("canary.txt"), "alive")
	var src: String = tmp.path_join("safe.trn")
	_write_text(src, "x")
	var escaped: Dictionary = BzPackage.install_map(game, "../addon", [src])
	t.eq(escaped.get("ok"), false, "path-traversal test_id is refused")
	t.eq(
		FileAccess.get_file_as_string(game.path_join("addon").path_join("canary.txt")),
		"alive",
		"canary outside mods/ is untouched"
	)
	t.ok(not FileAccess.file_exists(game.path_join("addon").path_join("safe.trn")))


func _build_session(session: String, stem: String) -> void:
	var residue: String = session.path_join("residue")
	var src: String = residue.path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	DirAccess.make_dir_recursive_absolute(session.path_join("masks"))
	var data := PackedInt32Array()
	data.resize(BzHg2.ZONE_SIZE * BzHg2.ZONE_SIZE)
	data.fill(1000)
	# Asymmetric north-west peak so a packaged thumbnail is still north-up.
	for z in range(BzHg2.ZONE_SIZE - 8, BzHg2.ZONE_SIZE):
		for x in range(0, 8):
			data[z * BzHg2.ZONE_SIZE + x] = 3500
	var hm := BzHg2.HeightMap.new(1, 1, data, 1, 8, 10, 0)
	_write_r16(session.path_join("terrain.r16"), data)
	_write_json(residue.path_join("hg2_header.json"), {
		"zonesX": 1, "zonesZ": 1, "version": 1, "depth": 8, "unknownA": 10, "unknownB": 0,
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
		"variants": [""],
	})
	_write_json(session.path_join("dirty.json"), {
		"terrain": false,
		"materials": false,
		"objects": {"": []},
		"features": false,
		"meta": [],
	})
	_write_json(session.path_join("objects.json"), {"": []})
	hm.write(src.path_join("%s.hg2" % stem))
	_write_text(src.path_join("%s.trn" % stem), "[Size]\nMinLevel=1\nMaxLevel=1\n")
	_write_text(src.path_join("%s.bzn" % stem), "[GameObject]\n")
	var thumb := Image.create_empty(16, 16, false, Image.FORMAT_RGB8)
	thumb.fill(Color8(20, 30, 40))
	thumb.save_png(src.path_join("preview.png"))


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
	var parent: String = path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
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
