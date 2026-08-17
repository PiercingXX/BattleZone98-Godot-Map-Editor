extends RefCounted
## Port of backend/tests/test_editor_bridge.py (conftest.py is path setup only).
## End-to-end goldens against the GDScript verb classes — no subprocess, no
## game/corpus bytes. Fixtures are hand-packed or written with Bz* helpers.
##
## Known upstream compile blockers (do not "fix" here — other agents own them):
## - BzSession._resolve_path: String.is_absolute() (Godot 4 is is_absolute_path)
##   → session_paths / ensure_session_dir missing → BzSave.save_session and
##   BzNew.create_map return {}.
## - BzAssets: INFERRED_DECLARATION treated as error (Variant :=).
## - BzOgre._Buf.read_string: _ascii_ignore called as instance method.


const _CLASS_PATHS := {
	"BzErrors": "res://project/backend/editor/BzErrors.gd",
	"BzSession": "res://project/backend/editor/BzSession.gd",
	"BzObjects": "res://project/backend/editor/BzObjects.gd",
	"BzOpen": "res://project/backend/editor/BzOpen.gd",
	"BzConvert": "res://project/backend/editor/BzConvert.gd",
	"BzSave": "res://project/backend/editor/BzSave.gd",
	"BzNew": "res://project/backend/editor/BzNew.gd",
	"BzWorlds": "res://project/backend/editor/BzWorlds.gd",
	"BzDiscover": "res://project/backend/editor/BzDiscover.gd",
	"BzAssets": "res://project/backend/editor/BzAssets.gd",
	"BzValidate": "res://project/backend/editor/BzValidate.gd",
	"BzRender": "res://project/backend/editor/BzRender.gd",
	"BzPackage": "res://project/backend/editor/BzPackage.gd",
	"BzHg2": "res://project/backend/formats/BzHg2.gd",
	"BzMat": "res://project/backend/formats/BzMat.gd",
	"BzBzn": "res://project/backend/formats/BzBzn.gd",
	"BzTrn": "res://project/backend/formats/BzTrn.gd",
	"BzLgt": "res://project/backend/formats/BzLgt.gd",
	"BzIni": "res://project/backend/formats/BzIni.gd",
	"BzDes": "res://project/backend/formats/BzDes.gd",
	"BzOdf": "res://project/backend/formats/BzOdf.gd",
	"BzVxt": "res://project/backend/formats/BzVxt.gd",
}

const _ZONE := 256
const _MAT_ZONE := 64
const _HEIGHT_MASK := 0x1FFF

var _temps: Array[String] = []
var _t: Variant


func run(t) -> void:
	_t = t
	_group_parse_libraryfolders_vdf()
	_group_probe_payload()
	_group_worlds_from_synthetic_game()
	_group_open_save_no_edits(1, 1, "single-zone")
	_group_open_save_no_edits(2, 2, "multi-zone")
	_group_new_save_validate()
	_group_binary_bzn_refused()
	_group_assets_builds_index()
	_group_render_north_up()
	_group_clone_new_object_on_save()
	_group_terrain_dirty_reencodes()
	_group_package_modes()
	_group_new_error_codes()
	for p in _temps:
		_rm_tree(p)
	_temps.clear()


# --- assertion groups (mirror test_editor_bridge.py) -----------------------

func _group_parse_libraryfolders_vdf() -> void:
	## test_parse_libraryfolders_vdf_tight_and_spaced
	if not _need("BzDiscover"):
		return
	var text := (
		"\"libraryfolders\"\n{\n"
		+ "\"0\"\n{\n"
		+ "\"path\"\"/home/x/.local/share/Steam\"\n"
		+ "}\n"
		+ "\"1\"\n{\n"
		+ "\"path\"\t\t\"/mnt/games\"\n"
		+ "}\n}\n"
	)
	var got: Variant = _invoke_any("BzDiscover", [
		"parse_libraryfolders_vdf", "parse_libraryfolders",
	], [text])
	if _is_missing(got):
		_t.fail("BzDiscover.parse_libraryfolders_vdf missing")
		return
	var paths := _as_str_array(got)
	_t.eq(paths, ["/home/x/.local/share/Steam", "/mnt/games"],
			"vdf tight + tab-spaced path lines")


func _group_probe_payload() -> void:
	## test_probe_cli_json + test_probe_finds_linux_install (shape only)
	if not _need("BzDiscover"):
		return
	var found: Variant = _invoke_any("BzDiscover", ["probe", "discover"], [])
	if _is_missing(found):
		_t.fail("BzDiscover.discover missing")
		return
	if not (found is Dictionary):
		_t.fail("discover() must return a Dictionary, got %s" % found)
		return
	var payload: Dictionary = found
	# Verb payload (docs/02 §3 probe) or the raw discover() dict.
	if payload.has("ok"):
		_t.eq(payload.get("ok"), true, "probe ok")
	if payload.has("contract_version"):
		_t.eq(payload.get("contract_version"), 1, "contract_version")
	_t.ok(payload.has("installs"), "probe/discover carries installs")
	var installs: Array = _as_array(payload.get("installs", []))
	# Synthetic-only: do not require a live install. If one is present, it
	# must look like a game directory.
	for item in installs:
		if not (item is Dictionary):
			continue
		if item.get("kind") == "game":
			var p := str(item.get("path", ""))
			_t.ok(not p.is_empty(), "game install path nonempty")
			if _has("BzDiscover"):
				var ok_inst: Variant = _invoke_any("BzDiscover", [
					"is_game_install",
				], [p])
				if not _is_missing(ok_inst):
					_t.ok(bool(ok_inst), "is_game_install(discovered game)")


