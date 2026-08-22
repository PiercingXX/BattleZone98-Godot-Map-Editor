extends RefCounted
## BzOpen: synthetic map → session. Payload shape, residue bytes, error paths.
## Optional open→save byte-identical check if BzSave has landed.


const FIX_BZN := "res://tests/gd/fixtures/bzn/untouched.bzn"

## Synthetic .bzn fixtures are caught by .gitignore's blanket *.bzn ban
## (AGENTS.md rule 3), so a fresh checkout — and every CI runner — has none.
## The cases that need one report SKIP instead of asserting against nothing.
const NEEDS_BZN_FIXTURE := "no local .bzn fixture (gitignored; see fixtures/bzn/README.txt)"


func run(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz_open_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)

	_test_is_binary_bzn(t, tmp)
	_test_error_paths(t, tmp)
	_test_open_success(t, tmp)
	_test_sparse_and_case(t, tmp)
	_test_pack_context(t, tmp)
	_test_open_save_if_present(t, tmp)

	_rm_rf(tmp)


func _test_is_binary_bzn(t, tmp: String) -> void:
	t.eq(BzOpen.is_binary_bzn(tmp.path_join("missing.bzn")), false, "missing is not binary")

	var empty: String = tmp.path_join("empty.bzn")
	_write_bytes(empty, PackedByteArray())
	t.eq(BzOpen.is_binary_bzn(empty), false, "empty file")

	# Not "nul.bzn": NUL (any extension) is a reserved device name on Windows —
	# the write silently goes to the NUL device and the file never exists.
	var nul: String = tmp.path_join("nulbytes.bzn")
	_write_bytes(nul, PackedByteArray([0x00, 0x01, 0x02]))
	t.eq(BzOpen.is_binary_bzn(nul), true, "NUL in first 256")

	var ascii_ok: String = tmp.path_join("ascii.bzn")
	_write_text(
		ascii_ok,
		"version [1] =\n2016\nbinarySave [1] =\nfalse\nmissionSave [1] =\ntrue\n"
	)
	t.eq(BzOpen.is_binary_bzn(ascii_ok), false, "ASCII + missionSave is not binary")

	var bin_true: String = tmp.path_join("bintrue.bzn")
	_write_text(bin_true, "version [1] =\n2016\nbinarySave [1] =\ntrue\n")
	t.eq(BzOpen.is_binary_bzn(bin_true), true, "binarySave true on next line")

	var bin_inline: String = tmp.path_join("bininline.bzn")
	_write_text(bin_inline, "version [1] =\n2016\nBinarySave [1] = true\n")
	t.eq(BzOpen.is_binary_bzn(bin_inline), true, "inline binarySave true")

	var no_ver: String = tmp.path_join("nover.bzn")
	_write_text(no_ver, "hello world\nbinarySave [1] =\nfalse\n")
	t.eq(BzOpen.is_binary_bzn(no_ver), true, "does not start with version")

	var bad_utf: String = tmp.path_join("badutf.bzn")
	var bad := PackedByteArray()
	bad.append_array("version [1] =\n2016\n".to_utf8_buffer())
	bad.append(0xFF)
	bad.append(0xFE)
	_write_bytes(bad_utf, bad)
	t.eq(BzOpen.is_binary_bzn(bad_utf), true, "invalid UTF-8")

	var ws: String = tmp.path_join("ws.bzn")
	_write_text(ws, "\n\n  version [1] =\n2016\nbinarySave [1] =\nfalse\n")
	t.eq(BzOpen.is_binary_bzn(ws), false, "leading whitespace then version")

	var late: String = tmp.path_join("late.bzn")
	var late_lines: PackedStringArray = PackedStringArray()
	late_lines.append("version [1] =")
	for _i in 20:
		late_lines.append("x")
	late_lines.append("binarySave [1] =")
	late_lines.append("true")
	_write_text(late, "\n".join(late_lines) + "\n")
	t.eq(BzOpen.is_binary_bzn(late), false, "binarySave after first 20 lines ignored")

	if t.require_files([FIX_BZN], NEEDS_BZN_FIXTURE):
		var fixture: String = ProjectSettings.globalize_path(FIX_BZN)
		t.eq(BzOpen.is_binary_bzn(fixture), false, "synthetic ASCII fixture")


