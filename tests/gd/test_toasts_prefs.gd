extends RefCounted
## Settings prefs round-trips, log level routing, toast queue, console filters.


func run(t) -> void:
	var snap := _snapshot()
	_settings_round_trip(t)
	_log_routing(t)
	_toast_queue(t)
	_camera_helpers(t)
	_team_palette(t)
	await _log_console(t)
	await _toast_layer(t)
	await _status_activity(t)
	await _prefs_dialog(t)
	_restore(snap)


func _settings_round_trip(t) -> void:
	t.eq(Settings.coerce_autosave_interval(15), 15)
	t.eq(Settings.coerce_autosave_interval(30), 30)
	t.eq(Settings.coerce_autosave_interval(60), 60)
	t.eq(Settings.coerce_autosave_interval(0), 0)
	t.eq(Settings.coerce_autosave_interval("off"), 0)
	t.eq(Settings.coerce_autosave_interval("15s"), 15)
	t.eq(Settings.coerce_autosave_interval(7), Settings.AUTOSAVE_DEFAULT_S, "unknown interval falls back")
	t.eq(Settings.coerce_autosave_interval(null), Settings.AUTOSAVE_DEFAULT_S)
	t.eq(Settings.coerce_camera_speed(1.0), 1.0)
	t.eq(Settings.coerce_camera_speed(0.1), Settings.CAM_SPEED_MIN)
	t.eq(Settings.coerce_camera_speed(9.0), Settings.CAM_SPEED_MAX)
	t.eq(Settings.coerce_camera_speed("1.5"), 1.5)
	t.eq(Settings.coerce_camera_speed("nope"), Settings.CAM_SPEED_DEFAULT)

	Settings.autosave_interval_s = 15
	Settings.camera_speed_mul = 1.75
	Settings.invert_look = true
	Settings.colorblind_teams = true
	Settings.default_save_dir = "/tmp/bz-maps"
	Settings.keymap_scheme = "gimp"
	Settings.ui_scale = 1.25
	Settings.save()

	Settings.autosave_interval_s = 30
	Settings.camera_speed_mul = 1.0
	Settings.invert_look = false
	Settings.colorblind_teams = false
	Settings.default_save_dir = ""
	Settings.keymap_scheme = "godot"
	Settings.ui_scale = 1.0
	Settings._load()
	t.eq(Settings.autosave_interval_s, 15, "autosave interval persists")
	t.eq(Settings.camera_speed_mul, 1.75, "camera speed persists")
	t.ok(Settings.invert_look, "invert look persists")
	t.ok(Settings.colorblind_teams, "colorblind teams persists")
	t.eq(Settings.default_save_dir, "/tmp/bz-maps", "default save dir persists")
	t.eq(Settings.keymap_scheme, "gimp", "keymap persists")
	t.eq(Settings.ui_scale, 1.25, "ui scale still persists")

	var cfg := ConfigFile.new()
	t.eq(cfg.load(Settings.PATH), OK)
	cfg.set_value("editor", "autosave_interval_s", 99)
	cfg.set_value("camera", "speed_mul", 0.05)
	cfg.save(Settings.PATH)
	Settings._load()
	t.eq(Settings.autosave_interval_s, Settings.AUTOSAVE_DEFAULT_S, "bad autosave clamps to default")
	t.eq(Settings.camera_speed_mul, Settings.CAM_SPEED_MIN, "tiny camera speed clamps to min")

	Settings.default_save_dir = "/pref/out"
	Settings.last_save_dir = ""
	t.eq(Settings.effective_save_dir(), "/pref/out", "effective save dir falls back to default")
	Settings.last_save_dir = "/last/out"
	t.eq(Settings.effective_save_dir(), "/last/out", "last save dir wins")