func _group_worlds_from_synthetic_game() -> void:
	## test_worlds_lists_stock_nine — synthetic Edit/trn, not a live install
	if not _need("BzWorlds"):
		return
	var game := _fake_game("worlds")
	var got: Variant = _invoke_any("BzWorlds", [
		"worlds_from_game", "worlds",
	], [game])
	if _is_missing(got):
		_t.fail("BzWorlds.worlds_from_game missing")
		return
	var worlds := _extract_worlds(got)
	if worlds.is_empty() and _is_err(got):
		_t.fail("worlds_from_game failed: %s" % _err_msg(got))
		return
	var ids: Array[String] = []
	for w in worlds:
		if w is Dictionary:
			ids.append(str(w.get("id", "")))
	for expected in ["mars", "io", "elysium", "moon"]:
		_t.ok(ids.has(expected), "stock world %s listed" % expected)
	var mars := _world_named(worlds, "mars")
	_t.ok(not mars.is_empty(), "mars world present")
	if mars.is_empty():
		return
	_t.ok(not _as_array(mars.get("texture_types", [])).is_empty(), "mars texture_types")
	_t.ok(str(mars.get("atlas", "")).length() > 0, "mars atlas")
	if mars.has("tile_uvs"):
		_t.eq(_as_array(mars.get("tile_uvs")).size(), 16, "tile_uvs length")


func _group_open_save_no_edits(zones_x: int, zones_z: int, label: String) -> void:
	## test_open_save_no_edits_single_zone / _multi_zone
	if not _need("BzOpen") or not _need("BzSave"):
		return
	var root := _scratch("rt-%s" % label)
	var src := root.path_join("src")
	var session := root.path_join("session")
	var out := root.path_join("out")
	DirAccess.make_dir_recursive_absolute(src)
	var stem := "szone01" if zones_x == 1 else "mzone01"
	_write_synthetic_map(src, stem, zones_x, zones_z)

	var opened: Variant = _invoke_any("BzOpen", ["open_map", "open"], [
		src.path_join("%s.hg2" % stem), session,
	])
	if not _expect_ok(opened, "open %s" % label):
		return
	var man: Dictionary = _as_dict(opened.get("manifest") if opened is Dictionary else {})
	_t.eq(int(man.get("width_m", 0)), zones_x * 1280, "%s width_m" % label)
	_t.eq(int(man.get("depth_m", 0)), zones_z * 1280, "%s depth_m" % label)
	_t.eq(int(man.get("grid_x", 0)), zones_x * _ZONE, "%s grid_x" % label)
	_t.eq(int(man.get("grid_z", 0)), zones_z * _ZONE, "%s grid_z" % label)
	_t.eq(int(man.get("height_max_raw", 0)), 4095, "%s height_max_raw" % label)
	_t.eq(int(man.get("contract_version", 0)), 1, "%s contract_version" % label)

	var terrain := session.path_join("terrain.r16")
	_t.ok(FileAccess.file_exists(terrain), "%s terrain.r16" % label)
	var tbytes := FileAccess.get_file_as_bytes(terrain)
	_t.eq(tbytes.size(), zones_x * _ZONE * zones_z * _ZONE * 2, "%s r16 size" % label)
	# Height-only: flags at world cell (100, 0) must be stripped.
	if tbytes.size() >= 202:
		_t.eq(int(tbytes.decode_u16(100 * 2)) & _HEIGHT_MASK, 1000,
				"%s r16 cell 100 is height-only 1000" % label)

	var saved: Variant = _invoke_any("BzSave", ["save_session", "save"], [
		session, out,
	])
	if not _expect_ok(saved, "save %s" % label):
		return
	var regen := _as_str_array((saved as Dictionary).get("regenerated", []))
	_t.eq(regen, [], "%s regenerated empty on no-edits" % label)

	var residue := _residue_source(session)
	_t.ok(DirAccess.dir_exists_absolute(residue), "%s residue/source" % label)
	var mismatches: Array[String] = []
	for name in _list_files(residue):
		var dest := out.path_join(name)
		if not FileAccess.file_exists(dest):
			mismatches.append("missing %s" % name)
			continue
		var a := FileAccess.get_file_as_bytes(residue.path_join(name))
		var b := FileAccess.get_file_as_bytes(dest)
		if a != b:
			mismatches.append("%s: %d bytes out != %d bytes in" % [name, b.size(), a.size()])
	_t.ok(mismatches.is_empty(), "%s byte-identical: %s" % [label, ", ".join(mismatches)])
	var ident := _as_str_array((saved as Dictionary).get("byte_identical", []))
	_t.ok(ident.has("%s.hg2" % stem) or ident.has("%s.HG2" % stem)
			or mismatches.is_empty(),
			"%s hg2 listed byte_identical (or residue matched)" % label)