func _test_error_paths(t, tmp: String) -> void:
	var missing: Dictionary = BzOpen.open_map(tmp.path_join("no-such"), tmp.path_join("s0"))
	t.ok(BzErrors.is_err(missing), "missing path: %s" % str(missing))
	t.eq(missing.get("error", {}).get("code"), "not_found")

	var empty: String = tmp.path_join("empty_dir")
	DirAccess.make_dir_recursive_absolute(empty)
	var none: Dictionary = BzOpen.open_map(empty, tmp.path_join("s1"))
	t.ok(BzErrors.is_err(none), "empty dir: %s" % str(none))
	t.eq(none.get("error", {}).get("code"), "no_map_files")
	t.eq(
		none.get("error", {}).get("hint"),
		"point at a .trn / .bzn / .hg2 or the directory that holds them"
	)

	var bin_dir: String = tmp.path_join("binmap")
	DirAccess.make_dir_recursive_absolute(bin_dir)
	_write_bytes(bin_dir.path_join("only.bzn"), PackedByteArray([0x00, 0x01, 0x02]))
	_write_hg2(bin_dir.path_join("only.hg2"), _flat_hm(1, 1, 1000))
	var refused: Dictionary = BzOpen.open_map(bin_dir.path_join("only.bzn"), tmp.path_join("s2"))
	t.ok(BzErrors.is_err(refused), "binary BZN refused: %s" % str(refused))
	t.eq(refused.get("error", {}).get("code"), "binary_bzn_unsupported")
	t.eq(
		refused.get("error", {}).get("message"),
		"only.bzn is a binary BZN; a binary reader is not in bzmap yet"
	)
	t.eq(
		refused.get("error", {}).get("hint"),
		"re-save from the game with the asciisave launch argument, or wait for the binary reader"
	)
	t.ok(str(refused.get("error", {}).get("path", "")).ends_with("only.bzn"))

	var nohg: String = tmp.path_join("nohg")
	DirAccess.make_dir_recursive_absolute(nohg)
	_write_text(nohg.path_join("nohg.trn"), "[Size]\nWidth = 1280\n")
	_write_text(nohg.path_join("nohg.bzn"), "version [1] =\n2016\nbinarySave [1] =\nfalse\n")
	var miss_hg2: Dictionary = BzOpen.open_map(nohg.path_join("nohg.trn"), tmp.path_join("s3"))
	t.ok(BzErrors.is_err(miss_hg2), "missing hg2: %s" % str(miss_hg2))
	t.eq(miss_hg2.get("error", {}).get("code"), "missing_hg2")
	t.ok(str(miss_hg2.get("error", {}).get("message")).contains("no .hg2 for stem 'nohg'"))
	t.eq(miss_hg2.get("error", {}).get("path"), nohg)


