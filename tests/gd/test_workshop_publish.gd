extends RefCounted
## WorkshopPublish: VDF/README exact text, preview scaling, publish flow.


func run(t) -> void:
	_test_paths(t)
	_test_vdf_exact(t)
	_test_readme_exact(t)
	_test_scale_preview(t)
	_test_find_preview_source(t)
	await _test_flow(t)


func _test_paths(t) -> void:
	t.eq(WorkshopPublish.workshop_dir("/out", "xtmap"), "/out/xtmap-workshop")
	t.eq(WorkshopPublish.workshop_dir("/out", "  "), "/out/map-workshop")
	t.eq(WorkshopPublish.workshop_dir("/out", ""), "/out/map-workshop")
	t.eq(WorkshopPublish.default_title("/tmp/out/xtmap-workshop", ""), "xtmap")
	t.eq(WorkshopPublish.default_title("/tmp/out/xtmap-workshop", "Custom"), "Custom")
	t.eq(WorkshopPublish.default_title("/tmp/out/plain", ""), "plain")
	t.eq(WorkshopPublish.STEAM_APP_ID, "301650")
	t.eq(WorkshopPublish.PREVIEW_SIZE, Vector2i(512, 512))


func _test_vdf_exact(t) -> void:
	var content := "/tmp/out/xtmap-workshop"
	var preview := "/tmp/out/xtmap-workshop/preview.jpg"
	var got := WorkshopPublish.generate_vdf(content, preview, "xtmap")
	var want := "\n".join(PackedStringArray([
		"\"workshopitem\"",
		"{",
		"\t\"appid\"\t\t\"301650\"",
		"\t\"publishedfileid\"\t\t\"0\"",
		"\t\"contentfolder\"\t\t\"/tmp/out/xtmap-workshop\"",
		"\t\"previewfile\"\t\t\"/tmp/out/xtmap-workshop/preview.jpg\"",
		"\t\"visibility\"\t\t\"2\"",
		"\t\"title\"\t\t\"xtmap\"",
		"\t\"description\"\t\t\"BattleZone 98 Redux map. Replace this description before you make the item public.\"",
		"\t\"changenote\"\t\t\"Initial upload from the BattleZone 98 Godot Map Editor.\"",
		"}",
		"",
	]))
	t.eq(got, want, "VDF is exact for the given paths")

	var got2 := WorkshopPublish.generate_vdf(
		"/data/maps/foo-workshop",
		"/data/maps/foo-workshop/preview.jpg",
		"foo",
		"3406347034",
		"0",
	)
	var want2 := "\n".join(PackedStringArray([
		"\"workshopitem\"",
		"{",
		"\t\"appid\"\t\t\"301650\"",
		"\t\"publishedfileid\"\t\t\"3406347034\"",
		"\t\"contentfolder\"\t\t\"/data/maps/foo-workshop\"",
		"\t\"previewfile\"\t\t\"/data/maps/foo-workshop/preview.jpg\"",
		"\t\"visibility\"\t\t\"0\"",
		"\t\"title\"\t\t\"foo\"",
		"\t\"description\"\t\t\"BattleZone 98 Redux map. Replace this description before you make the item public.\"",
		"\t\"changenote\"\t\t\"Initial upload from the BattleZone 98 Godot Map Editor.\"",
		"}",
		"",
	]))
	t.eq(got2, want2, "VDF fills publishedfileid and visibility")
	t.eq(
		WorkshopPublish.generate_vdf(content, preview, ""),
		WorkshopPublish.generate_vdf(content, preview, "xtmap"),
		"empty title falls back to folder stem",
	)


