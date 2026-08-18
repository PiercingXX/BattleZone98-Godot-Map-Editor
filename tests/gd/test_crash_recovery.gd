extends RefCounted
## Crash-recovery decision: clean-exit marker × session evidence matrix.


func run(t) -> void:
	_matrix(t)
	_dirty_any_true(t)
	_mtime_compare(t)
	_session_files(t)
	_payload_and_command(t)


func _matrix(t) -> void:
	t.ok(not SessionIO.should_offer_restore(true, true), "clean exit + evidence = no dialog")
	t.ok(not SessionIO.should_offer_restore(true, false), "clean exit + no evidence = no dialog")
	t.ok(SessionIO.should_offer_restore(false, true), "missing marker + evidence = restore")
	t.ok(not SessionIO.should_offer_restore(false, false), "missing marker + no evidence = no dialog")


func _dirty_any_true(t) -> void:
	t.ok(not SessionIO.dirty_json_any_true({}), "empty dirty")
	t.ok(not SessionIO.dirty_json_any_true({
		"terrain": false,
		"materials": false,
		"objects": {"": []},
		"features": false,
		"meta": [],
	}), "all-false dirty")
	t.ok(SessionIO.dirty_json_any_true({"terrain": true}), "terrain true")
	t.ok(SessionIO.dirty_json_any_true({"materials": true}), "materials true")
	t.ok(SessionIO.dirty_json_any_true({"features": true}), "features true")
	t.ok(SessionIO.dirty_json_any_true({"objects": {"": ["obj-1"]}}), "object id listed")
	t.ok(SessionIO.dirty_json_any_true({"meta": ["stem"]}), "meta list")
	t.ok(not SessionIO.dirty_json_any_true({"objects": {"_S": []}}), "empty object lists")


func _mtime_compare(t) -> void:
	t.ok(not SessionIO.files_show_unsaved(10, 10, 10), "same mtime is not newer")
	t.ok(not SessionIO.files_show_unsaved(9, 8, 10), "older buffers")
	t.ok(SessionIO.files_show_unsaved(11, 10, 10), "objects newer")
	t.ok(SessionIO.files_show_unsaved(10, 12, 10), "terrain newer")
	t.ok(SessionIO.files_show_unsaved(-1, 12, 10), "missing objects, terrain newer")


func _session_files(t) -> void:
	var tmp := OS.get_temp_dir().path_join("bz_recovery_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var sessions := tmp.path_join("sessions")
	DirAccess.make_dir_recursive_absolute(sessions)
	t.eq(SessionIO.newest_session_dir(sessions), "", "no sessions")
	t.ok(not SessionIO.session_has_unsaved_evidence(""), "empty path")
	t.ok(not SessionIO.session_has_unsaved_evidence(tmp.path_join("missing")))

	var older := sessions.path_join("aaa")
	var newer := sessions.path_join("zzz")
	DirAccess.make_dir_recursive_absolute(older)
	_write(older.path_join("manifest.json"), {"stem": "old"})
	DirAccess.make_dir_recursive_absolute(newer)
	_write(newer.path_join("manifest.json"), {"stem": "new"})
	t.eq(SessionIO.newest_session_dir(sessions), newer, "newest by mtime/name")

	_write(newer.path_join("dirty.json"), {
		"terrain": false,
		"materials": false,
		"objects": {"": []},
		"features": false,
		"meta": [],
	})
	t.ok(not SessionIO.session_has_unsaved_evidence(newer), "clean dirty.json is not evidence")
	_write(newer.path_join("dirty.json"), {"terrain": true})
	t.ok(SessionIO.session_has_unsaved_evidence(newer), "dirty.json any-true is evidence")
	t.ok(
		SessionIO.should_offer_restore(false, SessionIO.session_has_unsaved_evidence(newer)),
		"crash + dirty session offers restore"
	)
	t.ok(
		not SessionIO.should_offer_restore(true, SessionIO.session_has_unsaved_evidence(newer)),
		"clean exit suppresses restore"
	)

	var marker := tmp.path_join("clean_exit")
	t.ok(not SessionIO.consume_clean_exit(marker), "missing marker")
	SessionIO.write_clean_exit(marker)
	t.ok(FileAccess.file_exists(marker), "marker written")
	t.ok(SessionIO.consume_clean_exit(marker), "consume reports present")
	t.ok(not FileAccess.file_exists(marker), "marker removed")

	_rm_tree(tmp)


func _payload_and_command(t) -> void:
	var tmp := OS.get_temp_dir().path_join("bz_recovery_payload_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	t.eq(SessionIO.session_open_payload(tmp), {}, "no manifest")
	_write(tmp.path_join("manifest.json"), {"stem": "xtcrater", "width_m": 1280})
	var payload := SessionIO.session_open_payload(tmp)
	t.eq(str(payload.get("session", "")), tmp)
	t.eq(str((payload.get("manifest", {}) as Dictionary).get("stem", "")), "xtcrater")
	t.eq(
		SessionIO.asciisave_launch_command("foo.bzn"),
		"steam \"steam://run/301650//foo.bzn /asciisave /win\"",
	)
	t.eq(
		SessionIO.asciisave_launch_command("/maps/bar"),
		"steam \"steam://run/301650//bar.bzn /asciisave /win\"",
	)
	_rm_tree(tmp)


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _rm_tree(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(path.path_join(str(f)))
	for d in da.get_directories():
		_rm_tree(path.path_join(str(d)))
	DirAccess.remove_absolute(path)