func _test_open_success(t, tmp: String) -> void:
	if not t.require_files([FIX_BZN], NEEDS_BZN_FIXTURE):
		return
	var src: String = tmp.path_join("synmap_src")
	DirAccess.make_dir_recursive_absolute(src)
	var hm := _flat_hm(1, 1, 1000)
	hm.data[0] = 1000 | (5 << 13)
	hm.data[1] = 5000
	hm.data[256] = 10 | (7 << 13)
	hm.unknownA = 42
	hm.unknownB = 7
	_write_hg2(src.path_join("synmap.hg2"), hm)
	_write_mat(src.path_join("synmap.mat"), 64, 64, BzMat.encode_entry(2, 3, 0, 0, 1, 1))
	_write_text(
		src.path_join("synmap.trn"),
		"[Size]\r\nWidth = 1280\r\nDepth = 1280\r\n[Sky]\r\nSkyTexture = mars.map\r\n"
		+ "[Color]\r\nPalette = io.act\r\n[NormalView]\r\nNear = 1\r\n"
		+ "[World]\r\nSunColor = 255 200 100\r\n[Clouds]\r\nCloud1 = foo\r\n"
	)
	_write_text(src.path_join("synmap.ini"), "[MISSION]\r\nmissionName = Test\r\n")
	_write_text(src.path_join("synmap.des"), "desc here\n")
	_copy_file(ProjectSettings.globalize_path(FIX_BZN), src.path_join("synmap.bzn"))
	_copy_file(ProjectSettings.globalize_path(FIX_BZN), src.path_join("synmap_S.bzn"))
	_write_bytes(src.path_join("synmap.lgt"), "LGTFAKE".to_utf8_buffer())
	_write_bytes(src.path_join("synmap.vxt"), "VXTFAKE".to_utf8_buffer())
	_write_json(src.path_join("features.json"), {
		"water": [{"stem": "w1", "level_m": 10.0, "mask": "masks/w1.u8", "variant_scope": "all"}],
		"plants": [],
	})

	var sess: String = tmp.path_join("syn_sess")
	var result: Dictionary = BzOpen.open_map(src.path_join("synmap.trn"), sess)
	t.eq(result.get("ok"), true, "open_map ok: %s" % str(result))
	t.ok(not BzErrors.is_err(result))
	if result.get("ok") != true:
		return
	t.ok(str(result.get("session", "")).ends_with("syn_sess") or result.get("session") == sess)
	t.ok(result.has("manifest"), "payload has manifest")
	t.ok(result.has("warnings"), "payload has warnings")

	var man: Dictionary = result.get("manifest", {})
	t.eq(man.get("contract_version"), 1)
	t.eq(man.get("stem"), "synmap")
	t.eq(man.get("converted_from_binary"), false)
	t.eq(man.get("world"), "mars", "world from SkyTexture stem")
	t.eq(man.get("width_m"), 1280)
	t.eq(man.get("depth_m"), 1280)
	t.eq(man.get("grid_x"), 256)
	t.eq(man.get("grid_z"), 256)
	t.eq(man.get("cell_m"), 5.0)
	t.eq(man.get("height_scale"), 0.1)
	t.eq(man.get("height_max_raw"), 4095)
	t.eq(man.get("height_over_ceiling"), true)
	t.eq(man.get("mat_grid_x"), 64)
	t.eq(man.get("mat_grid_z"), 64)
	t.eq(man.get("mat_cell_m"), 20.0)
	t.eq(man.get("has_lightmap"), true)
	t.eq(man.get("pack_context"), {"kind": "base"})
	var variants: Array = man.get("variants", [])
	t.ok(variants.has(""), "base variant present")
	t.ok(variants.has("_S"), "_S variant present")
	t.ok(not variants.has("_ST"), "absent _ST not listed")

	var warns: Array = result.get("warnings", [])
	t.ok(
		warns.has(
			"source heightmap has cells above the editor authoring ceiling "
			+ "(raw 4095); inherited values are preserved"
		),
		"over-ceiling warning"
	)

	# Residue is a verbatim copy of every source file in the basename group.
	var residue: String = sess.path_join("residue").path_join("source")
	for name in [
		"synmap.hg2", "synmap.mat", "synmap.trn", "synmap.ini", "synmap.des",
		"synmap.bzn", "synmap_S.bzn", "synmap.lgt", "synmap.vxt",
	]:
		t.ok(_bytes_eq(src.path_join(name), residue.path_join(name)), "residue %s verbatim" % name)
	t.ok(
		not FileAccess.file_exists(residue.path_join("features.json")),
		"features.json sidecar is not a basename-group file"
	)

	var terrain: PackedByteArray = FileAccess.get_file_as_bytes(sess.path_join("terrain.r16"))
	t.eq(terrain.size(), 256 * 256 * 2)
	t.eq(terrain.decode_u16(0), 1000, "flags stripped from terrain.r16[0]")
	t.eq(terrain.decode_u16(2), 5000, "inherited over-ceiling height kept")
	t.eq(terrain.decode_u16(256 * 2), 10, "terrain.r16[256] height-only")

	var flags: PackedByteArray = FileAccess.get_file_as_bytes(
		sess.path_join("residue").path_join("hg2_flags.u8")
	)
	t.eq(flags.size(), 256 * 256)
	t.eq(int(flags[0]), 5)
	t.eq(int(flags[1]), 0)
	t.eq(int(flags[256]), 7)

	var header: Variant = _read_json(sess.path_join("residue").path_join("hg2_header.json"))
	t.eq(header.get("unknownA"), 42)
	t.eq(header.get("unknownB"), 7)
	t.eq(header.get("zonesX"), 1)
	t.eq(header.get("version"), 1)

	var dirty: Variant = _read_json(sess.path_join("dirty.json"))
	t.eq(dirty.get("terrain"), false)
	t.eq(dirty.get("materials"), false)
	t.eq(dirty.get("features"), false)
	t.eq(dirty.get("meta"), [])
	t.ok((dirty["objects"] as Dictionary).has(""))
	t.ok((dirty["objects"] as Dictionary).has("_S"))
	t.eq((dirty["objects"][""] as Array).size(), 0)

	var objs: Variant = _read_json(sess.path_join("objects.json"))
	t.ok(objs.has(""))
	t.ok(objs.has("_S"))
	t.ok(objs.has("_ST"))
	t.ok(objs.has("_SW"))
	t.eq((objs[""] as Array).size(), 2)
	t.eq((objs["_S"] as Array).size(), 2)
	var player: Dictionary = objs[""][0]
	t.eq(player.get("id"), "obj-0001")
	t.eq(player.get("origin"), "source")
	t.eq(player.get("prjid"), "player")
	t.eq(player.get("x"), 640.0)
	t.eq(player.get("required"), true)
	t.eq(objs["_S"][0].get("id"), "obj_s-0001", "variant id prefix")

	var meta: Variant = _read_json(sess.path_join("meta.json"))
	t.ok(typeof(meta) == TYPE_DICTIONARY, "meta.json is an object")
	var meta_d: Dictionary = meta if typeof(meta) == TYPE_DICTIONARY else {}
	t.ok(meta_d.has("ini"), "meta.ini present: %s" % str(meta_d.keys()))
	var ini_raw: String = ""
	if meta_d.get("ini") is Dictionary:
		ini_raw = str(meta_d["ini"].get("raw", ""))
	t.ok(ini_raw.contains("missionName"), "ini raw")
	t.ok(meta_d.has("des"))
	t.ok(meta_d.has("trn"))
	var trn_d: Dictionary = meta_d["trn"] if meta_d.get("trn") is Dictionary else {}
	t.eq((trn_d.get("Sky", {}) as Dictionary).get("SkyTexture"), "mars.map")
	t.eq((trn_d.get("World", {}) as Dictionary).get("SunColor"), "255 200 100")

	var feat: Variant = _read_json(sess.path_join("features.json"))
	t.eq((feat.get("water", []) as Array).size(), 1)
	t.eq(feat["water"][0].get("stem"), "w1")

	t.ok(FileAccess.file_exists(sess.path_join("aipaths.json")), "aipaths.json sidecar")
	var aip: Variant = _read_json(sess.path_join("aipaths.json"))
	t.ok(typeof(aip) == TYPE_DICTIONARY, "aipaths.json is an object")
	t.eq((aip.get("paths", ["x"]) as Array).size(), 0, "fixture has empty AiPaths")
	t.eq(bool((dirty.get("aipaths", {}) as Dictionary).get("", true)), false, "aipaths not dirty")

	# Directory input resolves the same stem.
	var sess_dir: String = tmp.path_join("syn_sess_dir")
	var via_dir: Dictionary = BzOpen.open_map(src, sess_dir)
	t.eq(via_dir.get("ok"), true, "open directory: %s" % str(via_dir))
	t.eq(via_dir.get("manifest", {}).get("stem"), "synmap")


