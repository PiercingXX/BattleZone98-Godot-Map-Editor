extends RefCounted
## Team quick-assign: one undo step, inspector row, objects.json persist.


func run(t) -> void:
	var saved_session := MapState.has_session
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_dirty: Dictionary = MapState.dirty.duplicate(true)
	var saved_sel: Array[String] = MapState.selected_ids.duplicate()
	var saved_variant := MapState.active_variant
	var saved_dir := MapState.session_dir
	var saved_feat: Dictionary = MapState.features.duplicate(true)
	var saved_field = MapState.field
	UndoStack.clear()
	MapState.has_session = true
	MapState.active_variant = ""
	MapState.dirty = {}
	MapState.features = {"water": [], "plants": []}

	_quick_assign_undo(t)
	_persist_objects_json(t)
	await _inspector_row(t)
	_keymap_chords(t)

	UndoStack.clear()
	MapState.has_session = saved_session
	MapState.objects = saved_objects
	MapState.dirty = saved_dirty
	MapState.selected_ids = saved_sel
	MapState.active_variant = saved_variant
	MapState.session_dir = saved_dir
	MapState.features = saved_feat
	MapState.field = saved_field
	if saved_session:
		MapState.mark_saved()


func _quick_assign_undo(t) -> void:
	var a := _rec("t-a", 0)
	var b := _rec("t-b", 1)
	MapState.objects = {"": [a, b]}
	MapState.selected_ids = ["t-a", "t-b"] as Array[String]
	UndoStack.clear()
	var logs: Array = []
	var log := func(msg): logs.append(str(msg))

	var saved_sel: Array[String] = MapState.selected_ids.duplicate()
	MapState.selected_ids.clear()
	EditActions.set_selection_team(2, log)
	t.eq(logs[logs.size() - 1], "nothing selected")
	t.ok(not UndoStack.can_undo(), "empty selection is not an undo step")
	MapState.selected_ids = saved_sel

	logs.clear()
	EditActions.set_selection_team(2, log)
	t.eq(int(MapState.find_object("t-a").get("team", 0)), 2)
	t.eq(int(MapState.find_object("t-b").get("team", 0)), 2)
	t.eq(logs[logs.size() - 1], "team 2 → 2 objects")
	t.ok(UndoStack.can_undo(), "team assign pushed undo")
	UndoStack.undo()
	t.eq(int(MapState.find_object("t-a").get("team", 0)), 0)
	t.eq(int(MapState.find_object("t-b").get("team", 0)), 1)
	t.ok(not UndoStack.can_undo(), "whole assign is one undo step")
	UndoStack.redo()
	t.eq(int(MapState.find_object("t-a").get("team", 0)), 2)
	t.eq(int(MapState.find_object("t-b").get("team", 0)), 2)

	logs.clear()
	EditActions.set_selection_team(2, log)
	t.eq(logs[logs.size() - 1], "already team 2")
	UndoStack.undo()
	t.eq(int(MapState.find_object("t-a").get("team", 0)), 0)


func _persist_objects_json(t) -> void:
	var tmp := OS.get_temp_dir().path_join("bz_team_persist_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	MapState.session_dir = tmp
	MapState.has_session = true
	MapState.field = HeightField.new()
	MapState.objects = {"": [_rec("p-1", 0)]}
	MapState.selected_ids = ["p-1"] as Array[String]
	MapState.dirty = {}
	UndoStack.clear()
	var logs: Array = []
	EditActions.set_selection_team(3, func(msg): logs.append(str(msg)))
	t.eq(int(MapState.find_object("p-1").get("team", 0)), 3)
	t.eq(logs[logs.size() - 1], "team 3 → 1 object")
	MapState.persist()
	var path := tmp.path_join("objects.json")
	t.ok(FileAccess.file_exists(path), "persist wrote objects.json")
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	t.ok(typeof(disk) == TYPE_DICTIONARY)
	var recs: Array = disk.get("", [])
	t.eq(recs.size(), 1)
	t.eq(int(recs[0].get("team", -1)), 3, "team rides through MapState.persist")
	_rm_rf(tmp)


func _inspector_row(t) -> void:
	var a := _rec("i-a", 1)
	var b := _rec("i-b", 1)
	MapState.objects = {"": [a, b]}
	MapState.selected_ids = ["i-a", "i-b"] as Array[String]
	UndoStack.clear()
	var insp: Node = load("res://project/ui/inspector/InspectorPanel.tscn").instantiate()
	t.tree.root.add_child(insp)
	await t.tree.process_frame
	var t0: Button = insp.find_child("Team0", true, false)
	var t2: Button = insp.find_child("Team2", true, false)
	t.ok(t0 != null and t2 != null, "inspector has team quick-set buttons")
	insp.clear()
	t.ok(t0.disabled, "team buttons lock with no selection")
	t.ok("Nothing selected" in t0.tooltip_text)
	insp.show_object(a)
	t.ok(not t2.disabled)
	t2.pressed.emit()
	t.eq(int(MapState.find_object("i-a").get("team", 0)), 2, "button sets first")
	t.eq(int(MapState.find_object("i-b").get("team", 0)), 2, "button sets whole selection")
	t.eq(int((insp.find_child("Team", true, false) as SpinBox).value), 2)
	t.ok(UndoStack.can_undo())
	UndoStack.undo()
	t.eq(int(MapState.find_object("i-a").get("team", 0)), 1)
	t.eq(int(MapState.find_object("i-b").get("team", 0)), 1)
	insp.queue_free()
	await t.tree.process_frame
	UndoStack.clear()


func _keymap_chords(t) -> void:
	for scheme in [Keymap.SCHEME_GODOT, Keymap.SCHEME_GIMP]:
		for i in 8:
			var ev := InputEventKey.new()
			ev.keycode = KEY_0 + i
			ev.pressed = true
			ev.shift_pressed = true
			t.eq(Keymap.resolve(ev, scheme), "team.%d" % i, "%s Shift+%d" % [scheme, i])
		t.eq(Keymap.format_action("team.2", scheme), "Shift+2")
		t.eq(Keymap.team_from_action("team.4"), 4)
	t.eq(Keymap.team_from_action("tool.fly"), -1)
	t.eq(Keymap.find_conflicts(Keymap.SCHEME_GODOT).size(), 0)
	t.eq(Keymap.find_conflicts(Keymap.SCHEME_GIMP).size(), 0)


func _rec(id: String, team: int) -> Dictionary:
	return {
		"id": id, "prjid": "avapc", "label": id,
		"x": 0.0, "y": 0.0, "z": 0.0, "yaw_deg": 0.0,
		"team": team, "pinned_y": false, "required": false,
		"placement_mode": "clone",
	}


func _rm_rf(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var child := path.path_join(name)
		if dir.current_is_dir():
			_rm_rf(child)
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	DirAccess.remove_absolute(path)
