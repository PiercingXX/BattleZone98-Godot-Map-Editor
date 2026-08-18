extends RefCounted
## Full main.tscn boot: every chrome node is wired and idle-safe.


func run(t) -> void:
	var saved_session := MapState.has_session
	var saved_stem := MapState.stem
	var saved_worker: Callable = Backend.test_worker
	var saved_root := Settings.game_root
	UndoStack.clear()
	MapState.has_session = false
	Backend.test_worker = _stub

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	t.tree.root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 8000
	while Backend.busy or not Backend._queue.is_empty():
		await t.tree.process_frame
		if Time.get_ticks_msec() > deadline:
			t.fail("backend did not drain after main.tscn boot")
			break
	await t.tree.process_frame

	var top: Node = scene.find_child("TopBar", true, false)
	var palette: Node = scene.find_child("PalettePanel", true, false)
	var inspector: Node = scene.find_child("InspectorPanel", true, false)
	var features: Node = scene.find_child("FeaturesPanel", true, false)
	var findings: Node = scene.find_child("FindingsPanel", true, false)
	var status: Node = scene.find_child("StatusBar", true, false)
	var probe: Node = scene.find_child("ProbeDialog", true, false)
	var help: Node = scene.find_child("HelpWindow", true, false)
	t.ok(top != null and palette != null and inspector != null)
	t.ok(features != null, "Features panel is in the right column")
	t.ok(findings != null and status != null and probe != null and help != null)
	t.ok((features.find_child("AddWater", true, false) as Button).disabled, "Features Add off with no map")
	t.ok((features.find_child("PaintRegion", true, false) as Button).disabled)

	t.ok((top.find_child("Save", true, false) as Button).disabled, "shell Save off with no map")
	t.ok((top.find_child("Validate", true, false) as Button).disabled)
	t.ok((top.find_child("Frame", true, false) as Button).disabled)
	t.ok((top.find_child("Undo", true, false) as Button).disabled)
	t.eq((top.find_child("MapLabel", true, false) as Label).text, "no map open")
	t.ok(top.find_child("View", true, false) is MenuButton, "shell has a View menu")

	t.ok((inspector.find_child("Apply", true, false) as Button).disabled)
	t.ok((inspector.find_child("Delete", true, false) as Button).disabled)
	t.ok((findings.find_child("Validate", true, false) as Button).disabled)

	t.ok(scene._io != null, "SessionIO constructed")
	var console: TextEdit = scene.find_child("Console", true, false)
	t.ok(console != null and "autosave" in console.text.to_lower(), "startup log mentions autosave")
	t.ok(top.get_signal_connection_list("open_requested").size() > 0)
	t.ok(top.get_signal_connection_list("save_requested").size() > 0)
	t.ok(top.get_signal_connection_list("validate_requested").size() > 0)
	t.ok(top.get_signal_connection_list("more_selected").size() > 0)
	t.ok(top.get_signal_connection_list("save_as_requested").size() > 0)
	t.ok(findings.get_signal_connection_list("validate_requested").size() > 0)
	t.ok(probe.get_signal_connection_list("install_chosen").size() > 0)

	var walk: Button = status.find_child("Walk", true, false)
	var grid: Button = status.find_child("Grid", true, false)
	var slope: Button = status.find_child("Slope", true, false)
	t.ok(walk != null and grid != null and slope != null)

	grid.set_pressed_no_signal(false)
	grid.button_pressed = true
	t.ok(bool(scene.get("_show_grid")), "Grid toggle reaches the shell")
	grid.button_pressed = false
	t.ok(not bool(scene.get("_show_grid")))

	var terrain = scene.get("_terrain")
	t.ok(terrain != null)
	slope.button_pressed = true
	t.ok(bool(terrain.get("_show_slope")), "Slope toggle reaches the renderer")
	slope.button_pressed = false
	t.ok(not bool(terrain.get("_show_slope")))

	help.popup_help()
	help.hide()
	if probe.has_method("hide"):
		probe.hide()

	# Session-shaped enablement without opening a real map.
	MapState.has_session = true
	MapState.stem = "foo"
	UndoStack.clear()
	MapState.mark_saved()
	MapState.session_changed.emit()
	t.ok(not (top.find_child("Save", true, false) as Button).disabled, "Save enables after session_changed")
	t.ok(not (findings.find_child("Validate", true, false) as Button).disabled)
	var map_label := top.find_child("MapLabel", true, false) as Label
	t.eq(map_label.text, "foo", "clean session has no unsaved star")
	UndoStack.push(_Nop.new())
	t.eq(map_label.text, "foo*", "edit stars the map label")
	UndoStack.undo()
	t.eq(map_label.text, "foo", "undo back to open/save clears the star")

	MapState.has_session = false
	MapState.session_changed.emit()
	t.ok((top.find_child("Save", true, false) as Button).disabled)
	t.eq((inspector.find_child("Mode", true, false) as Label).text, "nothing selected")

	scene.queue_free()
	await t.tree.process_frame
	# Drain anything the shell queued on the way out.
	deadline = Time.get_ticks_msec() + 4000
	while Backend.busy or not Backend._queue.is_empty():
		await t.tree.process_frame
		if Time.get_ticks_msec() > deadline:
			break
	Backend.test_worker = saved_worker
	MapState.has_session = saved_session
	MapState.stem = saved_stem
	Settings.game_root = saved_root
	UndoStack.clear()
	if saved_session:
		MapState.mark_saved()


func _stub(_verb: String, _args: PackedStringArray) -> Dictionary:
	return {"ok": true, "installs": [], "warnings": [], "worlds": [], "classes": []}


class _Nop:
	extends RefCounted
	func do() -> void:
		pass
	func undo() -> void:
		pass