func _log_routing(t) -> void:
	t.eq(LogRouter.infer_level("hello"), LogRouter.LEVEL_INFO)
	t.eq(LogRouter.infer_level("warning: fog"), LogRouter.LEVEL_WARNING)
	t.eq(LogRouter.infer_level("ERROR [x] boom"), LogRouter.LEVEL_ERROR)
	t.eq(LogRouter.infer_level("  hint: try this"), LogRouter.LEVEL_WARNING)
	t.eq(LogRouter.infer_level("opened /m.trn", "info"), LogRouter.LEVEL_INFO, "explicit level wins")
	t.eq(LogRouter.infer_level("hello", "error"), LogRouter.LEVEL_ERROR)

	t.ok(LogRouter.should_toast("opened /maps/a.trn"))
	t.ok(LogRouter.should_toast("saved 12 files to /out"))
	t.ok(LogRouter.should_toast("package addon: 4 files → /game/addon"))
	t.ok(not LogRouter.should_toast("package pack: 4 files → /out"), "assemble-pack is not a toast")
	t.ok(LogRouter.should_toast("/home/u/.local/share/x/screenshots/map-1.png"))
	t.ok(LogRouter.should_toast("C:\\Users\\a\\screenshots\\map-2.png"))
	t.ok(not LogRouter.should_toast("screenshot: no viewport"))
	t.ok(not LogRouter.should_toast("screenshot failed: no space"))
	t.ok(LogRouter.should_toast("128 classes  3 unresolved  fidelity mostly proxy"))
	t.ok(LogRouter.should_toast(GameTest.MSG_PASS))
	t.ok(LogRouter.should_toast(GameTest.MSG_FAIL_INSTANTIATE))
	t.ok(LogRouter.should_toast(GameTest.MSG_TIMEOUT))
	t.ok(LogRouter.should_toast(GameTest.MSG_CANCELLED))
	t.ok(LogRouter.should_toast("ERROR [no_map] missing"))
	t.ok(not LogRouter.should_toast("autosaved session"))
	t.ok(not LogRouter.should_toast("armed apc"))
	t.ok(not LogRouter.should_toast("open a map first"))

	var routed := LogRouter.route("opened /a.trn")
	t.eq(routed.level, LogRouter.LEVEL_INFO)
	t.ok(bool(routed.toast), "opened auto-toasts")
	var forced := LogRouter.route("quiet note", "info", true)
	t.ok(bool(forced.toast), "toast flag forces a toast")
	var err := LogRouter.route("ERROR [x] y", "", false)
	t.eq(err.level, LogRouter.LEVEL_ERROR)
	t.ok(bool(err.toast), "errors toast even without the flag")
	t.ok("[color=#" + LogRouter.COLOR_ERROR + "]" in LogRouter.bbcode_line("ERROR x", "error"))
	t.ok("[lb]" in LogRouter.escape_bbcode("a[b]"), "bbcode brackets are escaped")


func _toast_queue(t) -> void:
	var q := ToastQueue.new()
	t.eq(ToastQueue.MAX_VISIBLE, 4)
	t.eq(ToastQueue.LIFETIME_S, 3.5)
	var a := q.push("one", "info", 0.0)
	q.push("two", "info", 0.1)
	q.push("three", "info", 0.2)
	q.push("four", "info", 0.3)
	t.eq(q.items.size(), 4)
	q.push("five", "error", 0.4)
	t.eq(q.items.size(), 4, "max 4")
	t.eq(str(q.items[0].get("text")), "two", "oldest dropped")
	t.eq(str(q.items[3].get("text")), "five")
	t.eq(str(q.items[3].get("level")), LogRouter.LEVEL_ERROR)
	t.ok(q.dismiss(int(a.get("id", 0))) == false, "already evicted id is gone")
	t.ok(q.dismiss(int(q.items[0].get("id"))))
	t.eq(q.items.size(), 3)
	var now := 0.4 + ToastQueue.LIFETIME_S
	var gone := q.expire(now)
	t.eq(gone.size(), 3, "lifetime expires remaining toasts")
	t.eq(q.items.size(), 0)
	var fresh := q.push("fade", "info", 10.0)
	t.eq(q.alpha_at(fresh, 10.0), 1.0)
	t.ok(q.alpha_at(fresh, 10.0 + ToastQueue.LIFETIME_S - 0.2) < 1.0)
	t.eq(q.alpha_at(fresh, 10.0 + ToastQueue.LIFETIME_S), 0.0)


