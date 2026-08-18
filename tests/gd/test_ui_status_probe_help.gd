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

	bar.set_status("error", "boom")
	t.eq((bar.find_child("Status", true, false) as Label).text, "boom")
	bar.set_status("transient", "cam 80 m/s")
	t.eq((bar.find_child("Status", true, false) as Label).text, "boom", "transient does not clobber error")
	bar.set_status("ok", "ok: save")
	t.eq((bar.find_child("Status", true, false) as Label).text, "ok: save")

	bar.set_cursor("xz 1, 2")
	t.eq((bar.find_child("Cursor", true, false) as Label).text, "xz 1, 2")
	var goto_edit: LineEdit = bar.find_child("Goto", true, false)
	t.ok(goto_edit != null, "go-to box exists")
	t.eq(goto_edit.placeholder_text, "x, z")
	t.ok(not goto_edit.editable, "go-to locked with no map")
	t.ok("map" in goto_edit.tooltip_text.to_lower())
	var submitted: Array = []
	bar.goto_submitted.connect(func(text): submitted.append(str(text)))
	goto_edit.text_submitted.emit("64, 128")
	t.eq(submitted, [], "go-to does not emit without a session")
	var saved_session := false
	if MapState != null:
		saved_session = MapState.has_session
		MapState.has_session = true
		MapState.session_changed.emit()
		t.ok(goto_edit.editable, "go-to unlocks with a session")
		goto_edit.text_submitted.emit("64, 128")
		t.eq(submitted, ["64, 128"], "Enter emits the typed x, z")
		MapState.has_session = saved_session
		MapState.session_changed.emit()
	bar.set_map_info("1280x1280  mars")
	t.eq((bar.find_child("MapInfo", true, false) as Label).text, "1280x1280  mars")
	t.ok("autosave" in bar.tooltip_text.to_lower(), "status tooltip mentions autosave")
	var activity: Control = bar.find_child("Activity", true, false)
	t.ok(activity != null, "status hosts an activity indicator")
	t.ok(not activity.visible, "activity is hidden while idle")
	t.eq(StatusBar.verb_activity_text("assets"), "importing assets…")
	t.eq(StatusBar.verb_activity_text("save"), "saving…")

	t.ok(bar.find_child("Walk", true, false) == null, "toggles moved to the tool rail")
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
	t.ok("symmetry" in body.text.to_lower(), "help mentions symmetry mode")
	t.ok("quad" in body.text.to_lower(), "help mentions quad symmetry")
	t.ok("30s" in body.text, "help states the 30s interval")
	t.ok("Test" in body.text, "help mentions the Test button")
	t.ok("BZLogger" in body.text, "help mentions the in-game log verdict")
	t.ok("terrain selection" in body.text.to_lower(), "help documents terrain selection")
	t.ok("feather" in body.text.to_lower(), "help documents feather")
	t.ok("wand" in body.text.to_lower(), "help documents the magic wand")
	t.ok("clone" in body.text.to_lower(), "help documents clone stamp")
	t.ok("2D map" in body.text, "help documents 2D map mode")
	t.ok("Compass" in body.text, "help documents the compass")
	t.ok("Go-to" in body.text, "help documents go-to")
	t.ok("KP 7" in body.text, "help lists KP 7")
	t.ok("Preferences" in body.text, "help documents Preferences")
	t.ok("toast" in body.text.to_lower(), "help documents toasts")
	help.popup_help()
	help.hide()
	help.queue_free()
	await t.tree.process_frame
