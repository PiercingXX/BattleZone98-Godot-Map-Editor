extends RefCounted
## BzErrors + BzSession: session directory, buffers, pass-through bookkeeping.


func run(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz_session_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)

	_test_errors(t)
	_test_paths_and_skeleton(t, tmp)
	_test_json(t, tmp)
	_test_dirty_and_manifest(t, tmp)
	_test_terrain_buffers(t, tmp)
	_test_materials(t, tmp)
	_test_map_discovery(t, tmp)
	_test_residue(t, tmp)

	_rm_rf(tmp)


func _test_errors(t) -> void:
	var bare: Dictionary = BzErrors.err("stem_too_long", "too long")
	t.eq(bare.get("ok"), false, "err ok=false")
	t.ok(bare.has("error"), "err has error")
	t.eq(bare["error"].get("code"), "stem_too_long")
	t.eq(bare["error"].get("message"), "too long")
	t.ok(not (bare["error"] as Dictionary).has("hint"), "empty hint omitted (Python as_dict)")
	t.ok(not (bare["error"] as Dictionary).has("path"), "empty path omitted")
	t.ok(BzErrors.is_err(bare))

	var full: Dictionary = BzErrors.err(
		"not_found",
		"no such file or directory: /nope",
		"open or new a map first",
		"/nope"
	)
	t.eq(full["error"].get("hint"), "open or new a map first")
	t.eq(full["error"].get("path"), "/nope")
	t.ok(BzErrors.is_err(full))

	t.ok(not BzErrors.is_err({"ok": false, "findings": []}), "validate-style ok=false is not is_err")
	t.ok(not BzErrors.is_err({"ok": true, "stem": "x"}))
	t.ok(not BzErrors.is_err("nope"))


func _test_paths_and_skeleton(t, tmp: String) -> void:
	var root: String = tmp.path_join("sess")
	var paths: Dictionary = BzSession.session_paths(root)
	for key in [
		"root", "manifest", "terrain", "materials", "objects", "features",
		"meta", "dirty", "report", "masks", "residue", "source",
		"hg2_header", "hg2_flags",
	]:
		t.ok(paths.has(key), "session_paths has %s" % key)
	t.eq(paths["root"], root)
	t.eq(paths["manifest"], root.path_join("manifest.json"))
	t.eq(paths["terrain"], root.path_join("terrain.r16"))
	t.eq(paths["source"], root.path_join("residue").path_join("source"))
	t.eq(paths["hg2_flags"], root.path_join("residue").path_join("hg2_flags.u8"))

	var ensured: Dictionary = BzSession.ensure_session_dir(root)
	t.ok(not BzErrors.is_err(ensured), "ensure_session_dir succeeds")
	t.ok(DirAccess.dir_exists_absolute(ensured["masks"]), "masks/")
	t.ok(DirAccess.dir_exists_absolute(ensured["residue"]), "residue/")
	t.ok(DirAccess.dir_exists_absolute(ensured["source"]), "residue/source/")

	t.eq(BzSession.variant_bzn_suffix(""), ".bzn")
	t.eq(BzSession.variant_bzn_suffix("_S"), "_S.bzn")
	t.eq(BzSession.variant_bzn_suffix("_SW"), "_SW.bzn")


func _test_json(t, tmp: String) -> void:
	var path: String = tmp.path_join("round.json")
	var payload := {
		"ok": true,
		"name": "café",
		"n": 2,
		"flag": false,
		"nested": {"a": [1, 2]},
	}
	var wr: Dictionary = BzSession.write_json(path, payload)
	t.eq(wr.get("ok"), true, "write_json ok")
	var rd: Variant = BzSession.read_json(path)
	t.ok(not BzErrors.is_err(rd), "read_json ok")
	t.eq(rd.get("ok"), true)
	t.eq(rd.get("name"), "café", "unicode survives (ensure_ascii=False)")
	t.eq(rd.get("n"), 2)
	t.eq(rd.get("flag"), false)

	var missing: Variant = BzSession.read_json(tmp.path_join("no-such.json"))
	t.ok(BzErrors.is_err(missing), "read_json missing")
	t.eq(missing["error"].get("code"), "not_found")

	var bad_path: String = tmp.path_join("bad.json")
	_write_text(bad_path, "{not json")
	var bad: Variant = BzSession.read_json(bad_path)
	t.ok(BzErrors.is_err(bad), "read_json invalid")
	t.eq(bad["error"].get("code"), "invalid_json")