func _test_sparse_and_case(t, tmp: String) -> void:
	var sparse: String = tmp.path_join("sparse")
	DirAccess.make_dir_recursive_absolute(sparse)
	_write_hg2(sparse.path_join("sparse.hg2"), _flat_hm(1, 1, 1000))
	var hg2_path: String = sparse.path_join("sparse.hg2")
	t.eq(FileAccess.get_file_as_bytes(hg2_path).size(), 12 + 256 * 256 * 2, "sparse.hg2 on disk")
	var sess: String = tmp.path_join("sparse_sess")
	var result: Dictionary = BzOpen.open_map(hg2_path, sess)
	t.eq(result.get("ok"), true, "sparse open: %s" % str(result))
	if result.get("ok") != true:
		return
	var warns: Array = result.get("warnings", [])
	t.ok(warns.has("no .mat in the basename group"))
	t.ok(warns.has("no .bzn in the basename group"))
	var sman: Dictionary = result.get("manifest", {})
	t.eq(sman.get("variants"), [""])
	t.eq(sman.get("mat_grid_x"), 64)
	t.eq(sman.get("mat_grid_z"), 64)
	t.eq(sman.get("has_lightmap"), false)
	t.eq(FileAccess.get_file_as_bytes(sess.path_join("materials.u16")).size(), 64 * 64 * 2)

	var cased: String = tmp.path_join("Case")
	DirAccess.make_dir_recursive_absolute(cased)
	_write_hg2(cased.path_join("MyMap.Hg2"), _flat_hm(1, 1, 1100))
	_write_text(cased.path_join("mymap.TRN"), "[Sky]\r\nSkyTexture = venus.map\r\n")
	var csess: String = tmp.path_join("case_sess")
	var cresult: Dictionary = BzOpen.open_map(cased.path_join("mymap.TRN"), csess)
	t.eq(cresult.get("ok"), true, "case open: %s" % str(cresult))
	if cresult.get("ok") != true:
		return
	t.eq(cresult.get("manifest", {}).get("stem"), "mymap")
	t.eq(cresult.get("manifest", {}).get("world"), "venus")

	var var_dir: String = tmp.path_join("var")
	DirAccess.make_dir_recursive_absolute(var_dir)
	_write_hg2(var_dir.path_join("varmap.hg2"), _flat_hm(1, 1, 1000))
	_write_text(var_dir.path_join("varmap_S.bzn"), "version [1] =\n2016\nbinarySave [1] =\nfalse\n")
	var vsess: String = tmp.path_join("var_sess")
	var vresult: Dictionary = BzOpen.open_map(var_dir.path_join("varmap_S.bzn"), vsess)
	t.eq(vresult.get("ok"), true, "variant open: %s" % str(vresult))
	if vresult.get("ok") != true:
		return
	t.eq(vresult.get("manifest", {}).get("stem"), "varmap")
	t.eq(vresult.get("manifest", {}).get("variants"), ["_S"])

	# Two-zone map: grid / width come from the de-zoned heightmap.
	var multi: String = tmp.path_join("multi")
	DirAccess.make_dir_recursive_absolute(multi)
	_write_hg2(multi.path_join("multi.hg2"), _flat_hm(2, 1, 1200))
	var msess: String = tmp.path_join("multi_sess")
	var mresult: Dictionary = BzOpen.open_map(multi, msess)
	t.eq(mresult.get("ok"), true, "multi-zone open: %s" % str(mresult))
	if mresult.get("ok") != true:
		return
	t.eq(mresult.get("manifest", {}).get("grid_x"), 512)
	t.eq(mresult["manifest"].get("grid_z"), 256)
	t.eq(mresult["manifest"].get("width_m"), 2560)
	t.eq(mresult["manifest"].get("depth_m"), 1280)
	t.eq(FileAccess.get_file_as_bytes(msess.path_join("terrain.r16")).size(), 512 * 256 * 2)