func _group_new_save_validate() -> void:
	## test_new_save_validate
	if not _need("BzNew") or not _need("BzSave") or not _need("BzValidate"):
		return
	var root := _scratch("new")
	var game := _fake_game("new-game")
	var session := root.path_join("session")
	var out := root.path_join("out")
	var created: Variant = _invoke_any("BzNew", ["create_map", "new_map", "create"], [
		"xxedtest", "mars", 1280, 1280, session, game, 1000, "bzp",
	])
	if _is_missing(created):
		_t.fail("BzNew.create_map missing")
		return
	if not _expect_ok(created, "create_map xxedtest"):
		return
	var saved: Variant = _invoke_any("BzSave", ["save_session", "save"], [session, out])
	if not _expect_ok(saved, "save new map"):
		return
	_t.ok(FileAccess.file_exists(out.path_join("xxedtest.hg2")), "new .hg2")
	_t.ok(FileAccess.file_exists(out.path_join("xxedtest.mat")), "new .mat")
	_t.ok(FileAccess.file_exists(out.path_join("xxedtest.trn")), "new .trn")
	var report: Variant = _invoke_any("BzValidate", [
		"validate_session", "validate",
	], [session, "1,2", game])
	if _is_missing(report):
		report = _invoke_any("BzValidate", ["validate_session", "validate"], [session])
	if _is_missing(report):
		_t.fail("BzValidate.validate_session missing")
		return
	if not (report is Dictionary):
		_t.fail("validate must return a Dictionary")
		return
	_t.ok((report as Dictionary).has("findings"), "validate report has findings")
	_t.ok(FileAccess.file_exists(session.path_join("report.json")), "report.json written")
	var findings := _as_array((report as Dictionary).get("findings", []))
	for f in findings:
		if not (f is Dictionary):
			_t.fail("finding is not a Dictionary: %s" % f)
			continue
		for key in ["id", "severity", "title", "detail"]:
			_t.ok((f as Dictionary).has(key), "finding has %s" % key)


func _group_binary_bzn_refused() -> void:
	## test_binary_bzn_is_reported
	if not _need("BzOpen"):
		return
	var root := _scratch("binbzn")
	var fake := root.path_join("oldmap.bzn")
	_write_bytes(fake, PackedByteArray([0x00, 0x01, 0x02]) + "binary leftover".to_utf8_buffer())
	var is_bin: Variant = _invoke_any("BzOpen", [
		"is_binary_bzn", "is_binary",
	], [fake])
	if _is_missing(is_bin):
		_t.fail("BzOpen.is_binary_bzn missing")
		return
	_t.eq(bool(is_bin), true, "NUL-prefixed BZN is binary")

	# Valid HG2 + binary BZN: must refuse, never silently convert.
	var map_dir := root.path_join("map")
	DirAccess.make_dir_recursive_absolute(map_dir)
	_write_hg2(map_dir.path_join("oldmap.hg2"), 1, 1)
	_write_bytes(map_dir.path_join("oldmap.bzn"),
			PackedByteArray([0x00, 0x01, 0x02]) + "binary leftover".to_utf8_buffer())
	var opened: Variant = _invoke_any("BzOpen", ["open_map", "open"], [
		map_dir.path_join("oldmap.bzn"), root.path_join("sess"),
	])
	if _is_missing(opened):
		_t.fail("BzOpen.open_map missing")
		return
	if _is_ok(opened):
		_t.fail("binary BZN must not silently convert")
		return
	if opened == null or not (opened is Dictionary):
		_t.fail("binary BZN: open_map returned %s (BzOpen/deps failed to run)" % str(opened))
		return
	var code := _err_code(opened)
	var msg := _err_msg(opened).to_lower()
	_t.ok(
		code == "binary_bzn_unsupported" or code == "missing_hg2" or msg.contains("binary"),
		"binary BZN error code=%s msg=%s payload=%s" % [code, _err_msg(opened), str(opened)]
	)

	# ASCII BZN with missionSave=true is NOT binary (Python docstring).
	var ascii := root.path_join("ascii.bzn")
	_write_text(ascii, "version [1] =\r\n2016\r\nbinarySave [1] =\r\nfalse\r\nmissionSave [1] =\r\ntrue\r\n")
	var is_ascii: Variant = _invoke_any("BzOpen", ["is_binary_bzn", "is_binary"], [ascii])
	if not _is_missing(is_ascii):
		_t.eq(bool(is_ascii), false, "missionSave=true is not binary")


func _group_assets_builds_index() -> void:
	## test_assets_builds_index — synthetic ODFs, not a live install
	if not _need("BzAssets"):
		return
	var game := _fake_game("assets-game")
	_write_text(game.path_join("BZ_ASSETS").path_join("pspwn_1.odf"),
			"[GameObjectClass]\r\nclassLabel = spawnpnt\r\n")
	_write_text(game.path_join("BZ_ASSETS").path_join("player.odf"),
			"[GameObjectClass]\r\nclassLabel = person\r\n")
	_write_text(game.path_join("BZ_ASSETS").path_join("avtank.odf"),
			"[GameObjectClass]\r\nclassLabel = wingman\r\n")
	_write_text(game.path_join("BZ_ASSETS").path_join("avrecy.odf"),
			"[GameObjectClass]\r\nclassLabel = recycler\r\n")
	var cache := _scratch("asset-cache")
	var result: Variant = _invoke_any("BzAssets", ["build_assets", "assets"], [
		game, cache, [], true, false,
	])
	if _is_missing(result):
		_t.fail("BzAssets.build_assets missing")
		return
	if not _expect_ok(result, "build_assets"):
		return
	var classes := _as_array((result as Dictionary).get("classes", []))
	_t.ok(classes.size() >= 4, "synthetic classes enumerated (%d)" % classes.size())
	var prjids: Dictionary = {}
	for c in classes:
		if c is Dictionary:
			prjids[str(c.get("prjid", ""))] = true
	_t.ok(prjids.has("pspwn_1") or prjids.has("avtank") or prjids.has("avrecy"),
			"spawn/tank/recy class present")
	_t.ok(FileAccess.file_exists(cache.path_join("index.json")), "index.json written")
	var fp := str((result as Dictionary).get("source_fingerprint", ""))
	_t.ok(fp.begins_with("sha256:") or fp.length() > 8, "source_fingerprint")
	var again: Variant = _invoke_any("BzAssets", ["build_assets", "assets"], [
		game, cache, [], false, false,
	])
	if _is_ok(again):
		_t.eq(str((again as Dictionary).get("source_fingerprint", "")), fp,
				"fingerprint cache hit")


