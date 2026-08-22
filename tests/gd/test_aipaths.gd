extends RefCounted
## AI paths: F3/corpus grammar parse, session sidecar, untouched tail, dirty emit.


const FIX_BZN := "res://tests/gd/fixtures/bzn/untouched.bzn"

## Synthetic .bzn fixtures are caught by .gitignore's blanket *.bzn ban
## (AGENTS.md rule 3), so a fresh checkout — and every CI runner — has none.
## The cases that need one report SKIP instead of asserting against nothing.
const NEEDS_BZN_FIXTURE := "no local .bzn fixture (gitignored; see fixtures/bzn/README.txt)"


func run(t) -> void:
	_parse_grammar(t)
	_parse_unlabeled(t)
	_emit_roundtrip(t)
	_invariants(t)
	_respawn_name(t)
	_session_sidecar(t)
	_untouched_tail_identity(t)
	_dirty_writer(t)
	_mapstate_undo(t)
	_overlay_kind(t)
	await _view_menu(t)


func _parse_grammar(t) -> void:
	var parsed: Dictionary = BzOpen.parse_aipaths_text(_fixture_two_paths())
	t.eq(parsed.get("ok"), true, "parse ok")
	t.eq(int(parsed.get("count", -1)), 2, "declared count")
	var paths: Array = parsed.get("paths", [])
	t.eq(paths.size(), 2, "two [AiPath] blocks")
	t.eq(str(paths[0].get("name", "")), "edge_path")
	t.eq(bool(paths[0].get("has_label", false)), true)
	t.eq(str(paths[0].get("old_ptr", "")), "00000011")
	t.eq(str(paths[0].get("pathType", "")), "00000000")
	t.eq(int(paths[0].get("size", 0)), 9)
	t.eq((paths[0].get("points", []) as Array).size(), 2)
	t.near(float(paths[0]["points"][0][0]), 100.5)
	t.near(float(paths[0]["points"][0][1]), 200.25)
	t.near(float(paths[0]["points"][1][0]), 300.0)
	t.near(float(paths[0]["points"][1][1]), 400.5)
	t.eq(str(paths[1].get("name", "")), "spawn_30_1")
	t.eq((paths[1].get("points", []) as Array).size(), 1)
	t.near(float(paths[1]["points"][0][0]), 640.0)
	t.near(float(paths[1]["points"][0][1]), 640.0)
	var empty: Dictionary = BzOpen.parse_aipaths_text("[AiPaths]\r\ncount [1] =\r\n0\r\n")
	t.eq((empty.get("paths", []) as Array).size(), 0, "count 0")
	t.eq(int(empty.get("count", -1)), 0)
	var missing: Dictionary = BzOpen.parse_aipaths_text("version [1] =\n2016\n")
	t.eq((missing.get("paths", []) as Array).size(), 0, "no section")


func _parse_unlabeled(t) -> void:
	var parsed: Dictionary = BzOpen.parse_aipaths_text(_fixture_unlabeled())
	var paths: Array = parsed.get("paths", [])
	t.eq(paths.size(), 1)
	t.eq(str(paths[0].get("name", "")), "")
	t.eq(bool(paths[0].get("has_label", true)), false, "no label field")
	t.eq((paths[0].get("points", []) as Array).size(), 1)
	t.near(float(paths[0]["points"][0][0]), 10.0)
	t.near(float(paths[0]["points"][0][1]), 20.0)


