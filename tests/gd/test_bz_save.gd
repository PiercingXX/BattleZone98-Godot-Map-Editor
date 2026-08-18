extends RefCounted
## BzSave: pass-through byte-identical save, dirty re-encode, error paths.


func run(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz_save_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_test_errors(t, tmp)
	_test_untouched_roundtrip(t, tmp)
	_test_stem_rename(t, tmp)
	_test_dirty_terrain(t, tmp)
	_test_dirty_materials(t, tmp)
	_test_dirty_objects(t, tmp)
	_test_features_copy(t, tmp)
	_test_save_with_features(t, tmp)
	_test_managed_carriers_not_duplicated(t, tmp)
	_test_feature_stem_errors(t, tmp)
	_rm_rf(tmp)


func _test_errors(t, tmp: String) -> void:
	var nosess: Dictionary = BzSave.save_session(tmp.path_join("nosess"), tmp.path_join("out0"))
	t.ok(BzErrors.is_err(nosess), "missing manifest")
	t.eq(nosess["error"].get("code"), "no_session")
	t.eq(nosess["error"].get("hint"), "open or new a map first")

	var sess1: String = tmp.path_join("sess_nostem")
	DirAccess.make_dir_recursive_absolute(sess1.path_join("residue").path_join("source"))
	_write_json(sess1.path_join("manifest.json"), {"contract_version": 1})
	var nostem: Dictionary = BzSave.save_session(sess1, tmp.path_join("out1"))
	t.ok(BzErrors.is_err(nostem))
	t.eq(nostem["error"].get("code"), "no_stem")
	t.ok(not (nostem["error"] as Dictionary).has("hint"), "no_stem has no hint")

	var sess2: String = tmp.path_join("sess_nores")
	DirAccess.make_dir_recursive_absolute(sess2)
	_write_json(sess2.path_join("manifest.json"), {"contract_version": 1, "stem": "foo"})
	var nores: Dictionary = BzSave.save_session(sess2, tmp.path_join("out2"))
	t.ok(BzErrors.is_err(nores))
	t.eq(nores["error"].get("code"), "no_residue")
	t.ok(str(nores["error"].get("path", "")).contains("residue/source") or str(nores["error"].get("path", "")).contains("residue\\source"))


func _test_untouched_roundtrip(t, tmp: String) -> void:
	var sess: String = tmp.path_join("untouched")
	var src: String = sess.path_join("residue").path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	_write_json(sess.path_join("manifest.json"), {
		"contract_version": 1,
		"stem": "synth",
		"variants": [""],
		"mat_grid_x": 64,
		"mat_grid_z": 64,
	})
	_write_json(sess.path_join("dirty.json"), {
		"terrain": false,
		"materials": false,
		"objects": {"": []},
		"features": false,
		"meta": [],
	})
	_write_bytes(src.path_join("synth.trn"), "TRN-VERBATIM".to_utf8_buffer())
	_write_bytes(src.path_join("synth.hg2"), "HG2-FAKE-BYTES".to_utf8_buffer())
	_write_bytes(src.path_join("synth.mat"), "MAT-FAKE".to_utf8_buffer())
	_write_bytes(src.path_join("synth.bzn"), "version [1] =\r\n2016\r\n".to_utf8_buffer())
	_write_bytes(src.path_join("synth.vxt"), "vxt-data".to_utf8_buffer())
	_write_bytes(src.path_join("other.dat"), "passthru".to_utf8_buffer())
	var out_dir: String = tmp.path_join("out_untouched")
	var saved: Dictionary = BzSave.save_session(sess, out_dir)
	t.eq(saved.get("ok"), true, "untouched save ok")
	t.eq(saved.get("stem"), "synth")
	t.eq(saved.get("regenerated"), [], "no regenerated files")
	t.eq(saved.get("warnings"), [])
	var files: Array = saved.get("files", [])
	for name in ["other.dat", "synth.bzn", "synth.hg2", "synth.mat", "synth.trn", "synth.vxt"]:
		t.ok(files.has(name), "files lists %s" % name)
		t.ok((saved.get("byte_identical", []) as Array).has(name), "byte_identical %s" % name)
		t.ok(_same_bytes(src.path_join(name), out_dir.path_join(name)), "bytes match residue %s" % name)
	t.ok(saved.has("out"), "payload has out")
	t.ok(saved.has("features"), "payload has features")


func _test_stem_rename(t, tmp: String) -> void:
	var sess: String = tmp.path_join("rename")
	var src: String = sess.path_join("residue").path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	_write_json(sess.path_join("manifest.json"), {"contract_version": 1, "stem": "oldstem", "variants": [""]})
	_write_json(sess.path_join("dirty.json"), {"terrain": false, "materials": false, "objects": {"": []}, "features": false, "meta": []})
	_write_bytes(src.path_join("oldstem.trn"), "trn".to_utf8_buffer())
	_write_bytes(src.path_join("oldstem_S.bzn"), "s-bzn".to_utf8_buffer())
	var out_dir: String = tmp.path_join("out_rename")
	var saved: Dictionary = BzSave.save_session(sess, out_dir, "newstem")
	t.eq(saved.get("ok"), true)
	t.eq(saved.get("stem"), "newstem")
	t.ok(FileAccess.file_exists(out_dir.path_join("newstem.trn")))
	t.ok(FileAccess.file_exists(out_dir.path_join("newstem_S.bzn")))
	t.ok(_same_bytes(src.path_join("oldstem.trn"), out_dir.path_join("newstem.trn")))
	t.ok((saved.get("byte_identical", []) as Array).has("newstem.trn"))


func _test_dirty_terrain(t, tmp: String) -> void:
	var sess: String = tmp.path_join("dirty_t")
	var src: String = sess.path_join("residue").path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	var n: int = 256 * 256
	var words := PackedInt32Array()
	words.resize(n)
	words.fill(1000)
	var hm := BzHg2.HeightMap.new(1, 1, words)
	hm.write(src.path_join("sculp.hg2"))
	var paths: Dictionary = _paths(sess)
	_write_r16(str(paths["terrain"]), hm.data, true)
	_write_flags(str(paths["hg2_flags"]), hm.data)
	_write_json(str(paths["hg2_header"]), {
		"version": 1, "depth": 8, "zonesX": 1, "zonesZ": 1, "unknownA": 10, "unknownB": 0,
	})
	_write_json(str(paths["manifest"]), {
		"contract_version": 1, "stem": "sculp", "variants": [""],
		"mat_grid_x": 64, "mat_grid_z": 64,
	})
	_write_json(str(paths["dirty"]), {
		"terrain": true, "materials": false, "objects": {"": []}, "features": false, "meta": [],
	})
	# Edit one cell in the session buffer.
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(str(paths["terrain"]))
	raw.encode_u16(100 * 2, 1500)
	var tf := FileAccess.open(str(paths["terrain"]), FileAccess.WRITE)
	tf.store_buffer(raw)
	tf.close()
	var out_dir: String = tmp.path_join("out_terrain")
	var saved: Dictionary = BzSave.save_session(sess, out_dir)
	t.eq(saved.get("ok"), true, "dirty terrain save")
	t.ok((saved.get("regenerated", []) as Array).has("sculp.hg2"))
	t.ok((saved.get("warnings", []) as Array).has("terrain re-encoded from terrain.r16"))
	var rd: Dictionary = BzHg2.read_hg2(out_dir.path_join("sculp.hg2"))
	t.ok(bool(rd.get("ok")), "re-encoded hg2 readable")
	var out_hm: BzHg2.HeightMap = rd.get("heightmap")
	t.eq(out_hm.data[100] & 0x1FFF, 1500, "edited cell survived re-encode")
	t.eq(out_hm.data[0] & 0x1FFF, 1000)
	t.eq(out_hm.unknownA, 10, "unknownA preserved from residue header")


func _test_dirty_materials(t, tmp: String) -> void:
	var sess: String = tmp.path_join("dirty_m")
	var src: String = sess.path_join("residue").path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	var mat_n: int = 64 * 64
	var mat := PackedInt32Array()
	mat.resize(mat_n)
	mat.fill(0)
	mat[0] = 0x1000
	var grid := BzMat.MaterialGrid.new(mat, 64, 64)
	grid.write(src.path_join("paint.mat"))
	var paths: Dictionary = _paths(sess)
	_write_r16(str(paths["materials"]), grid.data, false)
	# Change a tile in the session buffer.
	var buf: PackedByteArray = FileAccess.get_file_as_bytes(str(paths["materials"]))
	buf.encode_u16(3 * 2, 0x2100)
	var mf := FileAccess.open(str(paths["materials"]), FileAccess.WRITE)
	mf.store_buffer(buf)
	mf.close()
	_write_json(str(paths["manifest"]), {
		"contract_version": 1, "stem": "paint", "variants": [""],
		"mat_grid_x": 64, "mat_grid_z": 64,
	})
	_write_json(str(paths["dirty"]), {
		"terrain": false, "materials": true, "objects": {"": []}, "features": false, "meta": [],
	})
	var out_dir: String = tmp.path_join("out_mat")
	var saved: Dictionary = BzSave.save_session(sess, out_dir)
	t.eq(saved.get("ok"), true)
	t.ok((saved.get("regenerated", []) as Array).has("paint.mat"))
	var rd: Dictionary = BzMat.MaterialGrid.read(out_dir.path_join("paint.mat"))
	t.ok(bool(rd.get("ok")))
	var out_g: BzMat.MaterialGrid = rd.get("grid")
	t.eq(out_g.data[0], 0x1000)
	t.eq(out_g.data[3], 0x2100, "edited tile re-encoded")


func _test_dirty_objects(t, tmp: String) -> void:
	var sess: String = tmp.path_join("dirty_o")
	var src: String = sess.path_join("residue").path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	var fixture: String = ProjectSettings.globalize_path("res://tests/gd/fixtures/bzn/untouched.bzn")
	DirAccess.copy_absolute(fixture, src.path_join("objmap.bzn"))
	var loaded: Dictionary = BzObjects.load_variant_objects(src.path_join("objmap.bzn"), "obj")
	t.ok(bool(loaded.get("ok")), "load fixture bzn")
	var records: Array = loaded.get("records", [])
	t.ok(records.size() >= 2)
	# Mutate the geyser (obj-0002).
	records[1]["x"] = 333.0
	records[1]["y"] = 44.0
	records[1]["z"] = 555.0
	records[1]["label"] = "moved_geyser"
	# Clone a new geyser from the residue same-class block.
	records.append({
		"id": "new-0001",
		"origin": "new",
		"prjid": "eggeizr1",
		"x": 200.0, "y": 100.0, "z": 200.0,
		"yaw_deg": 0.0,
		"team": 0,
		"label": "cloned_geyser",
		"up_convention": "upright",
		"pinned_y": false,
		"managed": false,
		"required": false,
		"template_verified": true,
		"placement_mode": "bzn",
	})
	# Unverified class → runtime spawn.
	records.append({
		"id": "new-0002",
		"origin": "new",
		"prjid": "howitzer",
		"x": 10.0, "y": 20.0, "z": 30.0,
		"yaw_deg": 0.0,
		"team": 0,
		"label": "runtime_gun",
		"template_verified": false,
		"placement_mode": "runtime",
	})
	var paths: Dictionary = _paths(sess)
	_write_json(str(paths["objects"]), {"": records})
	_write_json(str(paths["dirty"]), {
		"terrain": false, "materials": false,
		"objects": {"": ["obj-0002", "new-0001", "new-0002"]},
		"features": false, "meta": [],
	})
	_write_json(str(paths["manifest"]), {
		"contract_version": 1, "stem": "objmap", "variants": [""],
	})
	var out_dir: String = tmp.path_join("out_obj")
	var saved: Dictionary = BzSave.save_session(sess, out_dir)
	t.eq(saved.get("ok"), true, "dirty objects save")
	t.ok((saved.get("regenerated", []) as Array).has("objmap.bzn"))
	var text: String = FileAccess.get_file_as_string(out_dir.path_join("objmap.bzn"))
	t.ok(text.contains("moved_geyser"), "mutated label written")
	t.ok(text.contains("cloned_geyser"), "cloned object written")
	t.ok(text.contains("333"), "mutated x written")
	t.ok(not text.contains("howitzer"), "unverified class is not a BZN block")
	t.ok(FileAccess.file_exists(out_dir.path_join("objmapMAP.lua")), "runtime spawn lua")
	var lua: String = FileAccess.get_file_as_string(out_dir.path_join("objmapMAP.lua"))
	t.ok(lua.contains("BuildObject(\"howitzer\""), "runtime BuildObject")
	t.ok(lua.contains("RemovePilot"), "host-guarded RemovePilot")
	var warns: Array = saved.get("warnings", [])
	var saw_runtime := false
	for w in warns:
		if str(w).contains("runtime spawn"):
			saw_runtime = true
	t.ok(saw_runtime, "warning about runtime spawn")


func _test_features_copy(t, tmp: String) -> void:
	var sess: String = tmp.path_join("feat")
	var src: String = sess.path_join("residue").path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	_write_bytes(src.path_join("feat.trn"), "trn".to_utf8_buffer())
	_write_json(sess.path_join("manifest.json"), {"contract_version": 1, "stem": "feat", "variants": [""]})
	_write_json(sess.path_join("dirty.json"), {"terrain": false, "materials": false, "objects": {"": []}, "features": false, "meta": []})
	_write_json(sess.path_join("features.json"), {"water": [{"stem": "w1", "level_m": 92.0}], "plants": []})
	var out_dir: String = tmp.path_join("out_feat")
	var saved: Dictionary = BzSave.save_session(sess, out_dir)
	t.eq(saved.get("ok"), true)
	t.ok((saved.get("files", []) as Array).has("features.json"))
	t.ok(FileAccess.file_exists(out_dir.path_join("features.json")))
	t.eq((saved.get("features", {}) as Dictionary).get("water", []).size(), 1)


func _test_save_with_features(t, tmp: String) -> void:
	var sess: String = tmp.path_join("feat_gen")
	var src: String = sess.path_join("residue").path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	DirAccess.make_dir_recursive_absolute(sess.path_join("masks"))
	var hm: BzHg2.HeightMap = _pit_heightmap()
	hm.write(src.path_join("featmap.hg2"))
	var paths: Dictionary = _paths(sess)
	_write_r16(str(paths["terrain"]), hm.data, true)
	_write_flags(str(paths["hg2_flags"]), hm.data)
	_write_json(str(paths["hg2_header"]), {
		"version": 1, "depth": 8, "zonesX": 1, "zonesZ": 1, "unknownA": 10, "unknownB": 0,
	})
	var fixture: String = ProjectSettings.globalize_path("res://tests/gd/fixtures/bzn/untouched.bzn")
	DirAccess.copy_absolute(fixture, src.path_join("featmap.bzn"))
	DirAccess.copy_absolute(fixture, src.path_join("featmap_S.bzn"))
	_write_mask(sess.path_join("masks").path_join("wtr1.u8"), _pit_mask())
	_write_mask(sess.path_join("masks").path_join("plnt1.u8"), _flat_plant_mask())
	_write_json(sess.path_join("features.json"), {
		"water": [{
			"stem": "wtr1", "level_m": 70.0, "mask": "masks/wtr1.u8", "variant_scope": "all",
		}],
		"plants": [{
			"stem": "plnt1", "mask": "masks/plnt1.u8", "density": 16, "seed": 7,
		}],
	})
	_write_json(sess.path_join("manifest.json"), {
		"contract_version": 1, "stem": "featmap", "variants": ["", "_S"],
		"mat_grid_x": 64, "mat_grid_z": 64,
	})
	_write_json(sess.path_join("dirty.json"), {
		"terrain": false, "materials": false, "objects": {"": [], "_S": []},
		"features": false, "meta": [],
	})
	var out_dir: String = tmp.path_join("out_feat_gen")
	var saved: Dictionary = BzSave.save_session(sess, out_dir)
	t.eq(saved.get("ok"), true, "save-with-features ok: %s" % str(saved))
	if saved.get("ok") != true:
		return
	t.ok(saved.has("features"), "payload features block stays")
	t.eq((saved.get("features", {}) as Dictionary).get("water", []).size(), 1)
	var regen: Array = saved.get("regenerated", [])
	for name in ["wtr1.mesh", "wtr1.material", "wtr1.odf", "plnt1.mesh", "plnt1.material", "plnt1.odf"]:
		t.ok(FileAccess.file_exists(out_dir.path_join(name)), "emitted %s" % name)
		t.ok(regen.has(name), "regenerated lists %s" % name)
	t.ok(regen.has("featmap.bzn"), "base bzn regenerated with carriers")
	t.ok(regen.has("featmap_S.bzn"), "strategy bzn regenerated with carriers")
	_assert_one_carrier(t, out_dir.path_join("featmap.bzn"), "wtr1")
	_assert_one_carrier(t, out_dir.path_join("featmap.bzn"), "plnt1")
	_assert_one_carrier(t, out_dir.path_join("featmap_S.bzn"), "wtr1")
	_assert_one_carrier(t, out_dir.path_join("featmap_S.bzn"), "plnt1")
	var loaded: Dictionary = BzBzn.read_bzn(out_dir.path_join("featmap.bzn"))
	t.ok(bool(loaded.get("ok")), "emitted bzn readable")
	var bzn: BzBzn.BznFile = loaded.get("bznfile")
	var problems: PackedStringArray = bzn.validate()
	t.eq(problems.size(), 0, "validate: %s" % ", ".join(problems))
	var odf: String = FileAccess.get_file_as_string(out_dir.path_join("wtr1.odf"))
	t.ok(odf.contains('classLabel = "i76building2"'))


func _test_managed_carriers_not_duplicated(t, tmp: String) -> void:
	var sess: String = tmp.path_join("feat_dup")
	var src: String = sess.path_join("residue").path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	DirAccess.make_dir_recursive_absolute(sess.path_join("masks"))
	var hm: BzHg2.HeightMap = _pit_heightmap()
	hm.write(src.path_join("dupmap.hg2"))
	var paths: Dictionary = _paths(sess)
	_write_r16(str(paths["terrain"]), hm.data, true)
	_write_flags(str(paths["hg2_flags"]), hm.data)
	_write_json(str(paths["hg2_header"]), {
		"version": 1, "depth": 8, "zonesX": 1, "zonesZ": 1, "unknownA": 10, "unknownB": 0,
	})
	var fixture: String = ProjectSettings.globalize_path("res://tests/gd/fixtures/bzn/untouched.bzn")
	DirAccess.copy_absolute(fixture, src.path_join("dupmap.bzn"))
	_write_mask(sess.path_join("masks").path_join("wtr1.u8"), _pit_mask())
	_write_json(sess.path_join("features.json"), {
		"water": [{"stem": "wtr1", "level_m": 70.0, "mask": "masks/wtr1.u8", "variant_scope": "all"}],
		"plants": [],
	})
	_write_json(sess.path_join("manifest.json"), {
		"contract_version": 1, "stem": "dupmap", "variants": [""],
	})
	_write_json(sess.path_join("dirty.json"), {
		"terrain": false, "materials": false, "objects": {"": []}, "features": false, "meta": [],
	})
	var out1: String = tmp.path_join("out_dup1")
	var s1: Dictionary = BzSave.save_session(sess, out1)
	t.eq(s1.get("ok"), true, "first save ok")
	_assert_one_carrier(t, out1.path_join("dupmap.bzn"), "wtr1")
	# Simulate re-opening the previous save: residue now already has the carrier.
	DirAccess.copy_absolute(out1.path_join("dupmap.bzn"), src.path_join("dupmap.bzn"))
	var out2: String = tmp.path_join("out_dup2")
	var s2: Dictionary = BzSave.save_session(sess, out2)
	t.eq(s2.get("ok"), true, "second save ok")
	_assert_one_carrier(t, out2.path_join("dupmap.bzn"), "wtr1")
	var loaded: Dictionary = BzBzn.read_bzn(out2.path_join("dupmap.bzn"))
	var bzn: BzBzn.BznFile = loaded.get("bznfile")
	t.eq(bzn.validate().size(), 0, "second save still validates")


func _test_feature_stem_errors(t, tmp: String) -> void:
	var sess: String = tmp.path_join("feat_bad")
	var src: String = sess.path_join("residue").path_join("source")
	DirAccess.make_dir_recursive_absolute(src)
	_write_bytes(src.path_join("badmap.trn"), "trn".to_utf8_buffer())
	_write_json(sess.path_join("manifest.json"), {"contract_version": 1, "stem": "badmap", "variants": [""]})
	_write_json(sess.path_join("dirty.json"), {
		"terrain": false, "materials": false, "objects": {"": []}, "features": false, "meta": [],
	})
	_write_json(sess.path_join("features.json"), {
		"water": [{"stem": "badmap", "level_m": 70.0}],
		"plants": [],
	})
	var saved: Dictionary = BzSave.save_session(sess, tmp.path_join("out_bad"))
	t.ok(BzErrors.is_err(saved), "map-stem collision is an error")
	t.eq(saved["error"].get("code"), "stem_collision")


func _assert_one_carrier(t, bzn_path: String, stem: String) -> void:
	var loaded: Dictionary = BzBzn.read_bzn(bzn_path)
	t.ok(bool(loaded.get("ok")), "read %s" % bzn_path.get_file())
	var bzn: BzBzn.BznFile = loaded.get("bznfile")
	var n := 0
	var pos: Variant = null
	for obj in bzn.objects:
		var prj: String = "" if obj.prjid == null else str(obj.prjid)
		if prj == stem:
			n += 1
			pos = obj.position()
	t.eq(n, 1, "%s has exactly one %s carrier" % [bzn_path.get_file(), stem])
	if n == 1 and pos is Array and (pos as Array).size() >= 3:
		t.near(float(pos[0]), 0.0, 0.001, "%s carrier x" % stem)
		t.near(float(pos[2]), 0.0, 0.001, "%s carrier z" % stem)


func _pit_heightmap() -> BzHg2.HeightMap:
	var data := PackedInt32Array()
	data.resize(256 * 256)
	data.fill(1000)
	for z in range(40, 81):
		for x in range(40, 81):
			data[z * 256 + x] = 400
	return BzHg2.HeightMap.new(1, 1, data)


func _pit_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(256 * 256)
	for z in range(40, 81):
		for x in range(40, 81):
			mask[z * 256 + x] = 1
	return mask


func _flat_plant_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(256 * 256)
	mask.fill(1)
	for z in range(40, 81):
		for x in range(40, 81):
			mask[z * 256 + x] = 0
	return mask


func _write_mask(path: String, mask: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(mask)
		f.close()


func _write_json(path: String, payload: Variant) -> void:
	var text: String = JSON.stringify(payload, "  ") + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()


func _paths(sess: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(sess.path_join("residue").path_join("source"))
	DirAccess.make_dir_recursive_absolute(sess.path_join("masks"))
	return {
		"terrain": sess.path_join("terrain.r16"),
		"materials": sess.path_join("materials.u16"),
		"objects": sess.path_join("objects.json"),
		"dirty": sess.path_join("dirty.json"),
		"manifest": sess.path_join("manifest.json"),
		"hg2_header": sess.path_join("residue").path_join("hg2_header.json"),
		"hg2_flags": sess.path_join("residue").path_join("hg2_flags.u8"),
	}


func _write_r16(path: String, words: PackedInt32Array, mask_height: bool) -> void:
	var bytes := PackedByteArray()
	bytes.resize(words.size() * 2)
	for i in words.size():
		var v: int = words[i] & 0x1FFF if mask_height else words[i]
		bytes.encode_u16(i * 2, v & 0xFFFF)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)


func _write_flags(path: String, words: PackedInt32Array) -> void:
	var flags := PackedByteArray()
	flags.resize(words.size())
	for i in words.size():
		flags[i] = (words[i] >> 13) & 0xFF
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(flags)


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
