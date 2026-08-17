extends RefCounted
## Synthetic ODFs / textures / meshes — never real game, BZP, or corpus data.


func run(t) -> void:
	var tmp := OS.get_temp_dir().path_join("bz_assets_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	BzDiscover.test_steam_roots = PackedStringArray()
	BzDiscover.test_gog_installs = PackedStringArray()

	_test_no_game(t, tmp)
	_test_build_index(t, tmp)
	_test_pack_override_and_verified(t, tmp)
	_test_fingerprint_cache(t, tmp)
	_test_existing_glb_is_hd(t, tmp)
	_test_convert_synthetic_mesh(t, tmp)

	BzDiscover.test_steam_roots = null
	BzDiscover.test_gog_installs = null
	_rmtree(tmp)


func _test_no_game(t, tmp: String) -> void:
	var cache := tmp.path_join("cache_nogame")
	var missing := BzAssets.build_assets(tmp.path_join("no_such_install"), cache)
	t.ok(BzErrors.is_err(missing), "missing install is an error")
	t.eq(str(missing.get("error", {}).get("code", "")), "no_game", "no_game code")
	t.ok(str(missing.get("error", {}).get("hint", "")).contains("probe"), "hint")

	var empty := BzAssets.build_assets("", cache)
	t.ok(BzErrors.is_err(empty), "empty game_root with no discovered install")
	t.eq(str(empty.get("error", {}).get("code", "")), "no_game")


func _test_build_index(t, tmp: String) -> void:
	var inst := tmp.path_join("game_a")
	_make_install(inst)
	_write_odf(
		inst.path_join("BZ_ASSETS").path_join("odf").path_join("eggeizr1.odf"),
		"geyser",
		{"collisionradius": "8", "width": "16", "length": "16", "height": "8"}
	)
	_write_odf(
		inst.path_join("BZ_ASSETS").path_join("odf").path_join("player.odf"),
		"person",
		{}
	)
	_write_odf(
		inst.path_join("BZ_ASSETS").path_join("odf").path_join("pspwn_1.odf"),
		"spawnbuoy",
		{}
	)
	_write_odf(
		inst.path_join("BZ_ASSETS").path_join("odf").path_join("npscr1.odf"),
		"scrap",
		{}
	)
	_write_odf(
		inst.path_join("BZ_ASSETS").path_join("odf").path_join("avtank.odf"),
		"wingman",
		{"collisionradius": "5"}
	)
	_write_odf(
		inst.path_join("addon").path_join("loose01.odf"),
		"i76building",
		{}
	)
	# Case-insensitive suffix.
	_write_odf(
		inst.path_join("BZ_ASSETS").path_join("odf").path_join("sscr_1.ODF"),
		"scrap",
		{}
	)

	var cache := tmp.path_join("cache_a")
	var pack := tmp.path_join("empty_pack")
	DirAccess.make_dir_recursive_absolute(pack)
	var result := BzAssets.build_assets(inst, cache, [pack], true, false)
	t.eq(result.get("ok"), true, "build ok")
	t.ok(str(result.get("cache_dir", "")).contains("cache_a"), "cache_dir")
	t.ok(str(result.get("source_fingerprint", "")).begins_with("sha256:"), "fingerprint")
	t.ok(str(result.get("generated_at", "")).ends_with("Z"), "generated_at UTC")
	t.ok(result.get("classes") is Array, "classes array")
	t.ok(result.get("unresolved") is Array, "unresolved array")
	t.ok(FileAccess.file_exists(cache.path_join("index.json")), "index.json")

	var by := _by_prjid(result)
	t.ok(by.has("eggeizr1"), "geyser class")
	t.ok(by.has("player"), "player class")
	t.ok(by.has("pspwn_1"), "spawn class")
	t.ok(by.has("npscr1"), "scrap class")
	t.ok(by.has("avtank"), "craft class")
	t.ok(by.has("loose01"), "addon ODF")
	t.ok(by.has("sscr_1"), "case-insensitive .ODF")

	_expect_class(t, by["eggeizr1"], {
		"category": "geyser",
		"template_verified": true,
		"placement_mode": "bzn",
		"source": "game",
		"odf": "eggeizr1.odf",
		"label": "geyser",
		"mesh_fidelity": "proxy",
	})
	t.eq(float(by["eggeizr1"].get("radius_m", 0.0)), 8.0, "geyser radius")
	t.eq((by["eggeizr1"].get("footprint_m", []) as Array).size(), 2, "footprint pair")
	t.eq(float((by["eggeizr1"].get("footprint_m", [0, 0]) as Array)[0]), 16.0)
	t.eq(by["eggeizr1"].get("faction"), null, "e* faction is null")
	t.eq(str(by["eggeizr1"].get("icon", "")), "icons/eggeizr1.png")

	_expect_class(t, by["player"], {
		"category": "craft",
		"template_verified": true,
		"placement_mode": "bzn",
	})
	_expect_class(t, by["pspwn_1"], {
		"category": "spawn",
		"template_verified": true,
	})
	t.eq(by["pspwn_1"].get("faction"), null, "p* faction is null")
	_expect_class(t, by["npscr1"], {"category": "scrap", "template_verified": true})
	_expect_class(t, by["sscr_1"], {"category": "scrap", "template_verified": true})
	_expect_class(t, by["avtank"], {
		"category": "craft",
		"template_verified": false,
		"placement_mode": "runtime",
		"faction": "NSDF",
	})
	_expect_class(t, by["loose01"], {"category": "environment", "source": "game"})

	var icon := Image.new()
	t.eq(icon.load(cache.path_join("icons").path_join("eggeizr1.png")), OK, "icon png")
	t.eq(icon.get_width(), 64, "icon width")
	t.eq(icon.get_height(), 64, "icon height")


func _test_pack_override_and_verified(t, tmp: String) -> void:
	var inst := tmp.path_join("game_b")
	_make_install(inst)
	_write_odf(inst.path_join("BZ_ASSETS").path_join("avtank.odf"), "wingman", {})
	var pack := tmp.path_join("pack_b")
	DirAccess.make_dir_recursive_absolute(pack)
	_write_odf(pack.path_join("avtank.odf"), "hovercraft", {"width": "12"})
	_write_odf(pack.path_join("svtank.odf"), "tank", {})
	_write(
		pack.path_join("synth.bzn"),
		"version [1] =\r\n2016\r\n[GameObject]\r\nPrjID [1] =\r\nsvtank\r\n"
	)

	var cache := tmp.path_join("cache_b")
	var result := BzAssets.build_assets(inst, cache, [pack], true, false)
	t.eq(result.get("ok"), true)
	var by := _by_prjid(result)
	t.ok(by.has("avtank") and by.has("svtank"))
	t.eq(str(by["avtank"].get("source")), pack.get_file(), "pack overrides game prjid")
	t.eq(str(by["avtank"].get("label")), "hovercraft", "pack ODF wins")
	t.eq(str(by["svtank"].get("faction")), "CCA")
	t.eq(by["svtank"].get("template_verified"), true, "PrjID from pack BZN is verified")
	t.eq(str(by["svtank"].get("placement_mode")), "bzn")
	t.eq(by["avtank"].get("template_verified"), false, "unverified pack class stays runtime")


func _test_fingerprint_cache(t, tmp: String) -> void:
	var inst := tmp.path_join("game_c")
	_make_install(inst)
	_write_odf(inst.path_join("BZ_ASSETS").path_join("eggeizr1.odf"), "geyser", {})
	var cache := tmp.path_join("cache_c")
	var pack := tmp.path_join("pack_c")
	DirAccess.make_dir_recursive_absolute(pack)
	var first := BzAssets.build_assets(inst, cache, [pack], true, false)
	t.eq(first.get("ok"), true)
	var fp := str(first.get("source_fingerprint", ""))
	var when := str(first.get("generated_at", ""))
	var again := BzAssets.build_assets(inst, cache, [pack], false, false)
	t.eq(again.get("ok"), true, "cache hit ok")
	t.eq(str(again.get("source_fingerprint")), fp, "same fingerprint")
	t.eq(str(again.get("generated_at")), when, "cache hit keeps generated_at")
	t.eq((again.get("classes", []) as Array).size(), (first.get("classes", []) as Array).size())

	var refreshed := BzAssets.build_assets(inst, cache, [pack], true, false)
	t.eq(refreshed.get("ok"), true)
	t.eq(str(refreshed.get("source_fingerprint")), fp)
	# Rebuild writes a new timestamp (second resolution). Always a valid Z stamp.
	t.ok(str(refreshed.get("generated_at", "")).ends_with("Z"))


func _test_existing_glb_is_hd(t, tmp: String) -> void:
	var inst := tmp.path_join("game_d")
	_make_install(inst)
	_write_odf(inst.path_join("BZ_ASSETS").path_join("eggeizr1.odf"), "geyser", {})
	var cache := tmp.path_join("cache_d")
	DirAccess.make_dir_recursive_absolute(cache.path_join("meshes"))
	var glb := cache.path_join("meshes").path_join("eggeizr1.glb")
	_write(glb, "glTF-not-parsed")
	var pack := tmp.path_join("pack_d")
	DirAccess.make_dir_recursive_absolute(pack)
	var result := BzAssets.build_assets(inst, cache, [pack], true, false)
	var rec: Dictionary = _by_prjid(result).get("eggeizr1", {})
	t.eq(str(rec.get("mesh_fidelity")), "hd", "preexisting glb is hd")
	t.ok(str(rec.get("mesh", "")).ends_with("eggeizr1.glb"), "mesh path")


func _test_convert_synthetic_mesh(t, tmp: String) -> void:
	var inst := tmp.path_join("game_e")
	_make_install(inst)
	_write_odf(inst.path_join("BZ_ASSETS").path_join("avtank.odf"), "tank", {})
	var models := inst.path_join("BZ_ASSETS").path_join("common").path_join("models")
	# Synthetic .geo (not a game asset). BzOgre is a sibling mid-port; the
	# geo_flat rung exercises BzGeo + BzGlb which this module is allowed to call.
	t.ok(_write_synth_geo(models.path_join("avtank.geo")), "synthetic geo written")
	var cache := tmp.path_join("cache_e")
	var pack := tmp.path_join("pack_e")
	DirAccess.make_dir_recursive_absolute(pack)
	var result := BzAssets.build_assets(inst, cache, [pack], true, true)
	t.eq(result.get("ok"), true, "convert build ok")
	var rec: Dictionary = _by_prjid(result).get("avtank", {})
	t.eq(str(rec.get("mesh_fidelity")), "geo_flat", "converted mesh is geo_flat")
	t.ok(FileAccess.file_exists(cache.path_join("meshes").path_join("avtank.glb")), "glb on disk")
	var raw := FileAccess.get_file_as_bytes(cache.path_join("meshes").path_join("avtank.glb"))
	t.ok(raw.size() > 4, "glb has bytes")
	t.eq(raw.slice(0, 4).get_string_from_ascii(), "glTF", "glb magic")


func _expect_class(t, rec: Dictionary, want: Dictionary) -> void:
	for k in want.keys():
		t.eq(rec.get(k), want[k], "class %s.%s" % [rec.get("prjid", "?"), k])


func _by_prjid(result: Dictionary) -> Dictionary:
	var out := {}
	for rec in result.get("classes", []):
		if typeof(rec) == TYPE_DICTIONARY:
			out[str(rec.get("prjid", ""))] = rec
	return out


func _make_install(root: String) -> void:
	DirAccess.make_dir_recursive_absolute(
		root.path_join("BZ_ASSETS").path_join("common").path_join("models")
	)
	var f := FileAccess.open(root.path_join("battlezone98redux.exe"), FileAccess.WRITE)
	if f != null:
		f.store_string("")


func _write_odf(path: String, class_label: String, fields: Dictionary) -> void:
	var lines := "[GameObjectClass]\nclassLabel = \"%s\"\n" % class_label
	for k in fields.keys():
		lines += "%s = %s\n" % [k, fields[k]]
	_write(path, lines)


func _write_synth_geo(path: String) -> bool:
	## One untextured triangle. Layout matches BzGeo / docs/formats/F4.
	var buf := PackedByteArray()
	buf.append_array(".GEO".to_ascii_buffer())
	_append_s32(buf, 0)
	var name := "synth".to_ascii_buffer()
	while name.size() < 16:
		name.append(0)
	buf.append_array(name.slice(0, 16))
	_append_s32(buf, 3)
	_append_s32(buf, 1)
	_append_s32(buf, 0)
	for p in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]:
		_append_f32(buf, p.x)
		_append_f32(buf, p.y)
		_append_f32(buf, p.z)
	for _i in 3:
		_append_f32(buf, 0.0)
		_append_f32(buf, 0.0)
		_append_f32(buf, 1.0)
	var face := PackedByteArray()
	face.resize(55)
	face.encode_s32(4, 3)
	face[8] = 200
	face[9] = 200
	face[10] = 200
	buf.append_array(face)
	for i in 3:
		var node := PackedByteArray()
		node.resize(16)
		node.encode_s32(0, i)
		node.encode_s32(4, i)
		node.encode_float(8, 0.0)
		node.encode_float(12, 0.0)
		buf.append_array(node)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(buf)
	return true


func _append_s32(buf: PackedByteArray, v: int) -> void:
	var n := buf.size()
	buf.resize(n + 4)
	buf.encode_s32(n, v)


func _append_f32(buf: PackedByteArray, v: float) -> void:
	var n := buf.size()
	buf.resize(n + 4)
	buf.encode_float(n, v)


func _write(path: String, body: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(body)


func _rmtree(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.include_hidden = true
	da.include_navigational = false
	for fname in da.get_files():
		da.remove(fname)
	for dname in da.get_directories():
		_rmtree(path.path_join(dname))
	DirAccess.remove_absolute(path)