func _emit_roundtrip(t) -> void:
	if not t.require_files([FIX_BZN], NEEDS_BZN_FIXTURE):
		return
	var parsed: Dictionary = BzOpen.parse_aipaths_text(_fixture_two_paths())
	var paths: Array = parsed.get("paths", [])
	var emitted: String = BzOpen.emit_aipaths_block(paths, "\r\n")
	t.ok(emitted.begins_with("[AiPaths]\r\ncount [1] =\r\n2\r\n"), "header")
	t.ok(emitted.contains("old_ptr = 00000011"), "preserve old_ptr")
	t.ok(emitted.contains("label = edge_path"), "label")
	t.ok(emitted.contains("size [1] =\r\n9\r\n"), "size is label length")
	t.ok(emitted.contains("points [2] ="), "points count header")
	t.ok(emitted.contains("  x [1] ="), "two-space x indent")
	t.ok(emitted.contains("pathType = 00000000"), "pathType")
	var again: Dictionary = BzOpen.parse_aipaths_text(emitted)
	t.eq((again.get("paths", []) as Array).size(), 2)
	t.eq(str(again["paths"][0].get("name", "")), "edge_path")
	t.near(float(again["paths"][0]["points"][0][0]), 100.5)
	t.eq(BzOpen.aipaths_invariants(again.get("paths", [])).size(), 0)

	var unlabeled: Array = BzOpen.parse_aipaths_text(_fixture_unlabeled()).get("paths", [])
	var uemit: String = BzOpen.emit_aipaths_block(unlabeled, "\r\n")
	t.ok(not uemit.contains("label ="), "unlabeled omit label")
	t.ok(not uemit.contains("size [1] ="), "unlabeled omit size")
	var up: Dictionary = BzOpen.parse_aipaths_text(uemit)
	t.eq(bool(up["paths"][0].get("has_label", true)), false)

	var spliced: String = BzOpen.splice_aipaths_text(_host_bzn_empty_paths(), paths)
	t.ok(spliced.contains("[AiMission]"), "mission kept")
	t.ok(spliced.contains("[AOIs]"), "AOIs kept")
	t.ok(spliced.contains("size [1] =\r\n0\r\n[AiPaths]"), "AOIs size 0 kept")
	t.ok(spliced.contains("label = edge_path"), "paths spliced")
	t.ok(not spliced.contains("[AiPaths]\r\ncount [1] =\r\n0\r\n[AiPath]"), "old empty block gone")


func _invariants(t) -> void:
	var bad := [{
		"name": "ab",
		"has_label": true,
		"size": 9,
		"pointCount": 3,
		"points": [[0.0, 0.0]],
	}]
	var probs: PackedStringArray = BzOpen.aipaths_invariants(bad)
	t.ok(probs.size() >= 2, "size + pointCount")
	t.ok(BzOpen.next_old_ptr([]).ends_with("11") or BzOpen.next_old_ptr([]) == "00000011")
	t.eq(BzOpen.next_old_ptr([{"old_ptr": "00000014"}]), "00000015")


func _respawn_name(t) -> void:
	t.ok(BzOpen.is_respawn_path_name("foo_30_1"))
	t.ok(BzOpen.is_respawn_path_name("recy_15_2"))
	t.ok(not BzOpen.is_respawn_path_name("edge_path"))
	t.ok(not BzOpen.is_respawn_path_name("spawn_30"))
	t.ok(not BzOpen.is_respawn_path_name(""))


func _session_sidecar(t) -> void:
	if not t.require_files([FIX_BZN], NEEDS_BZN_FIXTURE):
		return
	var tmp: String = OS.get_temp_dir().path_join("bz_aip_open_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var src: String = tmp.path_join("src")
	DirAccess.make_dir_recursive_absolute(src)
	_write_hg2(src.path_join("synmap.hg2"), _flat_hm(1, 1, 1000))
	_write_mat(src.path_join("synmap.mat"), 64, 64, 0)
	_write_text(src.path_join("synmap.trn"), "[Size]\r\nWidth = 1280\r\n")
	_write_text(src.path_join("synmap.bzn"), _host_bzn_with_paths())
	_write_text(src.path_join("synmap_S.bzn"), _host_bzn_empty_paths())
	var residue_bzn: PackedByteArray = FileAccess.get_file_as_bytes(src.path_join("synmap.bzn"))
	var sess: String = tmp.path_join("sess")
	var opened: Dictionary = BzOpen.open_map(src.path_join("synmap.trn"), sess)
	t.eq(opened.get("ok"), true, "open: %s" % str(opened))
	if opened.get("ok") != true:
		_rm_rf(tmp)
		return
	t.ok(FileAccess.file_exists(sess.path_join("aipaths.json")), "sidecar written")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(sess.path_join("aipaths.json")))
	t.ok(typeof(data) == TYPE_DICTIONARY)
	var paths: Array = BzOpen.paths_of(data, "")
	t.eq(paths.size(), 2, "DM paths")
	t.eq(str(paths[0].get("name", "")), "edge_path")
	var s_paths: Array = BzOpen.paths_of(data, "_S")
	t.eq(s_paths.size(), 0, "_S empty")
	t.eq(data.get("paths", []).size(), 2, "top-level paths mirrors default")
	var dirty: Variant = JSON.parse_string(FileAccess.get_file_as_string(sess.path_join("dirty.json")))
	t.eq(bool((dirty.get("aipaths", {}) as Dictionary).get("", true)), false, "aipaths not dirty")
	var residue: String = sess.path_join("residue").path_join("source").path_join("synmap.bzn")
	t.ok(FileAccess.get_file_as_bytes(residue) == residue_bzn, "residue BZN untouched")
	_rm_rf(tmp)


