extends RefCounted
## Multi-select inspector apply + on-canvas nudge / rotate (one undo each).


func run(t) -> void:
	var saved_session := MapState.has_session
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_dirty: Dictionary = MapState.dirty.duplicate(true)
	var saved_sel: Array[String] = MapState.selected_ids.duplicate()
	var saved_variant := MapState.active_variant
	var saved_field = MapState.field
	var saved_tool := ToolState.tool
	UndoStack.clear()
	MapState.has_session = true
	MapState.active_variant = ""
	MapState.dirty = {}
	MapState.field = _flat(32, 32, 200)

	await _inspector_multi(t)
	_nudge_rotate(t)
	await _help_keys(t)

	UndoStack.clear()
	MapState.has_session = saved_session
	MapState.objects = saved_objects
	MapState.dirty = saved_dirty
	MapState.selected_ids = saved_sel
	MapState.active_variant = saved_variant
	MapState.field = saved_field
	ToolState.set_tool(saved_tool if saved_tool != "" else "fly")
	if saved_session:
		MapState.mark_saved()


func _inspector_multi(t) -> void:
	var a := _rec("obj-a", 10.0, 20.0, 30.0, 1, "alpha", false, 5.0)
	var b := _rec("obj-b", 80.0, 90.0, 45.0, 2, "bravo", false, 8.0)
	MapState.objects = {"": [a, b]}
	MapState.selected_ids = ["obj-a", "obj-b"] as Array[String]
	UndoStack.clear()

	var insp: Node = load("res://project/ui/inspector/InspectorPanel.tscn").instantiate()
	t.tree.root.add_child(insp)
	await t.tree.process_frame
	insp.apply_requested.connect(func(edits): EditActions.apply_inspector(edits))

	insp.show_object(a)
	(insp.find_child("Team", true, false) as SpinBox).value = 4
	_btn(insp, "Apply").pressed.emit()
	t.eq(int(MapState.find_object("obj-a").get("team", 0)), 4, "team applied to first")
	t.eq(int(MapState.find_object("obj-b").get("team", 0)), 4, "team applied to second")
	t.near(float(MapState.find_object("obj-a").get("x", 0.0)), 10.0, 0.001, "first x left alone")
	t.near(float(MapState.find_object("obj-b").get("x", 0.0)), 80.0, 0.001, "second x left alone")
	t.eq(str(MapState.find_object("obj-a").get("label", "")), "alpha", "first label left alone")
	t.eq(str(MapState.find_object("obj-b").get("label", "")), "bravo", "second label left alone")
	t.ok(UndoStack.can_undo(), "apply pushed undo")
	UndoStack.undo()
	t.eq(int(MapState.find_object("obj-a").get("team", 0)), 1)
	t.eq(int(MapState.find_object("obj-b").get("team", 0)), 2)
	t.ok(not UndoStack.can_undo(), "whole apply is one undo step")
	UndoStack.redo()
	t.eq(int(MapState.find_object("obj-a").get("team", 0)), 4)
	t.eq(int(MapState.find_object("obj-b").get("team", 0)), 4)

	# Label cannot be applied on multi-select even if the text is forced dirty.
	insp.show_object(MapState.find_object("obj-a"))
	(insp.find_child("Label", true, false) as LineEdit).text = "renamed-all"
	(insp.find_child("Yaw", true, false) as SpinBox).value = 12.0
	_btn(insp, "Apply").pressed.emit()
	t.eq(str(MapState.find_object("obj-a").get("label", "")), "alpha", "label skipped on multi")
	t.eq(str(MapState.find_object("obj-b").get("label", "")), "bravo")
	t.near(float(MapState.find_object("obj-a").get("yaw_deg", 0.0)), 12.0, 0.001)
	t.near(float(MapState.find_object("obj-b").get("yaw_deg", 0.0)), 12.0, 0.001)

	# y applies only when pin height is on (and y is dirty).
	insp.show_object(MapState.find_object("obj-a"))
	(insp.find_child("Y", true, false) as SpinBox).value = 50.0
	_btn(insp, "Apply").pressed.emit()
	t.near(float(MapState.find_object("obj-a").get("y", 0.0)), 5.0, 0.001, "y ignored while unpinned")
	t.near(float(MapState.find_object("obj-b").get("y", 0.0)), 8.0, 0.001)

	insp.show_object(MapState.find_object("obj-a"))
	var pin: CheckBox = insp.find_child("PinHeight", true, false)
	pin.button_pressed = true
	(insp.find_child("Y", true, false) as SpinBox).value = 50.0
	_btn(insp, "Apply").pressed.emit()
	t.near(float(MapState.find_object("obj-a").get("y", 0.0)), 50.0, 0.001, "pinned y applied")
	t.near(float(MapState.find_object("obj-b").get("y", 0.0)), 50.0, 0.001)
	t.ok(bool(MapState.find_object("obj-a").get("pinned_y", false)))
	t.ok(bool(MapState.find_object("obj-b").get("pinned_y", false)))

	insp.queue_free()
	await t.tree.process_frame
	UndoStack.clear()