func _camera_helpers(t) -> void:
	t.eq(FlyCamera.look_yaw_delta(10.0, 0.003), -0.03)
	t.eq(FlyCamera.look_pitch_delta(10.0, false, 0.003), -0.03)
	t.eq(FlyCamera.look_pitch_delta(10.0, true, 0.003), 0.03)
	t.eq(FlyCamera.speed_multiplier(false, false, 1.5), 1.5)
	t.eq(FlyCamera.speed_multiplier(true, false, 1.5), 6.0)
	t.eq(FlyCamera.speed_multiplier(false, true, 1.5), 0.375)


func _team_palette(t) -> void:
	var saved_cb := Settings.colorblind_teams
	Settings.colorblind_teams = false
	t.eq(ObjectMarkers.team_color(0), ObjectMarkers.TEAM_NEUTRAL)
	t.eq(ObjectMarkers.team_color(1), ObjectMarkers.TEAM_PALETTE[0])
	t.eq(ObjectMarkers.team_color(8), ObjectMarkers.TEAM_PALETTE[0], "wraps")
	Settings.colorblind_teams = true
	t.eq(ObjectMarkers.team_color(1), ObjectMarkers.TEAM_PALETTE_COLORBLIND[0])
	t.ok(ObjectMarkers.team_color(1) != ObjectMarkers.TEAM_PALETTE[0], "colorblind table is distinct")
	t.eq(ObjectMarkers.team_palette(true).size(), 7)
	t.eq(ObjectMarkers.team_palette(false).size(), 7)
	Settings.colorblind_teams = saved_cb


func _log_console(t) -> void:
	var log := LogConsole.new()
	log.name = "Console"
	t.tree.root.add_child(log)
	await t.tree.process_frame
	log.append_line("ok line", "info")
	log.append_line("warning: fog", "warning")
	log.append_line("ERROR [x] boom", "error")
	t.ok("ok line" in log.text)
	t.ok("warning: fog" in log.text)
	t.ok("ERROR [x] boom" in log.text)
	t.eq(log.get_line_count(), 3)
	t.eq(log.current_filter(), LogConsole.FILTER_ALL)
	log.set_filter(LogConsole.FILTER_WARNING)
	t.eq(log.visible_text(), "warning: fog\nERROR [x] boom", "warnings filter is warning+error")
	log.set_filter(LogConsole.FILTER_ERROR)
	t.eq(log.visible_text(), "ERROR [x] boom")
	var copied := log.copy_visible()
	t.eq(copied, "ERROR [x] boom")
	log.set_filter(LogConsole.FILTER_ALL)
	t.eq(log.visible_text().split("\n").size(), 3)
	t.ok(log.find_child("Copy", true, false) is Button)
	t.ok(log.find_child("Body", true, false) is RichTextLabel)
	var body: RichTextLabel = log.find_child("Body", true, false)
	t.ok(body.bbcode_enabled)
	t.ok(
		"[color=#" in body.text or "boom" in body.get_parsed_text(),
		"console renders the error line",
	)
	log.queue_free()
	await t.tree.process_frame


func _toast_layer(t) -> void:
	var layer := ToastLayer.new()
	t.tree.root.add_child(layer)
	await t.tree.process_frame
	layer.push("opened /m.trn", "info")
	layer.push("ERROR [x] boom", "error")
	t.eq(layer.visible_count(), 2)
	t.ok(layer.get_child_count() == 2)
	var err_card: Control = layer.get_child(1)
	t.ok(err_card != null)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	err_card.gui_input.emit(ev)
	t.eq(layer.visible_count(), 1, "click dismisses a toast")
	layer.push("a", "info")
	layer.push("b", "info")
	layer.push("c", "info")
	layer.push("d", "info")
	t.eq(layer.visible_count(), 4, "layer caps at 4")
	layer.queue_free()
	await t.tree.process_frame


func _status_activity(t) -> void:
	var bar: Node = load("res://project/ui/status/StatusBar.tscn").instantiate()
	t.tree.root.add_child(bar)
	await t.tree.process_frame
	var act: Control = bar.find_child("Activity", true, false)
	var label: Label = bar.find_child("ActivityLabel", true, false)
	t.ok(act != null and not act.visible)
	Backend.call_started.emit("assets")
	await t.tree.process_frame
	t.ok(act.visible, "assets shows the activity indicator")
	t.eq(label.text, "importing assets…")
	Backend.call_started.emit("save")
	await t.tree.process_frame
	t.eq(label.text, "saving…")
	Backend.call_finished.emit("save", {})
	await t.tree.process_frame
	t.ok(not act.visible, "finished hides the indicator when idle")
	bar.queue_free()
	await t.tree.process_frame