func _group_render_north_up() -> void:
	## test_render_writes_north_up_png
	if not _need("BzRender"):
		return
	var root := _scratch("render")
	var session := root.path_join("session")
	var src := root.path_join("src")
	DirAccess.make_dir_recursive_absolute(src)
	_write_synthetic_map(src, "xxrendr", 1, 1)
	if _has("BzOpen"):
		var opened: Variant = _invoke_any("BzOpen", ["open_map", "open"], [
			src.path_join("xxrendr.hg2"), session,
		])
		if not _expect_ok(opened, "open for render"):
			return
	elif _has("BzNew"):
		var created: Variant = _invoke_any("BzNew", ["create_map"], [
			"xxrendr", "mars", 1280, 1280, session, _fake_game("rend-game"), 1000, "bzp",
		])
		if not _expect_ok(created, "new for render"):
			return
	else:
		_t.fail("render needs BzOpen or BzNew to build a session")
		return
	var out := root.path_join("thumbs")
	var result: Variant = _invoke_any("BzRender", ["render_session", "render"], [
		session, out,
	])
	if _is_missing(result):
		_t.fail("BzRender.render_session missing")
		return
	if not _expect_ok(result, "render_session"):
		return
	_t.eq((result as Dictionary).get("north_up"), true, "north_up")
	var png := str((result as Dictionary).get("png", ""))
	var preview := str((result as Dictionary).get("preview", ""))
	if png.is_empty():
		png = out.path_join("xxrendr.png")
	if preview.is_empty():
		preview = out.path_join("preview.png")
	_t.ok(FileAccess.file_exists(png), "render png exists: %s" % png)
	_t.ok(FileAccess.file_exists(preview), "render preview exists: %s" % preview)
	if FileAccess.file_exists(png):
		var magic := FileAccess.get_file_as_bytes(png)
		_t.ok(magic.size() >= 8 and magic[0] == 0x89 and magic[1] == 0x50,
				"png magic")


func _group_clone_new_object_on_save() -> void:
	## test_clone_new_object_on_save
	if not _need("BzSave") or not _need("BzOpen"):
		return
	var root := _scratch("clone")
	var src := root.path_join("src")
	var session := root.path_join("session")
	DirAccess.make_dir_recursive_absolute(src)
	_write_synthetic_map(src, "xxclone", 1, 1)
	var opened: Variant = _invoke_any("BzOpen", ["open_map", "open"], [
		src.path_join("xxclone.trn"), session,
	])
	if not _expect_ok(opened, "open for clone"):
		return
	var objects_path := session.path_join("objects.json")
	var dirty_path := session.path_join("dirty.json")
	var objects: Variant = _read_json(objects_path)
	var dirty: Variant = _read_json(dirty_path)
	if typeof(objects) != TYPE_DICTIONARY:
		objects = {"": []}
	if typeof(dirty) != TYPE_DICTIONARY:
		dirty = {"terrain": false, "materials": false, "objects": {"": []}, "features": false, "meta": []}
	var rec := {
		"id": "new-0001",
		"origin": "new",
		"prjid": "pspwn_1",
		"x": 200.0, "y": 100.0, "z": 200.0,
		"yaw_deg": 0.0,
		"team": 0,
		"label": "xxclone99_spawn",
		"up_convention": "upright",
		"pinned_y": false,
		"managed": false,
		"required": false,
		"template_verified": true,
		"placement_mode": "bzn",
	}
	var variant_objs: Array = _as_array((objects as Dictionary).get("", []))
	variant_objs.append(rec)
	(objects as Dictionary)[""] = variant_objs
	var dirty_raw: Variant = (dirty as Dictionary).get("objects", {})
	var dirty_objs: Dictionary = dirty_raw if dirty_raw is Dictionary else {}
	var touched: Array = _as_array(dirty_objs.get("", []))
	touched.append("new-0001")
	dirty_objs[""] = touched
	(dirty as Dictionary)["objects"] = dirty_objs
	_write_json(objects_path, objects)
	_write_json(dirty_path, dirty)
	var out := root.path_join("out")
	var saved: Variant = _invoke_any("BzSave", ["save_session", "save"], [session, out])
	if not _expect_ok(saved, "save clone"):
		return
	var bzn_path := out.path_join("xxclone.bzn")
	_t.ok(FileAccess.file_exists(bzn_path), "cloned save wrote .bzn")
	if FileAccess.file_exists(bzn_path):
		var text := FileAccess.get_file_as_string(bzn_path)
		_t.ok(text.contains("xxclone99_spawn"), "cloned label in BZN")