func _nudge_rotate(t) -> void:
	var loose := _rec("n-1", 20.0, 20.0, 10.0, 0, "loose", false, 5.0)
	var pinned := _rec("n-2", 40.0, 40.0, 170.0, 1, "pinned", true, 7.0)
	MapState.objects = {"": [loose, pinned]}
	MapState.selected_ids = ["n-1", "n-2"] as Array[String]
	UndoStack.clear()
	var logs: Array = []
	var log := func(msg): logs.append(str(msg))

	ToolState.set_tool("fly")
	t.ok(not EditActions.try_select_transform(KEY_RIGHT, false, log), "ignored off select tool")
	t.near(float(MapState.find_object("n-1").get("x", 0.0)), 20.0, 0.001)

	ToolState.set_tool("select")
	var saved_sel: Array[String] = MapState.selected_ids.duplicate()
	MapState.selected_ids.clear()
	t.ok(not EditActions.try_select_transform(KEY_RIGHT, false, log), "ignored with empty selection")
	MapState.selected_ids = saved_sel

	t.ok(EditActions.try_select_transform(KEY_RIGHT, false, log), "arrow nudges")
	t.near(float(MapState.find_object("n-1").get("x", 0.0)), 21.0, 0.001, "1 m +x")
	t.near(float(MapState.find_object("n-2").get("x", 0.0)), 41.0, 0.001)
	t.near(float(MapState.find_object("n-1").get("y", 0.0)), 20.0, 0.001, "unpinned resnaps")
	t.near(float(MapState.find_object("n-2").get("y", 0.0)), 7.0, 0.001, "pinned keeps y")
	t.ok(not logs.is_empty() and "nudged" in logs[logs.size() - 1])
	UndoStack.undo()
	t.near(float(MapState.find_object("n-1").get("x", 0.0)), 20.0, 0.001)
	t.near(float(MapState.find_object("n-2").get("x", 0.0)), 40.0, 0.001)
	t.near(float(MapState.find_object("n-1").get("y", 0.0)), 5.0, 0.001)
	t.ok(not UndoStack.can_undo(), "nudge is one undo step")

	t.ok(EditActions.try_select_transform(KEY_UP, true, log), "shift arrow")
	t.near(float(MapState.find_object("n-1").get("z", 0.0)), 15.0, 0.001, "shift 5 m −z")
	t.near(float(MapState.find_object("n-2").get("z", 0.0)), 35.0, 0.001)
	UndoStack.undo()

	t.ok(EditActions.try_select_transform(KEY_R, false, log), "R rotates")
	t.near(float(MapState.find_object("n-1").get("yaw_deg", 0.0)), 25.0, 0.001, "+15 yaw")
	t.near(float(MapState.find_object("n-2").get("yaw_deg", 0.0)), -175.0, 0.001, "yaw wraps")
	t.ok("rotated" in logs[logs.size() - 1])
	UndoStack.undo()
	t.near(float(MapState.find_object("n-1").get("yaw_deg", 0.0)), 10.0, 0.001)
	t.near(float(MapState.find_object("n-2").get("yaw_deg", 0.0)), 170.0, 0.001)
	t.ok(not UndoStack.can_undo(), "rotate is one undo step")

	t.ok(EditActions.try_select_transform(KEY_R, true, log), "Shift+R")
	t.near(float(MapState.find_object("n-1").get("yaw_deg", 0.0)), 100.0, 0.001, "+90 yaw")
	UndoStack.undo()

	t.near(EditActions.wrap_yaw_deg(185.0), -175.0, 0.001)
	t.near(EditActions.wrap_yaw_deg(-180.0), 180.0, 0.001)

	var le := LineEdit.new()
	t.tree.root.add_child(le)
	le.grab_focus()
	# Focus grab is best-effort in headless; the helper still classifies LineEdit.
	if le.has_focus():
		t.ok(EditActions.gui_text_focused(t.tree.root.get_viewport()), "LineEdit counts as text focus")
	le.queue_free()


func _help_keys(t) -> void:
	var help: Node = load("res://project/ui/help/HelpWindow.tscn").instantiate()
	t.tree.root.add_child(help)
	await t.tree.process_frame
	var body: RichTextLabel = help.find_child("Body", true, false)
	t.ok("nudge" in body.text.to_lower(), "help lists nudge")
	t.ok("Shift+R" in body.text, "help lists Shift+R")
	t.ok("+15" in body.text, "help lists +15°")
	help.queue_free()
	await t.tree.process_frame


func _rec(id: String, x: float, z: float, yaw: float, team: int, label: String, pin: bool, y: float) -> Dictionary:
	return {
		"id": id, "prjid": "avapc", "label": label,
		"x": x, "y": y, "z": z, "yaw_deg": yaw,
		"team": team, "pinned_y": pin, "required": false,
		"placement_mode": "clone",
	}


func _flat(gx: int, gz: int, raw: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	field.heights.fill(raw)
	return field


func _btn(root: Node, name: String) -> Button:
	return root.find_child(name, true, false) as Button