func _prefs_dialog(t) -> void:
	var dlg: Node = load("res://project/ui/prefs/PrefsDialog.tscn").instantiate()
	t.tree.root.add_child(dlg)
	await t.tree.process_frame
	dlg.refresh()
	t.ok(dlg.find_child("UiScale", true, false) is HSlider)
	t.ok(dlg.find_child("CameraSpeed", true, false) is HSlider)
	t.ok(dlg.find_child("InvertLook", true, false) is CheckBox)
	t.ok(dlg.find_child("ColorblindTeams", true, false) is CheckBox)
	t.ok(dlg.find_child("SaveDir", true, false) is LineEdit)

	Settings.ui_scale = 1.0
	Settings.autosave_interval_s = 30
	Settings.camera_speed_mul = 1.0
	Settings.invert_look = false
	Settings.colorblind_teams = false
	dlg.refresh()

	var scale: HSlider = dlg.find_child("UiScale", true, false)
	scale.value = 1.35
	t.eq(Settings.ui_scale, Settings.coerce_ui_scale(1.35), "scale slider writes Settings")

	# Held grab: the readout tracks, the window does not rescale until release.
	Settings.ui_scale = 1.0
	dlg.refresh()
	scale.drag_started.emit()
	scale.value = 1.5
	t.eq(Settings.ui_scale, 1.0, "scale is not applied while the grab is held")
	var readout: Label = dlg.find_child("UiScaleValue", true, false)
	t.eq(readout.text, "%.2f×" % Settings.coerce_ui_scale(1.5), "readout still tracks live")
	scale.drag_ended.emit(true)
	t.eq(Settings.ui_scale, Settings.coerce_ui_scale(1.5), "scale lands on release")

	dlg._apply_autosave(60)
	t.eq(Settings.autosave_interval_s, 60, "autosave radio writes Settings")
	dlg._apply_autosave(0)
	t.eq(Settings.autosave_interval_s, 0)

	var cam: HSlider = dlg.find_child("CameraSpeed", true, false)
	cam.value = 2.0
	t.eq(Settings.camera_speed_mul, 2.0)

	var invert: CheckBox = dlg.find_child("InvertLook", true, false)
	invert.button_pressed = true
	t.ok(Settings.invert_look, "invert look checkbox writes Settings")

	var cb: CheckBox = dlg.find_child("ColorblindTeams", true, false)
	cb.button_pressed = true
	t.ok(Settings.colorblind_teams)

	dlg._apply_save_dir("/tmp/bz-default-save")
	t.eq(Settings.default_save_dir, "/tmp/bz-default-save")
	t.eq(Settings.last_save_dir, "/tmp/bz-default-save", "default save dir takes effect immediately")

	if dlg.has_method("popup_prefs"):
		dlg.popup_prefs()
		dlg.hide()
	dlg.queue_free()
	await t.tree.process_frame


func _snapshot() -> Dictionary:
	var cfg: Variant = null
	if FileAccess.file_exists(Settings.PATH):
		cfg = FileAccess.get_file_as_string(Settings.PATH)
	return {
		"cfg": cfg,
		"autosave": Settings.autosave_interval_s,
		"cam": Settings.camera_speed_mul,
		"invert": Settings.invert_look,
		"colorblind": Settings.colorblind_teams,
		"default_save": Settings.default_save_dir,
		"last_save": Settings.last_save_dir,
		"scheme": Settings.keymap_scheme,
		"ui_scale": Settings.ui_scale,
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
	Settings.autosave_interval_s = int(snap["autosave"])
	Settings.camera_speed_mul = float(snap["cam"])
	Settings.invert_look = bool(snap["invert"])
	Settings.colorblind_teams = bool(snap["colorblind"])
	Settings.default_save_dir = str(snap["default_save"])
	Settings.last_save_dir = str(snap["last_save"])
	Settings.keymap_scheme = str(snap["scheme"])
	Settings.ui_scale = float(snap["ui_scale"])