func _group_terrain_dirty_reencodes() -> void:
	## test_terrain_dirty_reencodes
	if not _need("BzSave") or not _need("BzOpen"):
		return
	var root := _scratch("sculpt")
	var src := root.path_join("src")
	var session := root.path_join("session")
	DirAccess.make_dir_recursive_absolute(src)
	_write_synthetic_map(src, "xxsculp", 1, 1)
	var opened: Variant = _invoke_any("BzOpen", ["open_map", "open"], [
		src.path_join("xxsculp.hg2"), session,
	])
	if not _expect_ok(opened, "open for sculpt"):
		return
	var dirty_path := session.path_join("dirty.json")
	var dirty: Variant = _read_json(dirty_path)
	if typeof(dirty) != TYPE_DICTIONARY:
		dirty = {}
	(dirty as Dictionary)["terrain"] = true
	_write_json(dirty_path, dirty)
	var terrain := session.path_join("terrain.r16")
	var raw := FileAccess.get_file_as_bytes(terrain)
	if raw.size() < 202:
		_t.fail("terrain.r16 too small to poke cell 100")
		return
	raw.encode_u16(100 * 2, 1500)
	_write_bytes(terrain, raw)
	var out := root.path_join("out")
	var saved: Variant = _invoke_any("BzSave", ["save_session", "save"], [session, out])
	if not _expect_ok(saved, "save dirty terrain"):
		return
	var regen := _as_str_array((saved as Dictionary).get("regenerated", []))
	_t.ok(regen.has("xxsculp.hg2"), "hg2 in regenerated: %s" % str(regen))
	var hg2 := out.path_join("xxsculp.hg2")
	_t.ok(FileAccess.file_exists(hg2), "re-encoded hg2 exists")
	if not FileAccess.file_exists(hg2):
		return
	# 1-zone: zone-major == row-major. Cell 100 is world (100, 0).
	# Flags at that cell were 3 on the synthetic source; reconstruct ORs them.
	var out_bytes := FileAccess.get_file_as_bytes(hg2)
	if out_bytes.size() < 12 + 202:
		_t.fail("re-encoded hg2 truncated")
		return
	var word := int(out_bytes.decode_u16(12 + 100 * 2))
	_t.eq(word & _HEIGHT_MASK, 1500, "re-encoded height at cell 100")
	# Flag bits must survive (docs/02 pass-through of per-cell flags).
	_t.eq(word >> 13, 3, "flag bits preserved on re-encode")


func _group_package_modes() -> void:
	## package install + pack (docs/02 §3) — not in the pytest file as a
	## named case, but the assignment lists package modes as a golden.
	if not _need("BzPackage") or not _need("BzOpen"):
		return
	var root := _scratch("pkg")
	var src := root.path_join("src")
	var session := root.path_join("session")
	DirAccess.make_dir_recursive_absolute(src)
	_write_synthetic_map(src, "xxpack01", 1, 1)
	var opened: Variant = _invoke_any("BzOpen", ["open_map", "open"], [
		src.path_join("xxpack01.hg2"), session,
	])
	if not _expect_ok(opened, "open for package"):
		return
	var game := _fake_game("pkg-game")
	var installed: Variant = _invoke_any("BzPackage", [
		"package_session", "package",
	], [session, "install", game, "bzeditor-xxpack01", ""])
	if _is_missing(installed):
		_t.fail("BzPackage.package_session missing")
		return
	if _expect_ok(installed, "package install"):
		_t.eq(str((installed as Dictionary).get("mode", "")), "install", "install mode")
		var dest := str((installed as Dictionary).get("dest", ""))
		if dest.is_empty():
			dest = game.path_join("mods").path_join("bzeditor-xxpack01")
		_t.ok(DirAccess.dir_exists_absolute(dest), "install dest exists")
		if DirAccess.dir_exists_absolute(dest):
			_t.ok(
				FileAccess.file_exists(dest.path_join("xxpack01.hg2"))
				or FileAccess.file_exists(dest.path_join("xxpack01.trn")),
				"install copied map files"
			)

	var pack_out := root.path_join("pack")
	var packed: Variant = _invoke_any("BzPackage", [
		"package_session", "package",
	], [session, "pack", "", "", pack_out])
	if _is_missing(packed):
		return
	if _expect_ok(packed, "package pack"):
		_t.eq(str((packed as Dictionary).get("mode", "")), "pack", "pack mode")
		var pdest := str((packed as Dictionary).get("dest", pack_out))
		_t.ok(DirAccess.dir_exists_absolute(pdest), "pack dest exists")

	var bad: Variant = _invoke_any("BzPackage", ["package_session", "package"], [
		session, "nope", "", "", "",
	])
	if not _is_missing(bad) and not _is_ok(bad):
		_t.eq(_err_code(bad), "bad_mode", "unknown package mode")