func _test_dirty_and_manifest(t, tmp: String) -> void:
	var d0: Dictionary = BzSession.empty_dirty()
	t.eq(d0.get("terrain"), false)
	t.eq(d0.get("materials"), false)
	t.eq(d0.get("features"), false)
	t.eq(d0.get("meta"), [])
	t.ok(d0["objects"].has(""), "default variant \"\"")
	t.eq((d0["objects"][""] as Array).size(), 0)

	var d1: Dictionary = BzSession.empty_dirty(["", "_S", "_SW"])
	t.ok((d1["objects"] as Dictionary).has(""))
	t.ok((d1["objects"] as Dictionary).has("_S"))
	t.ok((d1["objects"] as Dictionary).has("_SW"))

	var dirty_path: String = tmp.path_join("dirty.json")
	BzSession.write_json(dirty_path, d1)
	var back: Variant = BzSession.read_json(dirty_path)
	t.ok(not BzErrors.is_err(back))
	t.eq(back.get("terrain"), false)
	t.ok((back["objects"] as Dictionary).has(""), "empty-string variant key survives JSON")
	t.ok((back["objects"] as Dictionary).has("_S"))

	var man_path: String = tmp.path_join("manifest.json")
	var man: Variant = BzSession.write_manifest(man_path, {
		"stem": "xxedtest",
		"world": "mars",
		"width_m": 1280,
		"height_over_ceiling": false,
	})
	t.ok(not BzErrors.is_err(man))
	t.eq(man.get("contract_version"), 1)
	t.eq(man.get("stem"), "xxedtest")
	var man_rd: Variant = BzSession.read_json(man_path)
	t.eq(man_rd.get("contract_version"), BzSession.CONTRACT_VERSION)
	t.eq(man_rd.get("world"), "mars")