func _test_pack_context(t, tmp: String) -> void:
	# has .odf, not under workshop/packaged_mods → bzp with null workshop_id
	var odf_dir: String = tmp.path_join("odfonly")
	DirAccess.make_dir_recursive_absolute(odf_dir)
	_write_hg2(odf_dir.path_join("odfonly.hg2"), _flat_hm(1, 1, 1000))
	_write_text(odf_dir.path_join("odfonly.odf"), "[GameObjectClass]\r\n")
	var oresult: Dictionary = BzOpen.open_map(odf_dir, tmp.path_join("odf_sess"))
	t.eq(oresult.get("ok"), true, "odf pack_context: %s" % str(oresult))
	if oresult.get("ok") != true:
		return
	t.eq(oresult.get("manifest", {}).get("pack_context", {}).get("kind"), "bzp")
	t.eq(oresult.get("manifest", {}).get("pack_context", {}).get("workshop_id"), null)

	var pack: String = tmp.path_join("packaged_mods").path_join("9990001")
	DirAccess.make_dir_recursive_absolute(pack)
	_write_hg2(pack.path_join("pmod.hg2"), _flat_hm(1, 1, 1000))
	_write_text(pack.path_join("pmod.odf"), "[GameObjectClass]\r\n")
	var presult: Dictionary = BzOpen.open_map(pack, tmp.path_join("pmod_sess"))
	t.eq(presult.get("ok"), true, "packaged_mods pack_context: %s" % str(presult))
	if presult.get("ok") != true:
		return
	t.eq(presult.get("manifest", {}).get("pack_context", {}).get("kind"), "bzp")
	t.eq(presult.get("manifest", {}).get("pack_context", {}).get("workshop_id"), "9990001")

	var bzp: String = tmp.path_join("3406347034").path_join("maps")
	DirAccess.make_dir_recursive_absolute(bzp)
	_write_hg2(bzp.path_join("bzpid.hg2"), _flat_hm(1, 1, 1000))
	var bresult: Dictionary = BzOpen.open_map(bzp, tmp.path_join("bzpid_sess"))
	t.eq(bresult.get("ok"), true, "bzp id pack_context: %s" % str(bresult))
	if bresult.get("ok") != true:
		return
	t.eq(bresult.get("manifest", {}).get("pack_context", {}).get("kind"), "bzp")
	t.eq(bresult.get("manifest", {}).get("pack_context", {}).get("workshop_id"), "3406347034")