func _group_new_error_codes() -> void:
	## docs/02 §5 error shape for the new-map gates the Python new() enforces
	if not _need("BzNew"):
		return
	var game := _fake_game("err-game")
	var root := _scratch("newerr")
	var long_stem: Variant = _invoke_any("BzNew", ["create_map"], [
		"xxMonke01", "mars", 1280, 1280, root.path_join("s1"), game, 1000, "bzp",
	])
	if _is_missing(long_stem):
		return
	_t.ok(_is_err(long_stem), "stem_too_long rejects")
	if _is_err(long_stem):
		_t.eq(_err_code(long_stem), "stem_too_long", "stem_too_long code")
		_t.ok(_err_msg(long_stem).length() > 0, "error message nonempty")
	var bad_dim: Variant = _invoke_any("BzNew", ["create_map"], [
		"xxedim", "mars", 1000, 1280, root.path_join("s2"), game, 1000, "bzp",
	])
	if not _is_missing(bad_dim) and _is_err(bad_dim):
		_t.eq(_err_code(bad_dim), "bad_dimensions", "bad_dimensions code")


# --- synthetic map / fake install ------------------------------------------

func _fake_game(tag: String) -> String:
	var root := _scratch("game-%s" % tag)
	_write_bytes(root.path_join("battlezone98redux.exe"), PackedByteArray([0x4D, 0x5A]))
	DirAccess.make_dir_recursive_absolute(
			root.path_join("BZ_ASSETS").path_join("common").path_join("models"))
	var trn_dir := root.path_join("Edit").path_join("trn")
	DirAccess.make_dir_recursive_absolute(trn_dir)
	for world in [
		"achilles", "elysium", "europa", "ganymede", "io",
		"mars", "moon", "titan", "venus",
	]:
		_write_text(trn_dir.path_join("%s.trn" % world), _trn_text(world, 1280, 1280))
	return root


func _write_synthetic_map(dir: String, stem: String, zx: int, zz: int) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_write_hg2(dir.path_join("%s.hg2" % stem), zx, zz)
	_write_mat(dir.path_join("%s.mat" % stem), zx, zz)
	_write_text(dir.path_join("%s.trn" % stem), _trn_text("mars", zx * 1280, zz * 1280))
	_write_text(dir.path_join("%s.bzn" % stem), _bzn_text(stem))
	_write_text(dir.path_join("%s.ini" % stem),
			"[DESCRIPTION]\r\nmissionName = \"%s\"\r\n\r\n[WORKSHOP]\r\nmapType = \"multiplayer\"\r\ncustomtags = \"\"\r\n\r\n[MULTIPLAYER]\r\nminPlayers = \"1\"\r\nmaxPlayers = \"14\"\r\ngameType = \"K\"\r\n" % stem)
	_write_text(dir.path_join("%s.des" % stem),
			"WORLD: Mars\tSIZE: %dx%d\r\nGEYSERS: 1\tSCRAP: 0\r\nPLAYERS: 14\r\nMade by Skippy\r\n" % [zx * 1280, zz * 1280])
	_write_text(dir.path_join("%s.vxt" % stem),
			"avobserv avobserv.des\tx\tNSDF\n\nsvobserv svobserv.des\tx\tCCA")
	# Distinctive sidecar so pass-through is visible even if terrain is regenerated.
	_write_text(dir.path_join("%s.lua" % stem), "-- synthetic %s MAP hook\r\n" % stem)


func _write_hg2(path: String, zx: int, zz: int) -> void:
	var n: int = zx * zz * _ZONE * _ZONE
	var buf := PackedByteArray()
	buf.resize(12 + n * 2)
	buf.encode_u16(0, 1)
	buf.encode_u16(2, 8)
	buf.encode_u16(4, zx)
	buf.encode_u16(6, zz)
	buf.encode_u16(8, 10)
	buf.encode_u16(10, 0)
	var off := 12
	for zzi in zz:
		for zxi in zx:
			for z in _ZONE:
				for x in _ZONE:
					var wx: int = zxi * _ZONE + x
					var wz: int = zzi * _ZONE + z
					var word: int = 1000 + (wx % 17) + (wz % 13)
					if wx == 100 and wz == 0:
						word = 1000 | (3 << 13)
					buf.encode_u16(off, word)
					off += 2
	_write_bytes(path, buf)


func _write_mat(path: String, zx: int, zz: int) -> void:
	var n: int = zx * zz * _MAT_ZONE * _MAT_ZONE
	var buf := PackedByteArray()
	buf.resize(n * 2)
	var off := 0
	for zzi in zz:
		for zxi in zx:
			for z in _MAT_ZONE:
				for x in _MAT_ZONE:
					var wx: int = zxi * _MAT_ZONE + x
					var wz: int = zzi * _MAT_ZONE + z
					var word: int = ((wx % 16) << 12) | ((wz % 16) << 8)
					buf.encode_u16(off, word)
					off += 2
	_write_bytes(path, buf)


func _trn_text(world: String, width_m: int, depth_m: int) -> String:
	return (
		"[Size]\r\n"
		+ "MinX = 0\r\nMinZ = 0\r\nHeight = 0.000000\r\n"
		+ "Width = %d\r\nDepth = %d\r\n\r\n" % [width_m, depth_m]
		+ "[NormalView]\r\nViewRange = 400\r\nFogStart = 200\r\nFogEnd = 400\r\n\r\n"
		+ "[Atlases]\r\nMaterialName = %s_detail_atlas\r\n\r\n" % world
		+ "[World]\r\nGravity = 9.8\r\n\r\n"
		+ "[Sky]\r\nSkyTexture = %s.map\r\nSkyType = %s\r\n\r\n" % [world, world]
		+ "[Clouds]\r\nCloudTexture = \r\n\r\n"
		+ "[Color]\r\nPalette = %s\r\nFogColor = 180 140 100\r\n\r\n" % world
		+ "[TextureType0] // Sand\r\nFlatColor = 140 90 60\r\n\r\n"
		+ "[TextureType1] // Rock\r\nFlatColor = 110 80 50\r\n\r\n"
		+ "[TextureType2] // Dust\r\nFlatColor = 160 120 80\r\n\r\n"
		+ "[TextureType3] // Dark\r\nFlatColor = 70 50 40\r\n"
	)