func _test_terrain_buffers(t, tmp: String) -> void:
	var r16: String = tmp.path_join("tiny.r16")
	var words := PackedInt32Array([1000, (2 << BzSession.FLAG_SHIFT) | 2000, 4095])
	var wr: Dictionary = BzSession.write_terrain_r16(r16, {"data": words})
	t.eq(wr.get("ok"), true)
	var got: Variant = BzSession.read_terrain_r16(r16, 1, 3)
	t.ok(got is PackedInt32Array, "read_terrain_r16 returns words")
	t.eq(got[0], 1000)
	t.eq(got[1], 2000, "flag bits stripped from terrain.r16")
	t.eq(got[2], 4095)

	var mismatch: Variant = BzSession.read_terrain_r16(r16, 4, 4)
	t.ok(BzErrors.is_err(mismatch))
	t.eq(mismatch["error"].get("code"), "terrain_size_mismatch")
	t.ok(str(mismatch["error"].get("message")).contains("3"), "message names actual count")

	var missing: Variant = BzSession.read_terrain_r16(tmp.path_join("no.r16"), 1, 1)
	t.ok(BzErrors.is_err(missing))
	t.eq(missing["error"].get("code"), "not_found")

	t.ok(not BzSession.height_over_ceiling({"data": PackedInt32Array([1000, 4095])}))
	t.ok(BzSession.height_over_ceiling({"data": PackedInt32Array([4096])}))
	t.ok(
		BzSession.height_over_ceiling({"data": PackedInt32Array([(3 << 13) | 5000])}),
		"flagged cell still checks the 13-bit height"
	)

	# Full 1-zone reconstruct: flags OR'd back onto masked heights.
	var n: int = BzHg2.ZONE_SIZE * BzHg2.ZONE_SIZE
	var raw := PackedInt32Array()
	raw.resize(n)
	raw.fill(1000)
	raw[0] = (3 << BzSession.FLAG_SHIFT) | 1500
	raw[10] = 5000
	var hm := BzHg2.HeightMap.new(1, 1, raw)
	t.ok(BzSession.height_over_ceiling(hm), "5000 is over the authoring ceiling")

	var sess: String = tmp.path_join("recon")
	var paths: Dictionary = BzSession.ensure_session_dir(sess)
	BzSession.write_terrain_r16(paths["terrain"], hm)
	BzSession.write_hg2_flags(paths["hg2_flags"], hm)
	BzSession.write_json(paths["hg2_header"], {
		"version": 1,
		"depth": 8,
		"zonesX": 1,
		"zonesZ": 1,
		"unknownA": 10,
		"unknownB": 0,
	})
	var flags: Variant = BzSession.read_hg2_flags(paths["hg2_flags"], BzHg2.ZONE_SIZE, BzHg2.ZONE_SIZE)
	t.ok(flags is PackedByteArray)
	t.eq(int(flags[0]), 3)
	t.eq(int(flags[1]), 0)

	var bad_flags: Variant = BzSession.read_hg2_flags(paths["hg2_flags"], 2, 2)
	t.ok(BzErrors.is_err(bad_flags))
	t.eq(bad_flags["error"].get("code"), "flags_size_mismatch")

	var rebuilt_v: Variant = BzSession.reconstruct_heightmap(paths, {
		"zonesX": 1, "zonesZ": 1, "version": 1, "depth": 8, "unknownA": 10, "unknownB": 0,
	})
	t.ok(not BzErrors.is_err(rebuilt_v), "reconstruct_heightmap")
	var rebuilt: BzHg2.HeightMap = rebuilt_v
	t.eq(rebuilt.data[0], (3 << BzSession.FLAG_SHIFT) | 1500, "flags OR'd back")
	t.eq(rebuilt.data[1], 1000)
	t.eq(rebuilt.data[10] & BzSession.HEIGHT_MASK, 5000, "inherited over-ceiling height kept")
	t.eq(rebuilt.zonesX, 1)
	t.eq(rebuilt.unknownA, 10)

	# No flags file → zeros.
	DirAccess.remove_absolute(paths["hg2_flags"])
	var noflag_v: Variant = BzSession.reconstruct_heightmap(paths, {
		"zonesX": 1, "zonesZ": 1,
	})
	t.ok(not BzErrors.is_err(noflag_v))
	t.eq((noflag_v as BzHg2.HeightMap).data[0], 1500, "missing flags file → 0")


func _test_materials(t, tmp: String) -> void:
	var path: String = tmp.path_join("tiny.u16")
	var data := PackedInt32Array([0x1000, 0x2100, 0, 7])
	var grid := BzMat.MaterialGrid.new(data, 2, 2)
	var wr: Dictionary = BzSession.write_materials_u16(path, grid)
	t.eq(wr.get("ok"), true)
	var rd: Variant = BzSession.read_materials_u16(path, 2, 2)
	t.ok(not BzErrors.is_err(rd))
	t.eq(rd.grid_x, 2)
	t.eq(rd.grid_z, 2)
	t.eq(rd.data[0], 0x1000)
	t.eq(rd.data[3], 7)

	var mismatch: Variant = BzSession.read_materials_u16(path, 8, 8)
	t.ok(BzErrors.is_err(mismatch))
	t.eq(mismatch["error"].get("code"), "materials_size_mismatch")


