extends RefCounted
## SessionIO: stock world prefill, recent-open recorded only after success.


func run(t) -> void:
	var snap := _snapshot_settings()
	var saved_worlds: Array = MapState.worlds.duplicate(true)
	Settings.game_root = ""
	Settings.recent_maps.clear()
	MapState.worlds = []

	var stock: Array = SessionIO.stock_worlds()
	t.eq(stock.size(), 9, "nine stock worlds")
	var ids: Array = []
	var labels: Array = []
	for world in stock:
		ids.append(world.get("id"))
		labels.append(world.get("label"))
	t.eq(ids, [
		"achilles", "elysium", "europa", "ganymede", "io",
		"mars", "moon", "titan", "venus",
	])
	t.eq(labels, [
		"Achilles", "Elysium", "Europa", "Ganymede", "Io",
		"Mars", "Moon", "Titan", "Venus",
	])

	var opt := OptionButton.new()
	t.tree.root.add_child(opt)
	SessionIO.fill_world_dropdown(opt, stock)
	t.eq(opt.item_count, 9)
	t.eq(opt.get_item_text(0), "Achilles")
	t.eq(str(opt.get_item_metadata(0)), "achilles")
	t.eq(opt.get_item_text(5), "Mars")
	t.eq(str(opt.get_item_metadata(5)), "mars")
	SessionIO.fill_world_dropdown(opt, [{"id": "zzmod", "label": "Zzmod (probed)"}])
	t.eq(opt.item_count, 1, "probed worlds replace stock")
	t.eq(opt.get_item_text(0), "Zzmod (probed)")
	t.eq(str(opt.get_item_metadata(0)), "zzmod")
	opt.queue_free()

	var shell := _Shell.new()
	shell._world_option = OptionButton.new()
	shell._template_option = OptionButton.new()
	shell._new_dialog = ConfirmationDialog.new()
	shell.add_child(shell._world_option)
	shell.add_child(shell._template_option)
	shell.add_child(shell._new_dialog)
	t.tree.root.add_child(shell)
	await t.tree.process_frame

	var logs: Array = []
	var io := SessionIO.new(shell, func(msg): logs.append(str(msg)))
	io.show_new_dialog()
	t.eq(shell._world_option.item_count, 9, "empty MapState.worlds prefills stock")
	t.eq(str(shell._world_option.get_item_metadata(0)), "achilles")
	t.eq(shell._world_option.get_item_text(0), "Achilles")
	t.ok(shell._world_option.selected >= 0, "Create has a world selected")

	MapState.worlds = [{"id": "zzmod", "label": "Zzmod"}]
	io.show_new_dialog()
	t.eq(shell._world_option.item_count, 9, "filled dropdown kept when worlds already probed")
	shell._world_option.clear()
	io.show_new_dialog()
	t.eq(shell._world_option.item_count, 1, "empty dropdown fills from MapState.worlds")
	t.eq(str(shell._world_option.get_item_metadata(0)), "zzmod")
	shell._new_dialog.hide()

	io.open_file("")
	t.eq(io._pending_open_path, "", "empty path is not pending")
	t.ok(logs[logs.size() - 1].begins_with("no map path"), "empty path is logged")
	io.open_file("/no/such/recent-map.trn")
	t.eq(io._pending_open_path, "", "missing file is not pending")
	t.ok("file moved" in logs[logs.size() - 1], "missing file is logged")
	t.eq(Settings.recent_maps.size(), 0, "attempt does not record")

	io._pending_open_path = tmp_missing()
	io.clear_pending_open()
	io.record_open_if_pending()
	t.eq(Settings.recent_maps.size(), 0, "cleared pending is not recorded")

	var tmp := OS.get_temp_dir().path_join("bz_session_io_ux_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var opened := tmp.path_join("opened.trn")
	var wf := FileAccess.open(opened, FileAccess.WRITE)
	wf.store_string("trn")
	wf.close()
	io._pending_open_path = opened
	t.eq(Settings.recent_maps.size(), 0, "pending is not recorded until success")
	io.record_open_if_pending()
	t.eq(Settings.recent_maps.size(), 1)
	t.eq(Settings.recent_maps[0], opened.simplify_path())
	t.eq(io._pending_open_path, "")
	t.ok("opened" in logs[logs.size() - 1], "success is logged")

	shell.queue_free()
	await t.tree.process_frame
	DirAccess.remove_absolute(opened)
	DirAccess.remove_absolute(tmp)
	MapState.worlds = saved_worlds
	_restore_settings(snap)


func tmp_missing() -> String:
	return "/no/such/pending-open.trn"


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


class _Shell:
	extends Node
	var _world_option: OptionButton
	var _template_option: OptionButton
	var _new_dialog: ConfirmationDialog