func _untouched_tail_identity(t) -> void:
	if not t.require_files([FIX_BZN], NEEDS_BZN_FIXTURE):
		return
	var tmp: String = OS.get_temp_dir().path_join("bz_aip_id_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var src: String = tmp.path_join("src")
	DirAccess.make_dir_recursive_absolute(src)
	_write_hg2(src.path_join("idmap.hg2"), _flat_hm(1, 1, 1000))
	_write_mat(src.path_join("idmap.mat"), 64, 64, 0)
	_write_text(src.path_join("idmap.trn"), "[Size]\r\nWidth = 1280\r\n")
	var original := _host_bzn_with_paths()
	_write_text(src.path_join("idmap.bzn"), original)
	var sess: String = tmp.path_join("sess")
	var opened: Dictionary = BzOpen.open_map(src.path_join("idmap.trn"), sess)
	t.eq(opened.get("ok"), true, "open for identity")
	if opened.get("ok") != true:
		_rm_rf(tmp)
		return
	var out_dir: String = tmp.path_join("out")
	var saved: Dictionary = BzSave.save_session(sess, out_dir)
	t.eq(saved.get("ok"), true, "save ok")
	t.ok((saved.get("byte_identical", []) as Array).has("idmap.bzn"), "bzn listed identical")
	t.ok(
		FileAccess.get_file_as_bytes(src.path_join("idmap.bzn"))
		== FileAccess.get_file_as_bytes(out_dir.path_join("idmap.bzn")),
		"untouched BZN byte-identical"
	)
	_rm_rf(tmp)


func _dirty_writer(t) -> void:
	if not t.require_files([FIX_BZN], NEEDS_BZN_FIXTURE):
		return
	var tmp: String = OS.get_temp_dir().path_join("bz_aip_wr_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var src: String = tmp.path_join("src")
	DirAccess.make_dir_recursive_absolute(src)
	_write_hg2(src.path_join("wrmap.hg2"), _flat_hm(1, 1, 1000))
	_write_mat(src.path_join("wrmap.mat"), 64, 64, 0)
	_write_text(src.path_join("wrmap.trn"), "[Size]\r\nWidth = 1280\r\n")
	_write_text(src.path_join("wrmap.bzn"), _host_bzn_with_paths())
	var sess: String = tmp.path_join("sess")
	var opened: Dictionary = BzOpen.open_map(src.path_join("wrmap.trn"), sess)
	t.eq(opened.get("ok"), true)
	if opened.get("ok") != true:
		_rm_rf(tmp)
		return
	var aip_path: String = sess.path_join("aipaths.json")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(aip_path))
	var paths: Array = BzOpen.paths_of(data, "")
	t.ok(paths.size() >= 1)
	paths[0]["points"][0] = [111.0, 222.0]
	var variants: Dictionary = data.get("variants", {})
	if variants.has(""):
		variants[""] = {"paths": paths}
		data["variants"] = variants
	data["paths"] = paths
	_write_json(aip_path, data)
	var dirty: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sess.path_join("dirty.json")))
	dirty["aipaths"] = {"": true}
	_write_json(sess.path_join("dirty.json"), dirty)
	var out_dir: String = tmp.path_join("out")
	var saved: Dictionary = BzSave.save_session(sess, out_dir)
	t.eq(saved.get("ok"), true, "dirty save: %s" % str(saved))
	t.ok((saved.get("regenerated", []) as Array).has("wrmap.bzn"), "bzn regenerated")
	var out_text: String = FileAccess.get_file_as_string(out_dir.path_join("wrmap.bzn"))
	t.ok(out_text.contains("[AiMission]"), "mission preserved")
	t.ok(out_text.contains("[AOIs]"), "AOIs preserved")
	t.ok(out_text.contains("111") and out_text.contains("222"), "moved point emitted")
	t.ok(out_text.contains("label = edge_path"), "sibling path kept")
	var parsed: Dictionary = BzOpen.parse_aipaths_text(out_text)
	t.eq((parsed.get("paths", []) as Array).size(), 2)
	t.near(float(parsed["paths"][0]["points"][0][0]), 111.0)
	t.eq(BzOpen.aipaths_invariants(parsed.get("paths", [])).size(), 0)
	var loaded: Dictionary = BzBzn.read_bzn(out_dir.path_join("wrmap.bzn"))
	t.ok(bool(loaded.get("ok", false)), "rewritten bzn readable")
	var bzn: BzBzn.BznFile = loaded.get("bznfile")
	t.ok(bzn != null)
	if bzn != null:
		var problems: PackedStringArray = bzn.validate()
		t.eq(problems.size(), 0, "BznFile invariants: %s" % ", ".join(problems))
	_rm_rf(tmp)