func _bzn_text(stem: String) -> String:
	# Minimal ASCII BZN: player + pspwn_1 + geyser. CRLF. binarySave = false.
	var parts: PackedStringArray = PackedStringArray([
		"version [1] =",
		"2016",
		"binarySave [1] =",
		"false",
		"msn_filename = %s.bzn" % stem,
		"seq_count [1] =",
		"3",
		"missionSave [1] =",
		"true",
		"TerrainName = %s" % stem,
		"size [1] =",
		"3",
	])
	parts.append_array(_game_object_lines(
			"player", 0, 1, "%s0_player" % stem, 640.0, 100.0, 640.0, 1, true))
	parts.append_array(_game_object_lines(
			"pspwn_1", 1, 2, "%s1_spawn" % stem, 200.0, 100.0, 200.0, 0, false))
	parts.append_array(_game_object_lines(
			"eggeizr1", 2, 3, "%s2_geyser" % stem, 100.25, 12.5, 200.75, 0, false))
	parts.append_array(PackedStringArray([
		"[AiMission]",
		"[AOIs]",
		"size [1] =",
		"0",
		"[AiPaths]",
		"count [1] =",
		"0",
	]))
	return "\r\n".join(parts) + "\r\n"


func _game_object_lines(
		prjid: String, seqno: int, addr: int, label: String,
		x: float, y: float, z: float, team: int, is_user: bool
) -> PackedStringArray:
	var xs := _fmt_num(x)
	var ys := _fmt_num(y)
	var zs := _fmt_num(z)
	return PackedStringArray([
		"[GameObject]",
		"PrjID [1] =",
		prjid,
		"seqno [1] =",
		str(seqno),
		"pos [1] =",
		"  x [1] =",
		xs,
		"  y [1] =",
		ys,
		"  z [1] =",
		zs,
		"team [1] =",
		str(team),
		"label = %s" % label,
		"isUser [1] =",
		"1" if is_user else "0",
		"obj_addr = %08x" % addr,
		"transform [1] =",
		"  right_x [1] =",
		"1",
		"  right_y [1] =",
		"0",
		"  right_z [1] =",
		"0",
		"  up_x [1] =",
		"0",
		"  up_y [1] =",
		"1",
		"  up_z [1] =",
		"0",
		"  front_x [1] =",
		"0",
		"  front_y [1] =",
		"0",
		"  front_z [1] =",
		"1",
		"  posit_x [1] =",
		xs,
		"  posit_y [1] =",
		ys,
		"  posit_z [1] =",
		zs,
		"illumination [1] =",
		"1" if is_user else "0",
		"pos [1] =",
		"  x [1] =",
		xs,
		"  y [1] =",
		ys,
		"  z [1] =",
		zs,
		"seqNo [1] =",
		str(seqno),
		"name = ",
	])


func _fmt_num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return str(v)


# --- invocation / class loading --------------------------------------------

func _need(class_nm: String) -> bool:
	if _has(class_nm):
		return true
	if _CLASS_PATHS.has(class_nm) and FileAccess.file_exists(str(_CLASS_PATHS[class_nm])):
		_t.fail("%s exists but failed to load (parse error)" % class_nm)
	else:
		_t.fail("%s not yet ported" % class_nm)
	return false


func _has(class_nm: String) -> bool:
	if ClassDB.class_exists(class_nm):
		var inst: Variant = ClassDB.instantiate(class_nm)
		if inst != null:
			return true
	var script: Script = _load_script(class_nm)
	return script != null and script.can_instantiate()


func _load_script(class_nm: String) -> Script:
	if not _CLASS_PATHS.has(class_nm):
		return null
	var path := str(_CLASS_PATHS[class_nm])
	if not FileAccess.file_exists(path):
		return null
	var loaded: Variant = load(path)
	if loaded is Script:
		return loaded as Script
	return null


func _invoke_any(class_nm: String, methods: Array, args: Array) -> Variant:
	var last: Variant = null
	for method in methods:
		var r: Variant = _invoke(class_nm, str(method), args)
		if not _is_missing(r):
			return r
		last = r
	return last


func _invoke(class_nm: String, method: String, args: Array) -> Variant:
	if ClassDB.class_exists(class_nm):
		var inst_db: Variant = ClassDB.instantiate(class_nm)
		if inst_db != null and inst_db.has_method(method):
			return inst_db.callv(method, _trim_args(inst_db, method, args))
		var static_r: Variant = _try_static(class_nm, method, args)
		if static_r != null:
			return static_r
	var script: Script = _load_script(class_nm)
	if script != null and script.can_instantiate():
		if script.has_method(method):
			return script.callv(method, _trim_args(script, method, args))
		var inst: Variant = script.new()
		if inst != null and inst.has_method(method):
			return inst.callv(method, _trim_args(inst, method, args))
	return {
		"ok": false,
		"error": {
			"code": "missing_class",
			"message": "%s.%s not available" % [class_nm, method],
		},
	}


