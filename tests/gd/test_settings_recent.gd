extends RefCounted
## Settings: last-8 recent maps, dedupe, persist, prune-on-save.


func run(t) -> void:
	var snap := _snapshot_settings()
	var tmp := OS.get_temp_dir().path_join("bz_settings_recent_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)

	Settings.recent_maps.clear()
	Settings.record_recent_map("  %s  " % tmp.path_join("a.trn"))
	t.eq(Settings.recent_maps.size(), 1)
	t.eq(Settings.recent_maps[0], tmp.path_join("a.trn").simplify_path(), "strip + simplify")

	Settings.record_recent_map(tmp.path_join("b.trn"))
	Settings.record_recent_map(tmp.path_join("a.trn"))
	t.eq(Settings.recent_maps.size(), 2, "deduped")
	t.eq(Settings.recent_maps[0], tmp.path_join("a.trn").simplify_path(), "most recent first")
	t.eq(Settings.recent_maps[1], tmp.path_join("b.trn").simplify_path())

	Settings.record_recent_map("   ")
	t.eq(Settings.recent_maps.size(), 2, "empty path ignored")

	Settings.recent_maps.clear()
	for i in 10:
		Settings.record_recent_map(tmp.path_join("m%d.trn" % i))
	t.eq(Settings.recent_maps.size(), Settings.RECENT_MAX, "capped at 8")
	t.eq(Settings.recent_maps[0], tmp.path_join("m9.trn").simplify_path())
	t.eq(Settings.recent_maps[7], tmp.path_join("m2.trn").simplify_path(), "oldest extras dropped")

	var a := tmp.path_join("keep.trn")
	var b := tmp.path_join("drop.trn")
	_write(a, "a")
	_write(b, "b")
	Settings.recent_maps.clear()
	Settings.record_recent_map(a)
	Settings.record_recent_map(b)
	Settings.save()
	Settings.recent_maps.clear()
	Settings._load()
	t.eq(Settings.recent_maps.size(), 2, "recents persist")
	t.eq(Settings.recent_maps[0], b.simplify_path())
	t.eq(Settings.recent_maps[1], a.simplify_path())

	DirAccess.remove_absolute(b)
	Settings.save()
	t.eq(Settings.recent_maps.size(), 1, "missing files pruned on save")
	t.eq(Settings.recent_maps[0], a.simplify_path())
	t.ok(not Settings.recent_maps.has(b.simplify_path()))

	DirAccess.remove_absolute(a)
	DirAccess.remove_absolute(tmp)
	_restore_settings(snap)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _snapshot_settings() -> Dictionary:
	var cfg: Variant = null
	if FileAccess.file_exists(Settings.PATH):
		cfg = FileAccess.get_file_as_string(Settings.PATH)
	return {
		"game_root": Settings.game_root,
		"last_map_dir": Settings.last_map_dir,
		"last_save_dir": Settings.last_save_dir,
		"walk_mode": Settings.walk_mode,
		"last_cache_fingerprint": Settings.last_cache_fingerprint,
		"recent_maps": Settings.recent_maps.duplicate(),
		"cfg": cfg,
	}


func _restore_settings(snap: Dictionary) -> void:
	if snap["cfg"] == null:
		if FileAccess.file_exists(Settings.PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
		Settings._cfg = ConfigFile.new()
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		if f:
			f.store_string(str(snap["cfg"]))
			f.close()
		Settings._load()
	Settings.game_root = str(snap["game_root"])
	Settings.last_map_dir = str(snap["last_map_dir"])
	Settings.last_save_dir = str(snap["last_save_dir"])
	Settings.walk_mode = bool(snap["walk_mode"])
	Settings.last_cache_fingerprint = str(snap["last_cache_fingerprint"])
	Settings.recent_maps.clear()
	for path in snap["recent_maps"]:
		Settings.recent_maps.append(str(path))
