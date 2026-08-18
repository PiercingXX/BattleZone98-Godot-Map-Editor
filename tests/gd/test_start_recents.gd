extends RefCounted
## Start overlay: recents/thumb resolution, first-run hints, buttons.


func run(t) -> void:
	var snap := _snapshot()
	_resolve(t)
	_first_run(t)
	await _overlay(t)
	_restore(snap)


func _resolve(t) -> void:
	var tmp := OS.get_temp_dir().path_join("bz_start_recents_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var map := tmp.path_join("xtarena.trn")
	_write(map, "trn")
	var none := StartRecents.resolve_entry(map)
	t.eq(str(none.get("stem")), "xtarena")
	t.eq(str(none.get("dir")), tmp.simplify_path())
	t.eq(str(none.get("thumb_path")), "", "no sibling thumb")
	t.ok("xtarena" in str(none.get("caption")))
	t.ok(tmp.get_file() in str(none.get("caption")) or tmp.simplify_path() in str(none.get("caption")))
	t.ok(bool(none.get("exists")))
	t.eq(StartRecents.display_stem_dir("xtarena", tmp), "xtarena  ·  %s" % tmp)

	_write(tmp.path_join("xtarena.bmp"), "bmp")
	var bmp := StartRecents.resolve_entry(map)
	t.ok(str(bmp.get("thumb_path")).to_lower().ends_with("xtarena.bmp"), "bmp beside the map")
	t.eq(str(bmp.get("caption")), "xtarena", "thumb uses stem as caption")

	_write(tmp.path_join("xtarena.png"), "png")
	var png := StartRecents.resolve_entry(map)
	t.ok(str(png.get("thumb_path")).to_lower().ends_with("xtarena.png"), "png wins over bmp")

	_write(tmp.path_join("CASED.BMP"), "bmp")
	var cased := StartRecents.resolve_entry(tmp.path_join("CASED.trn"))
	t.eq(str(cased.get("stem")), "CASED")
	t.ok(str(cased.get("thumb_path")).to_lower().ends_with(".bmp"), "BMP case-insensitive")

	var missing := StartRecents.resolve_entry(tmp.path_join("gone.trn"))
	t.ok(not bool(missing.get("exists")), "missing map is flagged")
	t.eq(StartRecents.resolve_entry("   ").get("path"), "")

	DirAccess.remove_absolute(tmp.path_join("xtarena.trn"))
	DirAccess.remove_absolute(tmp.path_join("xtarena.bmp"))
	DirAccess.remove_absolute(tmp.path_join("xtarena.png"))
	DirAccess.remove_absolute(tmp.path_join("CASED.BMP"))
	DirAccess.remove_absolute(tmp)


func _first_run(t) -> void:
	Settings.recent_maps.clear()
	Settings.ever_had_recents = false
	t.ok(StartRecents.is_first_run(), "empty recents + never recorded is first-run")
	t.ok(Settings.is_first_run())
	Settings.ever_had_recents = true
	t.ok(not StartRecents.is_first_run(), "had recents once is not first-run")
	Settings.ever_had_recents = false
	Settings.record_recent_map("/tmp/does-not-need-to-exist.trn")
	t.ok(Settings.ever_had_recents, "recording a recent sets ever_had_recents")
	t.ok(not StartRecents.is_first_run())
	t.eq(PanelCollapse.header_text("Findings", true), "Findings ▾")
	t.eq(PanelCollapse.header_text("Findings", false), "Findings ▸")


func _overlay(t) -> void:
	Settings.recent_maps.clear()
	Settings.ever_had_recents = false
	var overlay: Node = load("res://project/ui/start/StartScreen.tscn").instantiate()
	t.tree.root.add_child(overlay)
	await t.tree.process_frame
	t.eq(
		(overlay.find_child("Title", true, false) as Label).text,
		str(ProjectSettings.get_setting("application/config/name", "")),
	)
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	t.ok(ver in (overlay.find_child("Version", true, false) as Label).text)
	t.ok((overlay.find_child("Hints", true, false) as Control).visible, "first-run hints show")
	t.eq(StartScreen.HINTS.size(), 3)
	t.ok("map" in StartScreen.HINTS[0].to_lower())
	t.ok("probe" in StartScreen.HINTS[1].to_lower())
	t.ok("f1" in StartScreen.HINTS[2].to_lower())
	t.ok(overlay.find_child("New", true, false) is Button)
	t.ok(overlay.find_child("Open", true, false) is Button)
	t.ok(overlay.find_child("Gallery", true, false) is Button)

	var saw := {"new": 0, "open": 0, "gallery": 0, "recent": "", "template": ""}
	overlay.new_requested.connect(func(): saw["new"] += 1)
	overlay.open_requested.connect(func(): saw["open"] += 1)
	overlay.gallery_requested.connect(func(): saw["gallery"] += 1)
	overlay.recent_open_requested.connect(func(p): saw["recent"] = p)
	overlay.template_requested.connect(func(p): saw["template"] = p)
	(overlay.find_child("New", true, false) as Button).pressed.emit()
	(overlay.find_child("Open", true, false) as Button).pressed.emit()
	(overlay.find_child("Gallery", true, false) as Button).pressed.emit()
	t.eq(saw["new"], 1)
	t.eq(saw["open"], 1)
	t.eq(saw["gallery"], 1)

	var tmp := OS.get_temp_dir().path_join("bz_start_ui_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var map := tmp.path_join("xtui.trn")
	_write(map, "trn")
	Settings.recent_maps.clear()
	Settings.record_recent_map(map)
	overlay.refresh()
	t.ok(not (overlay.find_child("Hints", true, false) as Control).visible, "hints hide after a recent")
	var recents: VBoxContainer = overlay.find_child("Recents", true, false)
	t.ok(recents.get_child_count() >= 1, "recent row is listed")
	(recents.get_child(0) as Button).pressed.emit()
	t.eq(str(saw["recent"]), map.simplify_path())

	var templates: HBoxContainer = overlay.find_child("Templates", true, false)
	t.ok(templates.get_child_count() >= 1, "templates row lists SessionIO templates")
	if templates.get_child_count() > 0:
		(templates.get_child(0) as Button).pressed.emit()
		t.ok(not str(saw["template"]).is_empty(), "template click emits trn path")
		t.ok(str(saw["template"]).to_lower().ends_with(".trn"))

	overlay.hide_start()
	t.ok(not overlay.visible)
	t.eq(overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	overlay.show_start()
	t.ok(overlay.visible)
	t.eq(overlay.mouse_filter, Control.MOUSE_FILTER_STOP)

	overlay.queue_free()
	await t.tree.process_frame
	DirAccess.remove_absolute(map)
	DirAccess.remove_absolute(tmp)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _snapshot() -> Dictionary:
	var cfg: Variant = null
	if FileAccess.file_exists(Settings.PATH):
		cfg = FileAccess.get_file_as_string(Settings.PATH)
	return {
		"cfg": cfg,
		"recent_maps": Settings.recent_maps.duplicate(),
		"ever_had_recents": Settings.ever_had_recents,
	}


func _restore(snap: Dictionary) -> void:
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
	Settings.ever_had_recents = bool(snap["ever_had_recents"])
	Settings.recent_maps.clear()
	for path in snap["recent_maps"]:
		Settings.recent_maps.append(str(path))