func _test_readme_exact(t) -> void:
	var content := "/tmp/out/xtmap-workshop"
	var preview := "/tmp/out/xtmap-workshop/preview.jpg"
	var vdf_path := content.path_join("workshop.vdf")
	var vdf := WorkshopPublish.generate_vdf(content, preview, "xtmap")
	var got := WorkshopPublish.generate_readme(content, preview, "xtmap")
	var want := "\n".join(PackedStringArray([
		"BattleZone 98 Redux — workshop upload kit",
		"==========================================",
		"",
		"This folder was built by the BattleZone 98 Godot Map Editor.",
		"The editor NEVER uploads anything to Steam. You upload it with",
		"steamcmd or the in-game workshop uploader.",
		"",
		"App ID: 301650 (Battlezone 98 Redux)",
		"Title:          xtmap",
		"Content folder: /tmp/out/xtmap-workshop",
		"Preview file:   /tmp/out/xtmap-workshop/preview.jpg",
		"",
		"Contents of this folder",
		"-----------------------",
		"- Assembled map pack (this folder is the Steam Workshop contentfolder)",
		"- preview.jpg — 512×512 Steam preview",
		"- README-UPLOAD.txt — these instructions",
		"- workshop.vdf — steamcmd workshop_build_item file (paths already filled in)",
		"",
		"=== steamcmd (workshop_build_item) ===",
		"",
		"1. Install SteamCMD from Valve.",
		"2. Log in and publish (paths already filled in):",
		"",
		"   steamcmd +login <steam_username> +workshop_build_item \"%s\" +quit" % vdf_path,
		"",
		"3. First upload: publishedfileid is 0. SteamCMD writes the new item id",
		"   back into workshop.vdf. Keep that file to update the same item later.",
		"",
		"Visibility (the \"visibility\" field in the VDF):",
		"  0 = public",
		"  1 = friends only",
		"  2 = hidden / private",
		"This kit defaults to 2 (hidden) so you can review the item page before",
		"going public. Change the number and re-run workshop_build_item.",
		"",
		"--- workshop.vdf ---",
		vdf.strip_edges(),
		"--- end workshop.vdf ---",
		"",
		"=== In-game workshop uploader ===",
		"",
		"BattleZone 98 Redux can publish from inside the game:",
		"1. Copy this folder's map files into the game addon/ directory",
		"   (More → Install into game (addon) does that from the editor).",
		"2. Launch the game, open the Workshop / extras uploader, and create",
		"   or update an item. Attach preview.jpg as the item preview.",
		"3. Set visibility there the same way (public / friends / hidden).",
		"",
		"Do not point either uploader at the game install, the BZP pack, or",
		"subscribed workshop items. This editor never uploads anything itself.",
		"",
	]))
	t.eq(got, want, "README is exact for the given paths")
	t.ok(got.contains("steamcmd +login"), "steamcmd login")
	t.ok(got.contains("workshop_build_item"), "workshop_build_item")
	t.ok(got.contains("301650"), "appid")
	t.ok(got.contains("NEVER uploads"), "never uploads")
	t.ok(got.contains("0 = public"), "visibility public")
	t.ok(got.contains("1 = friends only"), "visibility friends")
	t.ok(got.contains("2 = hidden / private"), "visibility hidden")
	t.ok(got.contains("In-game workshop uploader"), "in-game alternative")
	t.ok(got.contains(content), "contentfolder path")
	t.ok(got.contains(preview), "previewfile path")
	t.ok(got.contains(vdf.strip_edges()), "embeds the VDF")