func _mapstate_undo(t) -> void:
	var saved_session := MapState.has_session
	var saved_paths: Dictionary = MapState.aipaths.duplicate(true)
	var saved_dirty: Dictionary = MapState.dirty.duplicate(true)
	var saved_variant := MapState.active_variant
	UndoStack.clear()
	MapState.has_session = true
	MapState.active_variant = ""
	MapState.aipaths = {
		"paths": [],
		"variants": {"": {"paths": []}},
	}
	MapState.dirty = {"aipaths": {"": false}}
	MapState.width_m = 1280
	MapState.depth_m = 1280
	var before: Array = []
	var rec: Dictionary = MapState.default_new_path("")
	rec["size"] = str(rec.get("name", "")).length()
	var after: Array = [rec]
	var cmd := AiPathCommand.snapshot_and_apply(
		AiPathCommand.Kind.ADD_PATH, "", before, after, 0, 0
	)
	UndoStack.push(cmd)
	t.eq(MapState.active_paths().size(), 1, "add path")
	t.eq(str(MapState.active_paths()[0].get("name", "")).begins_with("path_"), true)
	t.eq(cmd.describe(), "add AI path")
	t.ok(bool((MapState.dirty.get("aipaths", {}) as Dictionary).get("", false)), "dirty after add")
	UndoStack.undo()
	t.eq(MapState.active_paths().size(), 0, "undo add")
	UndoStack.redo()
	t.eq(MapState.active_paths().size(), 1, "redo add")
	var before2 := AiPathCommand._dup(MapState.active_paths())
	var after2 := AiPathCommand._dup(before2)
	after2[0]["points"][0] = [5.0, 6.0]
	var move := AiPathCommand.snapshot_and_apply(
		AiPathCommand.Kind.MOVE_POINT, "", before2, after2, 0, 0
	)
	UndoStack.push(move)
	t.near(float(MapState.active_paths()[0]["points"][0][0]), 5.0)
	t.eq(move.describe(), "move AI path point")
	UndoStack.undo()
	t.near(float(MapState.active_paths()[0]["points"][0][0]), float(before2[0]["points"][0][0]))
	UndoStack.clear()
	MapState.has_session = saved_session
	MapState.aipaths = saved_paths
	MapState.dirty = saved_dirty
	MapState.active_variant = saved_variant


func _overlay_kind(t) -> void:
	t.eq(AiPathOverlay.kind_of({"name": "edge_path", "has_label": true}), "nav")
	t.eq(AiPathOverlay.kind_of({"name": "foo_30_1", "has_label": true}), "respawn")
	t.eq(AiPathOverlay.kind_of({"name": "", "has_label": false}), "unlabeled")
	t.ok(AiPathOverlay.is_editable({"name": "edge_path", "has_label": true}))
	t.ok(not AiPathOverlay.is_editable({"name": "", "has_label": false}))


