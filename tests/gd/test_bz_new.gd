extends RefCounted
## BzNew: stem/world/dimension errors + synthetic-game create_map.


func run(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz_new_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var game: String = _make_game(tmp)
	_test_errors(t, tmp, game)
	_test_success(t, tmp, game)
	_test_non_square_mat_shape(t, tmp, game)
	_rm_rf(tmp)


## "legal sizes are 1280, 2560, 3840, 5120; non-square is allowed" — and the
## New dialog has separate width and depth pickers, so this is a route users
## have. create_map bakes the .mat and then reads it straight back in; read
## without the companion zone counts, a 1x3-zone map's 12288 tile words are
## guessed from their closest factor pair as 96x128 and the grid comes back
## transposed.
func _test_non_square_mat_shape(t, tmp: String, game: String) -> void:
	var sess: String = tmp.path_join("ntall")
	var created: Dictionary = BzNew.create_map("xxedtall", "mars", 1280, 3840, sess, game, 1000, "bzp")
	t.eq(created.get("ok"), true, "non-square create_map ok")
	if created.get("ok") != true:
		t.fail("create_map failed: %s" % str(created))
		return
	var manifest: Dictionary = created.get("manifest", {})
	t.eq(manifest.get("width_m"), 1280, "width")
	t.eq(manifest.get("depth_m"), 3840, "depth")
	t.eq(manifest.get("grid_x"), 256, "grid_x")
	t.eq(manifest.get("grid_z"), 768, "grid_z")
	# 1x3 zones at 64 tiles a zone. The factor-pair guess would say 128x96.
	t.eq(manifest.get("mat_grid_x"), 64, "mat grid is 1 zone wide, not the factor-pair guess")
	t.eq(manifest.get("mat_grid_z"), 192, "mat grid is 3 zones deep")
	var mats: PackedByteArray = FileAccess.get_file_as_bytes(sess.path_join("materials.u16"))
	t.eq(mats.size(), 64 * 192 * 2, "materials.u16 holds one word per tile")


func _make_game(tmp: String) -> String:
	var game: String = tmp.path_join("game")
	var trn_dir: String = game.path_join("Edit").path_join("trn")
	DirAccess.make_dir_recursive_absolute(trn_dir)
	_write_text(
		trn_dir.path_join("mars.trn"),
		"[Size]\r\nMinX = 9\r\nMinZ = 9\r\nHeight = 20\r\nWidth = 1280\r\nDepth = 1280\r\n"
		+ "[Atlases]\r\nMaterialName = mars_detail_atlas\r\n"
		+ "[Sky]\r\nSkyTexture = mars.map\r\n"
		+ "[World]\r\nFoo = bar\r\n"
		+ "[NormalView]\r\nNV = 1\r\n"
		+ "[TextureType0] // Sandy\r\nFlatColor = 140 90 60\r\n"
	)
	return game


func _test_errors(t, tmp: String, game: String) -> void:
	var too_long: Dictionary = BzNew.create_map("toolongxx", "mars", 1280, 1280, tmp.path_join("n1"), game)
	t.ok(BzErrors.is_err(too_long))
	t.eq(too_long["error"].get("code"), "stem_too_long")
	t.eq(too_long["error"].get("hint"), "use a stem of 8 characters or fewer")
	t.ok(str(too_long["error"].get("message", "")).contains("'toolongxx'"))

	var bad: Dictionary = BzNew.create_map("bad stem", "mars", 1280, 1280, tmp.path_join("n2"), game)
	t.ok(BzErrors.is_err(bad))
	t.eq(bad["error"].get("code"), "bad_stem")

	var empty_stem: Dictionary = BzNew.create_map("", "mars", 1280, 1280, tmp.path_join("n2b"), game)
	t.ok(BzErrors.is_err(empty_stem))
	t.eq(empty_stem["error"].get("code"), "bad_stem")

	var disc: Variant = load("res://project/backend/editor/BzDiscover.gd")
	var first_root: String = ""
	if disc != null and disc.has_method("first_game_root"):
		first_root = str(disc.call("first_game_root"))
	if first_root.is_empty():
		var nogame: Dictionary = BzNew.create_map("okstem", "mars", 1280, 1280, tmp.path_join("n3"), "")
		t.ok(BzErrors.is_err(nogame), "no_game: %s" % str(nogame))
		if BzErrors.is_err(nogame):
			t.eq(nogame["error"].get("code"), "no_game")
	else:
		t.ok(true, "no_game skipped: a game install is discoverable (Python same)")

	var collide: Dictionary = BzNew.create_map("mars", "mars", 1280, 1280, tmp.path_join("n4"), game)
	t.ok(BzErrors.is_err(collide))
	t.eq(collide["error"].get("code"), "stem_collision")

	var unknown: Dictionary = BzNew.create_map("okstem", "pluto", 1280, 1280, tmp.path_join("n5"), game)
	t.ok(BzErrors.is_err(unknown))
	t.eq(unknown["error"].get("code"), "unknown_world")
	t.ok(str(unknown["error"].get("hint", "")).contains("mars"))

	var dims: Dictionary = BzNew.create_map("okstem", "mars", 1000, 1280, tmp.path_join("n6"), game)
	t.ok(BzErrors.is_err(dims))
	t.eq(dims["error"].get("code"), "bad_dimensions")
	t.eq(dims["error"].get("hint"), "legal sizes are 1280, 2560, 3840, 5120; non-square is allowed")

	var height: Dictionary = BzNew.create_map("okstem", "mars", 1280, 1280, tmp.path_join("n7"), game, 0)
	t.ok(BzErrors.is_err(height))
	t.eq(height["error"].get("code"), "bad_base_height")

	var height_hi: Dictionary = BzNew.create_map("okstem", "mars", 1280, 1280, tmp.path_join("n7b"), game, 4096)
	t.ok(BzErrors.is_err(height_hi))
	t.eq(height_hi["error"].get("code"), "bad_base_height")

	# io is a stock world id but this synthetic install has no io.trn.
	var notpl: Dictionary = BzNew.create_map("okstem", "io", 1280, 1280, tmp.path_join("n8"), game)
	t.ok(BzErrors.is_err(notpl), "no_world_template: %s" % str(notpl))
	if BzErrors.is_err(notpl):
		t.eq(notpl["error"].get("code"), "no_world_template")


func _test_success(t, tmp: String, game: String) -> void:
	var sess: String = tmp.path_join("nsuccess")
	var created: Dictionary = BzNew.create_map("xxedtest", "mars", 1280, 1280, sess, game, 1000, "bzp")
	t.eq(created.get("ok"), true, "create_map ok")
	if created.get("ok") != true:
		t.fail("create_map failed: %s" % str(created))
		return
	var manifest: Dictionary = created.get("manifest", {})
	t.eq(manifest.get("stem"), "xxedtest")
	t.eq(manifest.get("source_path"), "", "new maps have empty source_path")
	t.eq(manifest.get("world"), "mars")
	t.eq(manifest.get("width_m"), 1280)
	t.eq(manifest.get("depth_m"), 1280)
	t.eq(manifest.get("grid_x"), 256)
	t.eq(manifest.get("grid_z"), 256)
	t.eq(manifest.get("cell_m"), 5.0)
	t.eq(manifest.get("height_scale"), 0.1)
	t.eq(manifest.get("height_max_raw"), 4095)
	t.eq(manifest.get("mat_grid_x"), 64)
	t.eq(manifest.get("mat_grid_z"), 64)
	t.eq(manifest.get("has_lightmap"), true)
	t.eq(manifest.get("pack_context"), {"kind": "bzp"})
	t.eq(manifest.get("contract_version"), 1)
	t.ok(created.has("warnings"), "open-map payload has warnings")
	t.ok(created.has("session"), "open-map payload has session")

	var paths: Dictionary = {
		"terrain": sess.path_join("terrain.r16"),
		"materials": sess.path_join("materials.u16"),
		"manifest": sess.path_join("manifest.json"),
		"dirty": sess.path_join("dirty.json"),
		"source": sess.path_join("residue").path_join("source"),
	}
	t.ok(FileAccess.file_exists(str(paths["terrain"])), "terrain.r16")
	t.ok(FileAccess.file_exists(str(paths["materials"])), "materials.u16")
	t.ok(FileAccess.file_exists(str(paths["manifest"])))
	t.ok(FileAccess.file_exists(str(paths["dirty"])))
	var r16: PackedByteArray = FileAccess.get_file_as_bytes(str(paths["terrain"]))
	t.eq(r16.size(), 256 * 256 * 2)
	t.eq(r16.decode_u16(0), 1000, "flat plateau at base_height")
	t.eq(r16.decode_u16(100 * 2), 1000)

	var src: String = str(paths["source"])
	for name in ["xxedtest.hg2", "xxedtest.mat", "xxedtest.trn", "xxedtest.ini", "xxedtest.des", "xxedtest.odf", "xxedtest.vxt", "xxedtest.lgt"]:
		t.ok(FileAccess.file_exists(src.path_join(name)), "residue has %s" % name)

	# [Size] rewritten to standalone origin + requested dimensions (Python write_complete_trn).
	var trn_text: String = FileAccess.get_file_as_string(src.path_join("xxedtest.trn"))
	t.ok(trn_text.contains("Width = 1280"))
	t.ok(trn_text.contains("Depth = 1280"))
	t.ok(trn_text.contains("MinX = 0"))
	t.ok(trn_text.contains("MinZ = 0"))
	t.ok(trn_text.contains("Height = 0.000000"))
	t.ok(trn_text.contains("Foo = bar"), "World section copied from template")
	t.ok(trn_text.contains("NV = 1"), "NormalView copied (not overridden)")

	var ini: String = FileAccess.get_file_as_string(src.path_join("xxedtest.ini"))
	t.ok(ini.contains('missionName = "xxedtest"'))
	var des: String = FileAccess.get_file_as_string(src.path_join("xxedtest.des"))
	t.ok(des.contains("WORLD: Mars"))
	t.ok(des.contains("GEYSERS: 0"))
	t.ok(des.contains("Made by Skippy"))

	var lgt: PackedByteArray = FileAccess.get_file_as_bytes(src.path_join("xxedtest.lgt"))
	t.eq(lgt.size(), 131072)
	t.eq(lgt[0], 56, "plane 0 fill")
	t.eq(lgt[65536], 136, "flat north-light bake")

	# Height/materials/objects stay residue bytes. Save always ships `{stem}.act`
	# and retargets `[Color] Palette` at it, so the .trn may be rewritten.
	var out_dir: String = tmp.path_join("new_out")
	var saved: Dictionary = BzSave.save_session(sess, out_dir)
	t.eq(saved.get("ok"), true, "save after new")
	for name in saved.get("regenerated", []):
		var ext := str(name).get_extension().to_lower()
		t.ok(ext == "trn" or ext == "act", "untouched new-map only rewrites fog palette files")
	var da := DirAccess.open(src)
	t.ok(da != null)
	da.list_dir_begin()
	var fn: String = da.get_next()
	var mismatches: Array = []
	while fn != "":
		if not da.current_is_dir():
			var ext := fn.get_extension().to_lower()
			if ext != "trn" and ext != "act":
				var a: String = src.path_join(fn)
				var b: String = out_dir.path_join(fn)
				if not FileAccess.file_exists(b) or FileAccess.get_file_as_bytes(a) != FileAccess.get_file_as_bytes(b):
					mismatches.append(fn)
		fn = da.get_next()
	da.list_dir_end()
	t.eq(mismatches, [], "non-palette residue files reappear byte-identical")
	t.ok(FileAccess.file_exists(out_dir.path_join("xxedtest.act")), "new-map save ships {stem}.act")

	# pack_kind base omits .odf
	var sess_b: String = tmp.path_join("nbase")
	var created_b: Dictionary = BzNew.create_map("xxbase", "mars", 1280, 1280, sess_b, game, 1000, "base")
	t.eq(created_b.get("ok"), true)
	t.eq((created_b.get("manifest", {}) as Dictionary).get("pack_context"), {"kind": "base"})
	t.ok(not FileAccess.file_exists(sess_b.path_join("residue").path_join("source").path_join("xxbase.odf")), "base maps skip .odf")


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(text.to_utf8_buffer())
	f.close()


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