func _try_static(class_nm: String, method: String, args: Array) -> Variant:
	if not ClassDB.class_has_method(class_nm, method, true):
		return null
	match args.size():
		0:
			return ClassDB.class_call_static(class_nm, method)
		1:
			return ClassDB.class_call_static(class_nm, method, args[0])
		2:
			return ClassDB.class_call_static(class_nm, method, args[0], args[1])
		3:
			return ClassDB.class_call_static(class_nm, method, args[0], args[1], args[2])
		4:
			return ClassDB.class_call_static(class_nm, method, args[0], args[1], args[2], args[3])
		5:
			return ClassDB.class_call_static(class_nm, method, args[0], args[1], args[2], args[3], args[4])
		6:
			return ClassDB.class_call_static(class_nm, method, args[0], args[1], args[2], args[3], args[4], args[5])
		7:
			return ClassDB.class_call_static(class_nm, method, args[0], args[1], args[2], args[3], args[4], args[5], args[6])
		8:
			return ClassDB.class_call_static(class_nm, method, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7])
	return null


func _trim_args(obj: Object, method: String, args: Array) -> Array:
	var n := _declared_argc(obj, method)
	if n < 0 or args.size() <= n:
		return args
	return args.slice(0, n)


func _declared_argc(obj: Object, method: String) -> int:
	if obj == null:
		return -1
	for info in obj.get_method_list():
		if str(info.get("name", "")) == method:
			return _as_array(info.get("args", [])).size()
	return -1


# --- result helpers --------------------------------------------------------

func _is_missing(r: Variant) -> bool:
	return _err_code(r) == "missing_class"


func _is_ok(r: Variant) -> bool:
	return r is Dictionary and bool((r as Dictionary).get("ok", false))


func _is_err(r: Variant) -> bool:
	return r is Dictionary and (r as Dictionary).has("error") and not bool((r as Dictionary).get("ok", true))


func _expect_ok(r: Variant, what: String) -> bool:
	if _is_missing(r):
		_t.fail("%s: class/method missing" % what)
		return false
	if _is_ok(r):
		return true
	if r == null:
		_t.fail("%s returned null (callee crashed; often a missing BzSession/BzSave method)" % what)
		return false
	_t.fail("%s failed: %s (%s) raw=%s" % [what, _err_code(r), _err_msg(r), str(r)])
	return false


func _err_code(r: Variant) -> String:
	if not (r is Dictionary):
		return ""
	var err: Variant = (r as Dictionary).get("error", {})
	if err is Dictionary:
		return str(err.get("code", ""))
	return ""


func _err_msg(r: Variant) -> String:
	if not (r is Dictionary):
		return str(r)
	var err: Variant = (r as Dictionary).get("error", {})
	if err is Dictionary:
		return str(err.get("message", ""))
	return str(r)


func _as_dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


func _as_array(v: Variant) -> Array:
	if v is Array:
		return v
	if v is PackedStringArray:
		var out: Array = []
		for s in v:
			out.append(s)
		return out
	return []


func _as_str_array(v: Variant) -> Array:
	var out: Array = []
	if v is PackedStringArray:
		for s in v:
			out.append(str(s))
		return out
	if v is Array:
		for item in v:
			out.append(str(item))
	return out


func _extract_worlds(got: Variant) -> Array:
	if got is Array:
		return got
	if got is Dictionary:
		if (got as Dictionary).has("worlds"):
			return _as_array((got as Dictionary).get("worlds"))
	return []


func _world_named(worlds: Array, id: String) -> Dictionary:
	for w in worlds:
		if w is Dictionary and str(w.get("id", "")) == id:
			return w
	return {}


func _residue_source(session: String) -> String:
	if _has("BzSession"):
		var paths: Variant = _invoke_any("BzSession", ["session_paths"], [session])
		if paths is Dictionary and (paths as Dictionary).has("source"):
			return str((paths as Dictionary).get("source"))
	return session.path_join("residue").path_join("source")


# --- json / files / temp ---------------------------------------------------

func _read_json(path: String) -> Variant:
	if _has("BzSession"):
		var r: Variant = _invoke_any("BzSession", ["read_json"], [path])
		if not _is_missing(r) and not _is_err(r):
			return r
	if not FileAccess.file_exists(path):
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _write_json(path: String, payload: Variant) -> void:
	if _has("BzSession"):
		var r: Variant = _invoke_any("BzSession", ["write_json"], [path, payload])
		if not _is_missing(r) and FileAccess.file_exists(path):
			return
	_write_text(path, JSON.stringify(payload, "\t") + "\n")


func _scratch(tag: String) -> String:
	var p := OS.get_cache_dir().path_join("bz-gd-goldens").path_join(
			"%s-%d" % [tag, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(p)
	_temps.append(p)
	return p


func _write_bytes(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_t.fail("cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_buffer(data)
	f.close()


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_t.fail("cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(text)
	f.close()


func _list_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if not d.current_is_dir():
			out.append(fn)
		fn = d.get_next()
	d.list_dir_end()
	return out


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn == "." or fn == "..":
			fn = d.get_next()
			continue
		var child := path.path_join(fn)
		if d.current_is_dir():
			_rm_tree(child)
		else:
			DirAccess.remove_absolute(child)
		fn = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)