func _test_scale_preview(t) -> void:
	var empty := WorkshopPublish.scale_preview(Image.new())
	t.ok(empty == null or empty.is_empty(), "empty source stays empty")
	t.ok(WorkshopPublish.scale_preview(null).is_empty(), "null source is empty")

	var small := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	small.fill(Color(1, 0, 0, 1))
	var scaled := WorkshopPublish.scale_preview(small)
	t.eq(scaled.get_width(), 512, "upscale width")
	t.eq(scaled.get_height(), 512, "upscale height")
	t.eq(scaled.get_format(), Image.FORMAT_RGB8, "JPEG wants RGB8")
	t.eq(small.get_width(), 64, "source is not mutated")
	t.eq(small.get_format(), Image.FORMAT_RGBA8, "source format kept")
	var mid: Color = scaled.get_pixel(256, 256)
	t.ok(mid.r > 0.9 and mid.g < 0.1 and mid.b < 0.1, "solid red survives Lanczos")

	var already := Image.create(512, 512, false, Image.FORMAT_RGB8)
	already.fill(Color(0, 1, 0))
	var same := WorkshopPublish.scale_preview(already)
	t.eq(same.get_width(), 512)
	t.eq(same.get_height(), 512)
	t.eq(same.get_format(), Image.FORMAT_RGB8)
	var g: Color = same.get_pixel(10, 10)
	t.ok(g.g > 0.9 and g.r < 0.1, "already-512 stays green")

	var big := Image.create(1024, 256, false, Image.FORMAT_L8)
	big.fill(Color(0.5, 0.5, 0.5))
	var down := WorkshopPublish.scale_preview(big)
	t.eq(down.get_width(), 512, "downscale width")
	t.eq(down.get_height(), 512, "downscale height (stretch)")
	t.eq(down.get_format(), Image.FORMAT_RGB8)

	var tmp := OS.get_temp_dir().path_join("bz_workshop_preview_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var jpg := tmp.path_join("preview.jpg")
	var wr := WorkshopPublish.write_preview_jpg(small, jpg)
	t.ok(bool(wr.get("ok", false)), "write_preview_jpg ok")
	t.eq(str(wr.get("path", "")), jpg)
	t.eq(int(wr.get("width", 0)), 512)
	t.eq(int(wr.get("height", 0)), 512)
	t.ok(FileAccess.file_exists(jpg), "jpg exists")
	var loaded := Image.load_from_file(jpg)
	t.ok(loaded != null and not loaded.is_empty(), "jpg loads")
	t.eq(loaded.get_width(), 512)
	t.eq(loaded.get_height(), 512)
	var bad := WorkshopPublish.write_preview_jpg(Image.new(), tmp.path_join("nope.jpg"))
	t.ok(not bool(bad.get("ok", true)), "empty image does not write")
	var missing := WorkshopPublish.write_preview_from_path(tmp.path_join("gone.png"), jpg)
	t.ok(not bool(missing.get("ok", true)), "missing source is an error")
	DirAccess.remove_absolute(jpg)
	DirAccess.remove_absolute(tmp)


func _test_find_preview_source(t) -> void:
	var tmp := OS.get_temp_dir().path_join("bz_workshop_src_%d" % Time.get_ticks_usec())
	var session := tmp.path_join("session")
	var dest := tmp.path_join("dest")
	var thumbs := session.path_join("thumbs")
	DirAccess.make_dir_recursive_absolute(thumbs)
	DirAccess.make_dir_recursive_absolute(dest)
	t.eq(WorkshopPublish.find_preview_source(session, dest, "xtmap"), "", "nothing yet")
	_write_png(dest.path_join("preview.png"), 16, 16, Color.BLUE)
	t.eq(
		WorkshopPublish.find_preview_source(session, dest, "xtmap"),
		dest.path_join("preview.png"),
		"pack dest is a fallback",
	)
	_write_png(thumbs.path_join("xtmap.png"), 16, 16, Color.GREEN)
	t.eq(
		WorkshopPublish.find_preview_source(session, dest, "xtmap"),
		thumbs.path_join("xtmap.png"),
		"session stem.png beats dest",
	)
	_write_png(thumbs.path_join("preview.png"), 16, 16, Color.RED)
	t.eq(
		WorkshopPublish.find_preview_source(session, dest, "xtmap"),
		thumbs.path_join("preview.png"),
		"session thumbs/preview.png wins",
	)
	_rm_tree(tmp)


func _test_flow(t) -> void:
	var snap := _snapshot()
	var old_worker: Callable = Backend.test_worker
	UndoStack.clear()
	MapState.has_session = false
	MapState.stem = ""
	MapState.session_dir = ""
	Settings.game_root = ""

	var logs: Array = []
	var wp := WorkshopPublish.new()
	wp.name = "WorkshopPublishFlow"
	wp.log = func(msg): logs.append(str(msg))
	t.tree.root.add_child(wp)
	await t.tree.process_frame
	var idle := Time.get_ticks_msec() + 4000
	while Backend.busy or not Backend._queue.is_empty():
		await t.tree.process_frame
		if Time.get_ticks_msec() > idle:
			break

	t.ok(not wp.begin("/tmp"), "begin refuses without a session")
	t.ok("open a map" in logs[logs.size() - 1])

	var tmp := OS.get_temp_dir().path_join("bz_workshop_flow_%d" % Time.get_ticks_usec())
	var session := tmp.path_join("session")
	var parent := tmp.path_join("out")
	var thumbs := session.path_join("thumbs")
	DirAccess.make_dir_recursive_absolute(thumbs)
	DirAccess.make_dir_recursive_absolute(parent)
	_write_png(thumbs.path_join("preview.png"), 40, 20, Color(0.2, 0.4, 0.9))
	MapState.has_session = true
	MapState.stem = "xtmap"
	MapState.session_dir = session

	t.ok(not wp.begin(""), "empty parent is refused")
	Settings.game_root = tmp.path_join("install")
	DirAccess.make_dir_recursive_absolute(Settings.game_root)
	t.ok(not wp.begin(Settings.game_root), "refuses the game install")
	t.ok("game install" in logs[logs.size() - 1])
	t.ok(not wp.begin(SessionIO.templates_dir()), "refuses templates/")
	t.ok("templates" in logs[logs.size() - 1].to_lower())
	Settings.game_root = ""

	var dest := WorkshopPublish.workshop_dir(parent, "xtmap")
	var verbs: Array = []
	Backend.test_worker = func(verb: String, extra_args: PackedStringArray) -> Dictionary:
		verbs.append(verb)
		if verb == "validate":
			var report := {
				"ok": false,
				"findings": [{"id": "V1", "severity": "error", "title": "off ground"}],
			}
			var sess := _flag(extra_args, "--session")
			if not sess.is_empty():
				var rf := FileAccess.open(sess.path_join("report.json"), FileAccess.WRITE)
				if rf:
					rf.store_string(JSON.stringify(report))
					rf.close()
			return report
		if verb == "package":
			var out := _flag(extra_args, "--out")
			if not out.is_empty():
				DirAccess.make_dir_recursive_absolute(out)
			return {"ok": true, "mode": "pack", "dest": dest, "files": ["xtmap.trn"]}
		if verb == "render":
			return {
				"ok": true,
				"preview": thumbs.path_join("preview.png"),
				"png": thumbs.path_join("preview.png"),
			}
		return {"ok": true, "verb": verb}

	var finished: Array = []
	wp.finished.connect(func(r): finished.append(r))
	t.ok(wp.begin(parent), "begin starts")
	t.ok(wp.is_active())
	t.ok(not wp.begin(parent), "second begin is refused")
	t.ok("already running" in logs[logs.size() - 1])
	var deadline := Time.get_ticks_msec() + 6000
	while wp.is_active() or Backend.busy or not Backend._queue.is_empty():
		await t.tree.process_frame
		if Time.get_ticks_msec() > deadline:
			t.fail("workshop publish did not finish")
			break
	await t.tree.process_frame
	t.ok(not wp.is_active(), "publish finished")
	t.eq(verbs, ["validate", "package"], "validate then pack; thumbs skip render")
	t.eq(finished.size(), 1)
	t.ok(bool(finished[0].get("ok", false)), "flow ok")
	t.eq(str(finished[0].get("dest", "")), dest)
	var warned := false
	var logged_pack := false
	var logged_preview := false
	var logged_readme := false
	var logged_vdf := false
	var logged_folder := false
	var uploaded := false
	for line in logs:
		var s := str(line)
		if "findings" in s and "not blocking" in s:
			warned = true
		if s.begins_with("workshop pack "):
			logged_pack = true
		if s.begins_with("workshop preview "):
			logged_preview = true
		if s.begins_with("workshop readme "):
			logged_readme = true
		if s.begins_with("workshop vdf "):
			logged_vdf = true
		if s.begins_with("workshop folder ") and "not uploaded" in s:
			logged_folder = true
		if "steamcmd +" in s or s.begins_with("uploaded"):
			uploaded = true
	t.ok(warned, "findings warn and do not block")
	t.ok(logged_pack, "logged pack path")
	t.ok(logged_preview, "logged preview path")
	t.ok(logged_readme, "logged readme path")
	t.ok(logged_vdf, "logged vdf path")
	t.ok(logged_folder, "logged folder path")
	t.ok(not uploaded, "never invoked steamcmd / upload")
	t.ok(FileAccess.file_exists(dest.path_join("preview.jpg")), "preview.jpg written")
	t.ok(FileAccess.file_exists(dest.path_join("README-UPLOAD.txt")), "README written")
	t.ok(FileAccess.file_exists(dest.path_join("workshop.vdf")), "workshop.vdf written")
	var jpg := Image.load_from_file(dest.path_join("preview.jpg"))
	t.ok(jpg != null, "preview.jpg loads")
	t.eq(jpg.get_width(), 512)
	t.eq(jpg.get_height(), 512)
	var readme := FileAccess.get_file_as_string(dest.path_join("README-UPLOAD.txt"))
	t.eq(
		readme,
		WorkshopPublish.generate_readme(dest, dest.path_join("preview.jpg"), "xtmap"),
		"written README matches generator",
	)
	t.eq(
		FileAccess.get_file_as_string(dest.path_join("workshop.vdf")),
		WorkshopPublish.generate_vdf(dest, dest.path_join("preview.jpg"), "xtmap"),
		"written VDF matches generator",
	)
	t.eq(MapState.findings.size(), 1, "findings pushed onto MapState")
	t.ok(not MapState.findings_stale)

	wp.queue_free()
	await t.tree.process_frame
	_rm_tree(tmp)
	Backend.test_worker = old_worker
	UndoStack.clear()
	_restore(snap)


func _flag(args: PackedStringArray, name: String) -> String:
	for i in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return ""


func _write_png(path: String, w: int, h: int, color: Color) -> void:
	var parent := path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(color)
	img.save_png(path)


func _rm_tree(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.include_hidden = true
	for n in da.get_files():
		DirAccess.remove_absolute(path.path_join(str(n)))
	for d in da.get_directories():
		_rm_tree(path.path_join(str(d)))
	DirAccess.remove_absolute(path)


func _snapshot() -> Dictionary:
	return {
		"has_session": MapState.has_session,
		"stem": MapState.stem,
		"session_dir": MapState.session_dir,
		"findings": MapState.findings.duplicate(true),
		"findings_stale": MapState.findings_stale,
		"game_root": Settings.game_root,
		"last_save_dir": Settings.last_save_dir,
	}


func _restore(snap: Dictionary) -> void:
	MapState.has_session = bool(snap["has_session"])
	MapState.stem = str(snap["stem"])
	MapState.session_dir = str(snap["session_dir"])
	MapState.findings = snap["findings"]
	MapState.findings_stale = bool(snap["findings_stale"])
	Settings.game_root = str(snap["game_root"])
	Settings.last_save_dir = str(snap["last_save_dir"])