## The AI-paths toggle used to be an item in the top bar's View menu. It is a
## checkbox in the bottom-right ViewPanel now (ViewPanel.SIMPLE plus the three
## special-cased keys), so this drives that instead. Until it was rewritten it
## asked TopBar for a "View" MenuButton, got null, and took the whole file
## down with it — silently, because a GDScript runtime error raises no
## assertion and the runner scored the file as a pass.
func _view_menu(t) -> void:
	AiPathOverlay.enabled = false
	var saved_session := MapState.has_session
	var saved_flag := Settings.view_aipaths
	MapState.has_session = false
	var panel: Node = load("res://project/ui/view/ViewPanel.tscn").instantiate()
	t.tree.root.add_child(panel)
	await t.tree.process_frame

	var check: CheckBox = panel.find_child("ViewAipaths", true, false)
	t.ok(check != null, "the view panel carries an AI paths checkbox")
	if check == null:
		panel.queue_free()
		MapState.has_session = saved_session
		return
	t.eq(check.text, "AI paths")
	t.ok(check.disabled, "AI paths disabled with no map")
	t.eq(check.tooltip_text, "Open a map first")

	# A disabled checkbox cannot be clicked, but the handler refuses anyway —
	# refresh() is the guard, so drive the signal directly.
	panel._on_toggled(true, "aipaths")
	t.eq(AiPathOverlay.enabled, false, "disabled toggle does not flip")

	MapState.has_session = true
	panel.refresh()
	t.ok(not check.disabled, "enabled once a map is open")
	t.eq(check.tooltip_text, "", "and the reason-why tooltip goes away")

	check.button_pressed = true
	t.ok(AiPathOverlay.enabled, "view panel → AI paths on")
	t.ok(Settings.view_aipaths, "and the setting follows")
	check.button_pressed = false
	t.ok(not AiPathOverlay.enabled, "second click off")

	panel.queue_free()
	await t.tree.process_frame
	MapState.has_session = saved_session
	AiPathOverlay.enabled = false
	Settings.view_aipaths = saved_flag


func _fixture_two_paths() -> String:
	return (
		"[AiPaths]\r\ncount [1] =\r\n2\r\n"
		+ "[AiPath]\r\nold_ptr = 00000011\r\nsize [1] =\r\n9\r\n"
		+ "label = edge_path\r\npointCount [1] =\r\n2\r\npoints [2] =\r\n"
		+ "  x [1] =\r\n100.5\r\n  z [1] =\r\n200.25\r\n"
		+ "  x [1] =\r\n300\r\n  z [1] =\r\n400.5\r\n"
		+ "pathType = 00000000\r\n"
		+ "[AiPath]\r\nold_ptr = 00000012\r\nsize [1] =\r\n10\r\n"
		+ "label = spawn_30_1\r\npointCount [1] =\r\n1\r\npoints [1] =\r\n"
		+ "  x [1] =\r\n640\r\n  z [1] =\r\n640\r\n"
		+ "pathType = 00000000\r\n"
	)


func _fixture_unlabeled() -> String:
	return (
		"[AiPaths]\r\ncount [1] =\r\n1\r\n"
		+ "[AiPath]\r\nold_ptr = 00000011\r\n"
		+ "pointCount [1] =\r\n1\r\npoints [1] =\r\n"
		+ "  x [1] =\r\n10\r\n  z [1] =\r\n20\r\n"
		+ "pathType = 00000000\r\n"
	)


func _host_bzn_empty_paths() -> String:
	return FileAccess.get_file_as_string(ProjectSettings.globalize_path(FIX_BZN))


func _host_bzn_with_paths() -> String:
	var base: String = _host_bzn_empty_paths()
	if not base.ends_with("\n"):
		base += "\n"
	# Fixture uses LF. Splice must keep the mission/AOIs prefix.
	return BzOpen.splice_aipaths_text(base, BzOpen.parse_aipaths_text(_fixture_two_paths()).get("paths", []))


func _flat_hm(zones_x: int, zones_z: int, fill: int) -> BzHg2.HeightMap:
	var n: int = zones_x * BzHg2.ZONE_SIZE * zones_z * BzHg2.ZONE_SIZE
	var data := PackedInt32Array()
	data.resize(n)
	data.fill(fill)
	return BzHg2.HeightMap.new(zones_x, zones_z, data, 1, 8, 10, 0)


func _write_hg2(path: String, hm: BzHg2.HeightMap) -> void:
	BzHg2.write_hg2(path, hm)


func _write_mat(path: String, grid_x: int, grid_z: int, first: int) -> void:
	var data := PackedInt32Array()
	data.resize(grid_x * grid_z)
	data.fill(0)
	if data.size() > 0:
		data[0] = first
	var grid := BzMat.MaterialGrid.new(data, grid_z, grid_x)
	BzMat.write_mat(path, grid)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


func _write_json(path: String, payload: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	var text: String = JSON.stringify(payload, "  ")
	if not text.ends_with("\n"):
		text += "\n"
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
