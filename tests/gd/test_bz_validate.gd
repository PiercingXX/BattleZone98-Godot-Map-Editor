extends RefCounted
## End-to-end `BzValidate.validate_session` against synthetic sessions.


func run(t) -> void:
	_test_missing_session(t)
	_test_clean_session(t)
	_test_findings_and_report(t)
	_test_dirty_without_save(t)


func _test_missing_session(t) -> void:
	var missing: String = OS.get_temp_dir().path_join("bz-no-session-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(missing)
	var r: Dictionary = BzValidate.validate_session(missing)
	t.eq(r.get("ok"), false)
	t.ok(BzErrors.is_err(r), "missing manifest is an error payload")
	t.eq(r["error"]["code"], "no_session")
	t.ok(str(r["error"]["message"]).contains("no manifest.json"), r["error"]["message"])
	t.eq(r["error"].get("path", ""), missing)


func _test_clean_session(t) -> void:
	var session: String = _make_session("clean", 100.0)
	var r: Dictionary = BzValidate.validate_session(session)
	t.eq(r.get("ok"), true, "clean session ok: %s" % JSON.stringify(r))
	t.ok(r.has("findings"), "payload has findings")
	t.eq((r["findings"] as Array).size(), 0)
	var report_path: String = _session_paths(session)["report"]
	t.ok(FileAccess.file_exists(report_path), "report.json written")
	var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	t.ok(typeof(stored) == TYPE_DICTIONARY)
	t.eq(stored.get("ok"), true)
	t.eq((stored.get("findings", []) as Array).size(), 0)


func _test_findings_and_report(t) -> void:
	var session: String = _make_session("floaty", 250.0)
	var r: Dictionary = BzValidate.validate_session(session, "1,2")
	t.eq(r.get("ok"), false, "off-ground objects are errors")
	t.ok(r.has("findings"))
	var findings: Array = r["findings"]
	t.ok(findings.size() >= 1, "at least one finding")
	var f: Dictionary = findings[0]
	t.ok(str(f.get("id", "")).begins_with("V"), "id Vn")
	t.eq(f.get("severity"), "error")
	t.ok(str(f.get("title", "")).length() <= 96)
	t.ok(str(f.get("detail", "")).contains("from terrain height"))
	t.eq(f.get("world_pos"), null)
	t.eq(f.get("object_id"), null)
	t.eq(f.get("variant"), null)
	var stored: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(str(_session_paths(session)["report"]))
	)
	t.eq((stored as Dictionary).get("ok"), false)
	t.eq(((stored as Dictionary).get("findings") as Array).size(), findings.size())


func _test_dirty_without_save(t) -> void:
	var session: String = _make_session("dirty", 100.0)
	var paths: Dictionary = _session_paths(session)
	var dirty := {
		"terrain": false,
		"materials": false,
		"objects": {"": []},
		"features": false,
		"meta": ["ini.missionName"],
	}
	_write_json(str(paths["dirty"]), dirty)
	var r: Dictionary = BzValidate.validate_session(session)
	t.ok(
		r.has("findings") or BzErrors.is_err(r),
		"dirty session returns findings or a save error, not a crash"
	)
	if r.has("findings") and not BzErrors.is_err(r):
		t.eq((r["findings"] as Array).size(), 0, "materialized clean source still validates")


func _make_session(stem: String, player_y: float) -> String:
	var session: String = OS.get_temp_dir().path_join(
		"bz-sess-%s-%d" % [stem, Time.get_ticks_usec()]
	)
	var paths: Dictionary = _session_paths(session)
	for key in ["root", "masks", "residue", "source"]:
		DirAccess.make_dir_recursive_absolute(str(paths[key]))
	_write_json(str(paths["manifest"]), {
		"contract_version": 1,
		"stem": stem,
		"width_m": 1280,
		"depth_m": 1280,
		"grid_x": 256,
		"grid_z": 256,
	})
	_write_json(str(paths["dirty"]), {
		"terrain": false,
		"materials": false,
		"objects": {"": []},
		"features": false,
		"meta": [],
	})
	var src: String = str(paths["source"])
	DirAccess.make_dir_recursive_absolute(src)
	_write_clean_map(src, stem, player_y)
	return session


func _write_clean_map(dir: String, stem: String, player_y: float) -> void:
	var data := PackedInt32Array()
	data.resize(256 * 256)
	data.fill(1000)
	BzHg2.HeightMap.new(1, 1, data).write(dir.path_join("%s.hg2" % stem))
	var mat := PackedByteArray()
	mat.resize(64 * 64 * 2)
	var mf := FileAccess.open(dir.path_join("%s.mat" % stem), FileAccess.WRITE)
	mf.store_buffer(mat)
	mf.close()
	_write_text(dir.path_join("%s.trn" % stem), "[Size]\r\nWidth = 1280\r\nDepth = 1280\r\n")
	_write_text(dir.path_join("%s.bzn" % stem), _bzn_text(stem, player_y))


func _bzn_text(stem: String, player_y: float) -> String:
	var y: String = str(player_y)
	var lines := PackedStringArray([
		"version [1] =", "2016",
		"binarySave [1] =", "false",
		"msn_filename = %s.bzn" % stem,
		"seq_count [1] =", "1",
		"missionSave [1] =", "true",
		"TerrainName = %s" % stem,
		"size [1] =", "1",
		"[GameObject]",
		"PrjID [1] =", "player",
		"seqno [1] =", "0",
		"pos [1] =",
		"  x [1] =", "640",
		"  y [1] =", y,
		"  z [1] =", "640",
		"team [1] =", "1",
		"label = %s0_player" % stem,
		"isUser [1] =", "1",
		"obj_addr = 00000001",
		"transform [1] =",
		"  right_x [1] =", "1",
		"  right_y [1] =", "0",
		"  right_z [1] =", "0",
		"  up_x [1] =", "0",
		"  up_y [1] =", "1",
		"  up_z [1] =", "0",
		"  front_x [1] =", "0",
		"  front_y [1] =", "0",
		"  front_z [1] =", "1",
		"  posit_x [1] =", "640",
		"  posit_y [1] =", y,
		"  posit_z [1] =", "640",
		"illumination [1] =", "1",
		"pos [1] =",
		"  x [1] =", "640",
		"  y [1] =", y,
		"  z [1] =", "640",
		"seqNo [1] =", "0",
		"name = ",
		"[AiMission]",
		"[AOIs]",
		"size [1] =", "0",
		"[AiPaths]",
		"count [1] =", "0",
	])
	return "\r\n".join(lines) + "\r\n"


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(text.to_utf8_buffer())
	f.close()


func _session_paths(session_dir: String) -> Dictionary:
	var residue: String = session_dir.path_join("residue")
	return {
		"root": session_dir,
		"manifest": session_dir.path_join("manifest.json"),
		"dirty": session_dir.path_join("dirty.json"),
		"report": session_dir.path_join("report.json"),
		"masks": session_dir.path_join("masks"),
		"residue": residue,
		"source": residue.path_join("source"),
	}


func _write_json(path: String, payload: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(payload, "  ") + "\n")
	f.close()
