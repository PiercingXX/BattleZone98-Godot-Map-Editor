extends RefCounted
## Inspector: leftover-field clear, enablement, apply/delete, pin Y, water undo.


func run(t) -> void:
	var saved_session := MapState.has_session
	var saved_feat: Dictionary = MapState.features.duplicate(true)
	var saved_dirty: Dictionary = MapState.dirty.duplicate(true)
	var saved_stem := MapState.stem
	var saved_sel: Array[String] = MapState.selected_ids.duplicate()
	UndoStack.clear()
	MapState.has_session = false
	MapState.stem = "testmap"
	MapState.features = {"water": [], "plants": []}
	MapState.selected_ids.clear()

	var insp: Node = load("res://project/ui/inspector/InspectorPanel.tscn").instantiate()
	t.tree.root.add_child(insp)
	await t.tree.process_frame

	t.ok(_btn(insp, "Apply").disabled, "Apply disabled with no selection")
	t.ok(_btn(insp, "Delete").disabled, "Delete disabled with no selection")
	t.ok(not (insp.find_child("Label", true, false) as LineEdit).editable)
	t.ok(not (insp.find_child("Water", true, false) as SpinBox).editable, "water locked with no session")

	var water: SpinBox = insp.find_child("Water", true, false)
	var before_w := MapState.water_level()
	water.value = 40.0
	t.near(MapState.water_level(), before_w, 0.001, "water does not mutate without a session")
	t.near(water.value, before_w, 0.001, "water spinbox reverts")

	var rec := {
		"id": "obj-1", "prjid": "avapc", "label": "scout",
		"x": 100.0, "y": 20.0, "z": 50.0, "yaw_deg": 45.0,
		"team": 2, "pinned_y": false, "required": false, "placement_mode": "clone",
	}
	insp.show_object(rec)
	t.eq((insp.find_child("Prj", true, false) as LineEdit).text, "avapc")
	t.eq((insp.find_child("Label", true, false) as LineEdit).text, "scout")
	t.eq((insp.find_child("X", true, false) as SpinBox).value, 100.0)
	t.ok(not (insp.find_child("Y", true, false) as SpinBox).editable, "Y locked when unpinned")
	t.ok(not _btn(insp, "Apply").disabled)
	t.ok(not _btn(insp, "Delete").disabled)

	insp.clear()
	t.eq((insp.find_child("Label", true, false) as LineEdit).text, "")
	t.eq((insp.find_child("X", true, false) as SpinBox).value, 0.0)
	t.eq((insp.find_child("Y", true, false) as SpinBox).value, 0.0)
	t.eq((insp.find_child("Z", true, false) as SpinBox).value, 0.0)
	t.eq((insp.find_child("Yaw", true, false) as SpinBox).value, 0.0)
	t.eq((insp.find_child("Team", true, false) as SpinBox).value, 0.0)
	t.eq((insp.find_child("Mode", true, false) as Label).text, "nothing selected")
	t.ok(_btn(insp, "Apply").disabled, "Apply disabled after clear")

	var applies: Array = []
	var deletes: Array = []
	insp.apply_requested.connect(func(edits): applies.append(edits))
	insp.delete_requested.connect(func(): deletes.append(1))

	MapState.has_session = true
	var pinned := rec.duplicate(true)
	pinned["pinned_y"] = true
	insp.show_object(pinned)
	_btn(insp, "Apply").pressed.emit()
	t.eq(applies.size(), 0, "Apply with no edits is a no-op")
	t.ok(not insp.is_field_dirty("label"), "fill does not dirty fields")

	insp.show_object(pinned)
	(insp.find_child("Label", true, false) as LineEdit).text = "renamed"
	t.ok(insp.is_field_dirty("label"), "label edit is dirty")
	t.ok(not insp.is_field_dirty("x"), "untouched x stays clean")
	_btn(insp, "Apply").pressed.emit()
	t.eq(applies.size(), 1, "Apply emits when a field changed")
	t.eq(applies[0].size(), 1, "single-select apply is one edit")
	t.eq(applies[0][0]["after"].get("label"), "renamed")
	t.ok(not insp.is_field_dirty("label"), "apply clears dirty")

	insp.show_object({
		"id": "player-1", "prjid": "player", "label": "player",
		"x": 0.0, "y": 0.0, "z": 0.0, "yaw_deg": 0.0,
		"team": 1, "pinned_y": false, "required": true,
	})
	t.ok(_btn(insp, "Delete").disabled, "Delete disabled for required player")
	_btn(insp, "Delete").pressed.emit()
	t.eq(deletes.size(), 0, "Delete on required does not emit")

	insp.show_object(rec)
	_btn(insp, "Delete").pressed.emit()
	t.eq(deletes.size(), 1)

	var pin: CheckBox = insp.find_child("PinHeight", true, false)
	insp.show_object(rec)
	pin.button_pressed = true
	t.ok((insp.find_child("Y", true, false) as SpinBox).editable, "Y editable when pinned")

	MapState.selected_ids = ["obj-1", "obj-2"] as Array[String]
	insp.show_object(rec)
	t.ok("2 selected" in (insp.find_child("Mode", true, false) as Label).text)
	t.ok("apply edits the first" not in (insp.find_child("Mode", true, false) as Label).text)
	var label_edit: LineEdit = insp.find_child("Label", true, false)
	t.ok(not label_edit.editable, "label locked on multi-select")
	t.ok("one object" in label_edit.tooltip_text, "label tooltip says why")
	t.ok("all 2 selected" in _btn(insp, "Apply").tooltip_text)
	(insp.find_child("Team", true, false) as SpinBox).value = 7
	t.ok(insp.is_field_dirty("team"), "team edit is dirty")
	t.ok(not insp.is_field_dirty("x"), "untouched x stays clean on multi")

	# Water live-preview + undoable commit.
	insp.set_water(-1.0)
	water.value = 92.0
	t.near(MapState.water_level(), 92.0, 0.001, "water live-previews")
	insp.commit_water()
	t.ok(UndoStack.can_undo(), "water commit pushed undo")
	UndoStack.undo()
	t.near(MapState.water_level(), -1.0, 0.001, "water undo restores")
	UndoStack.redo()
	t.near(MapState.water_level(), 92.0, 0.001, "water redo")

	MapState.has_session = false
	MapState.session_changed.emit()
	t.eq((insp.find_child("Mode", true, false) as Label).text, "nothing selected", "session close clears inspector")
	t.ok(not water.editable, "water locks after session close")

	insp.queue_free()
	await t.tree.process_frame
	UndoStack.clear()
	MapState.has_session = saved_session
	MapState.features = saved_feat
	MapState.dirty = saved_dirty
	MapState.stem = saved_stem
	MapState.selected_ids = saved_sel
	if saved_session:
		MapState.mark_saved()


func _btn(root: Node, name: String) -> Button:
	return root.find_child(name, true, false) as Button