func _test_map_discovery(t, tmp: String) -> void:
	var missing: Dictionary = BzSession.resolve_map_input(tmp.path_join("does-not-exist"))
	t.ok(BzErrors.is_err(missing))
	t.eq(missing["error"].get("code"), "not_found")

	var empty: String = tmp.path_join("empty_dir")
	DirAccess.make_dir_recursive_absolute(empty)
	var none: Dictionary = BzSession.resolve_map_input(empty)
	t.ok(BzErrors.is_err(none))
	t.eq(none["error"].get("code"), "no_map_files")
	t.eq(none["error"].get("hint"), "point at a .trn / .bzn / .hg2 or the directory that holds them")

	var maps: String = tmp.path_join("maps")
	DirAccess.make_dir_recursive_absolute(maps)
	_write_text(maps.path_join("Foo.TRN"), "trn")
	_write_text(maps.path_join("foo.hg2"), "hg2")
	_write_text(maps.path_join("foo_S.bzn"), "s")
	_write_text(maps.path_join("foo_SW.bzn"), "sw")
	_write_text(maps.path_join("fooMAP.lua"), "lua")
	_write_text(maps.path_join("foo.des"), "des")
	_write_text(maps.path_join("other.trn"), "no")
	_write_text(maps.path_join("fooextra.txt"), "no")

	var names: Array = []
	for p in BzSession.collect_map_files(maps, "foo"):
		names.append(str(p).get_file())
	t.ok(names.has("Foo.TRN"))
	t.ok(names.has("foo.hg2"))
	t.ok(names.has("foo_S.bzn"))
	t.ok(names.has("foo_SW.bzn"))
	t.ok(names.has("fooMAP.lua"), "<stem>MAP.lua is in the basename group")
	t.ok(names.has("foo.des"))
	t.ok(not names.has("other.trn"))
	t.ok(not names.has("fooextra.txt"), "prefix without . or _ is not a match")

	var from_dir: Dictionary = BzSession.resolve_map_input(maps)
	t.eq(from_dir.get("ok"), true)
	t.eq(str(from_dir.get("stem")).to_lower(), "foo")
	t.eq(from_dir.get("directory"), maps)
	t.ok((from_dir["files"] as Array).size() >= 6)

	var from_var: Dictionary = BzSession.resolve_map_input(maps.path_join("foo_S.bzn"))
	t.eq(from_var.get("ok"), true)
	t.eq(from_var.get("stem"), "foo", "variant suffix stripped")

	t.eq(BzSession.find_source_file(maps, "foo", ".hg2").get_file().to_lower(), "foo.hg2")
	t.eq(BzSession.find_source_file(maps, "foo", ".trn").get_file().to_lower(), "foo.trn")
	t.eq(BzSession.find_source_file(maps, "foo", ".nope"), "", "missing suffix → empty")


func _test_residue(t, tmp: String) -> void:
	var src_dir: String = tmp.path_join("orig")
	var residue: String = tmp.path_join("res_src")
	DirAccess.make_dir_recursive_absolute(src_dir)
	var a: String = src_dir.path_join("xxmap.trn")
	var b: String = src_dir.path_join("xxmap.hg2")
	_write_text(a, "trn-bytes")
	_write_text(b, "hg2-bytes")
	var copied: Variant = BzSession.copy_into_residue([a, b], residue)
	t.ok(not BzErrors.is_err(copied))
	t.eq((copied as Array).size(), 2)
	t.eq(FileAccess.get_file_as_string(residue.path_join("xxmap.trn")), "trn-bytes")
	t.eq(FileAccess.get_file_as_string(residue.path_join("xxmap.hg2")), "hg2-bytes")

	# Same-path copy is a no-op success (Python dest.resolve() == src.resolve()).
	var again: Variant = BzSession.copy_into_residue(
		[residue.path_join("xxmap.trn")], residue
	)
	t.ok(not BzErrors.is_err(again))
	t.eq(FileAccess.get_file_as_string(residue.path_join("xxmap.trn")), "trn-bytes")


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


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
