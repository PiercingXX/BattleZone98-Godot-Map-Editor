extends RefCounted
## StatusBar toggles + status kinds, ProbeDialog install pick, HelpWindow text.


func run(t) -> void:
	await _status(t)
	await _probe(t)
	await _help(t)


func _status(t) -> void:
	var saved_walk := Settings.walk_mode
	var bar: Node = load("res://project/ui/status/StatusBar.tscn").instantiate()
	t.tree.root.add_child(bar)
	await t.tree.process_frame

	var logs: Array = []
	bar.log_toggled.connect(func(on): logs.append(on))
	var log_btn: Button = bar.find_child("Log", true, false)
	log_btn.button_pressed = true
	t.eq(logs, [true], "Log toggle emits")
	bar.set_log_visible(false)
	t.ok(not log_btn.button_pressed)
	t.eq(logs, [true], "set_log_visible does not re-emit")

	bar.set_status("error", "boom")
	t.eq((bar.find_child("Status", true, false) as Label).text, "boom")
	bar.set_status("transient", "cam 80 m/s")
	t.eq((bar.find_child("Status", true, false) as Label).text, "boom", "transient does not clobber error")
	bar.set_status("ok", "ok: save")
	t.eq((bar.find_child("Status", true, false) as Label).text, "ok: save")

	bar.set_cursor("xz 1, 2")
	t.eq((bar.find_child("Cursor", true, false) as Label).text, "xz 1, 2")
	bar.set_map_info("1280x1280  mars")
	t.eq((bar.find_child("MapInfo", true, false) as Label).text, "1280x1280  mars")
	t.ok("autosave" in bar.tooltip_text.to_lower(), "status tooltip mentions autosave")

	var walk: Button = bar.find_child("Walk", true, false)
	var grid: Button = bar.find_child("Grid", true, false)
	var slope: Button = bar.find_child("Slope", true, false)
	t.ok(walk.toggle_mode and grid.toggle_mode and slope.toggle_mode)
	grid.button_pressed = true
	t.ok(not grid.button_pressed, "Grid reverts without an editor shell")
	slope.button_pressed = true
	t.ok(not slope.button_pressed, "Slope reverts without an editor shell")

	var want_walk := not saved_walk
	walk.button_pressed = want_walk
	t.eq(Settings.walk_mode, want_walk, "Walk writes Settings")
	Settings.walk_mode = saved_walk
	Settings.save()

	bar.queue_free()
	await t.tree.process_frame


func _probe(t) -> void:
	var saved_root := Settings.game_root
	Settings.game_root = ""
	var dlg: Node = load("res://project/ui/probe/ProbeDialog.tscn").instantiate()
	t.tree.root.add_child(dlg)
	await t.tree.process_frame

	var use: Button = dlg.find_child("Use", true, false)
	var browse: Button = dlg.find_child("Browse", true, false)
	t.ok(use.disabled)
	t.ok(browse != null, "Browse fallback exists")

	var chosen: Array = []
	dlg.install_chosen.connect(func(p): chosen.append(p))

	dlg.show_probe({"installs": [], "warnings": ["nothing here"]})
	var list: ItemList = dlg.find_child("List", true, false)
	t.ok(list.item_count >= 1)
	t.ok(use.disabled)

	dlg.show_probe({
		"installs": [
			{"kind": "workshop_item", "path": "/ws/item", "id": "1", "source": "steam"},
			{"kind": "game", "path": "/games/bz98", "source": "steam"},
		],
		"warnings": ["optional note"],
	})
	t.eq(list.item_count, 3)
	# workshop row
	list.select(0)
	list.item_selected.emit(0)
	t.ok(use.disabled, "workshop row is not a game install")
	list.item_activated.emit(0)
	t.eq(chosen, [], "activating a non-game row does not pick")
	# game row
	list.select(1)
	list.item_selected.emit(1)
	t.ok(not use.disabled, "Use enables on a game row")
	list.item_activated.emit(1)
	t.eq(chosen, ["/games/bz98"], "double-click / activate uses the game install")

	dlg.show_probe({"installs": [{"kind": "game", "path": "/games/bz98"}], "warnings": []})
	list.select(0)
	list.item_selected.emit(0)
	use.pressed.emit()
	t.eq(chosen, ["/games/bz98", "/games/bz98"], "Use this install emits")

	dlg.hide()
	dlg.queue_free()
	await t.tree.process_frame
	Settings.game_root = saved_root


func _help(t) -> void:
	var help: Node = load("res://project/ui/help/HelpWindow.tscn").instantiate()
	t.tree.root.add_child(help)
	await t.tree.process_frame
	var body: RichTextLabel = help.find_child("Body", true, false)
	t.ok("Delete" in body.text, "help lists Delete")
	t.ok("G grid" in body.text, "help lists grid")
	t.ok("Ctrl+Z" in body.text)
	t.ok("9 select" in body.text)
	t.ok("autosave" in body.text.to_lower(), "help mentions autosave")
	t.ok("30s" in body.text, "help states the 30s interval")
	help.popup_help()
	help.hide()
	help.queue_free()
	await t.tree.process_frame