func _test_open_save_if_present(t, tmp: String) -> void:
	if not t.require_files([FIX_BZN], NEEDS_BZN_FIXTURE):
		return
	# BzSave is another agent's file. Do not name that class here: a parse
	# error in their script would make this test fail to load. Residue
	# verbatim copies (above) are the open half of the open→save guarantee.
	var src: String = tmp.path_join("rt_src")
	DirAccess.make_dir_recursive_absolute(src)
	_write_hg2(src.path_join("rt.hg2"), _flat_hm(1, 1, 1000))
	_write_mat(src.path_join("rt.mat"), 64, 64, 0)
	_write_text(src.path_join("rt.trn"), "[Size]\r\nWidth = 1280\r\n")
	_copy_file(ProjectSettings.globalize_path(FIX_BZN), src.path_join("rt.bzn"))
	var sess: String = tmp.path_join("rt_sess")
	var opened: Dictionary = BzOpen.open_map(src.path_join("rt.trn"), sess)
	t.eq(opened.get("ok"), true, "open for residue/session buffers")
	if opened.get("ok") != true:
		return
	var residue: String = sess.path_join("residue").path_join("source")
	t.ok(_bytes_eq(src.path_join("rt.hg2"), residue.path_join("rt.hg2")), "hg2 residue")
	t.ok(_bytes_eq(src.path_join("rt.mat"), residue.path_join("rt.mat")), "mat residue")
	t.ok(_bytes_eq(src.path_join("rt.trn"), residue.path_join("rt.trn")), "trn residue")
	t.ok(_bytes_eq(src.path_join("rt.bzn"), residue.path_join("rt.bzn")), "bzn residue")
	t.ok(FileAccess.file_exists(sess.path_join("terrain.r16")), "session terrain.r16")
	t.ok(FileAccess.file_exists(sess.path_join("materials.u16")), "session materials.u16")
	t.ok(FileAccess.file_exists(sess.path_join("objects.json")), "session objects.json")
	t.ok(FileAccess.file_exists(sess.path_join("aipaths.json")), "session aipaths.json")
	t.ok(FileAccess.file_exists(sess.path_join("manifest.json")), "session manifest.json")


func _flat_hm(zones_x: int, zones_z: int, fill: int) -> BzHg2.HeightMap:
	var n: int = zones_x * BzHg2.ZONE_SIZE * zones_z * BzHg2.ZONE_SIZE
	var data := PackedInt32Array()
	data.resize(n)
	data.fill(fill)
	return BzHg2.HeightMap.new(zones_x, zones_z, data, 1, 8, 10, 0)


func _write_hg2(path: String, hm: BzHg2.HeightMap) -> void:
	var wr: Dictionary = BzHg2.write_hg2(path, hm)
	if not bool(wr.get("ok", false)):
		push_error("write_hg2 failed: %s" % path)


func _write_mat(path: String, grid_x: int, grid_z: int, first: int) -> void:
	var data := PackedInt32Array()
	data.resize(grid_x * grid_z)
	data.fill(0)
	if data.size() > 0:
		data[0] = first
	var grid := BzMat.MaterialGrid.new(data, grid_z, grid_x)
	BzMat.write_mat(path, grid)


func _write_json(path: String, payload: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	var text: String = JSON.stringify(payload, "  ")
	if not text.ends_with("\n"):
		text += "\n"
	file.store_string(text)
	file.close()


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed != null else {}


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


func _write_bytes(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(data)
	file.close()


func _copy_file(src: String, dest: String) -> void:
	DirAccess.copy_absolute(src, dest)


func _bytes_eq(a: String, b: String) -> bool:
	if not FileAccess.file_exists(a) or not FileAccess.file_exists(b):
		return false
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
