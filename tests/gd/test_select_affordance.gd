extends RefCounted
## Viewport selection affordances: marquee hit-test, selection apply, hover copy.


func run(t) -> void:
	var saved_session := MapState.has_session
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_sel: Array[String] = MapState.selected_ids.duplicate()
	var saved_variant := MapState.active_variant
	var saved_tool := ToolState.tool
	UndoStack.clear()
	MapState.has_session = true
	MapState.active_variant = ""
	MapState.objects = {}
	MapState.selected_ids.clear()

	_hit_test(t)
	_select_apply(t)
	await _status_and_help(t)
	_markers_style(t)

	UndoStack.clear()
	MapState.has_session = saved_session
	MapState.objects = saved_objects
	MapState.selected_ids = saved_sel
	MapState.active_variant = saved_variant
	ToolState.set_tool(saved_tool if saved_tool != "" else "fly")
	if saved_session:
		MapState.mark_saved()


func _hit_test(t) -> void:
	var r := EditActions.screen_rect_from_drag(Vector2(100, 50), Vector2(20, 80))
	t.near(r.position.x, 20.0, 0.001, "drag order min x")
	t.near(r.position.y, 50.0, 0.001, "drag order min y")
	t.near(r.size.x, 80.0, 0.001)
	t.near(r.size.y, 30.0, 0.001)
	var r2 := EditActions.screen_rect_from_drag(Vector2(20, 80), Vector2(100, 50))
	t.eq(r, r2, "drag endpoints commute")
	var z := EditActions.screen_rect_from_drag(Vector2(4, 4), Vector2(4, 4))
	t.near(z.size.x, 0.0, 0.001, "zero-size drag")
	t.near(z.size.y, 0.0, 0.001)

	t.ok(not EditActions.is_marquee_drag(Vector2.ZERO, Vector2(3, 0)), "3 px is a click")
	t.ok(EditActions.is_marquee_drag(Vector2.ZERO, Vector2(4, 0)), "4 px is a drag")
	t.ok(EditActions.is_marquee_drag(Vector2.ZERO, Vector2(0, 4)))
	t.ok(not EditActions.is_marquee_drag(Vector2.ZERO, Vector2(3, 0), 8.0), "custom threshold")

	var box := Rect2(Vector2(10, 10), Vector2(20, 20))
	t.ok(EditActions.point_in_screen_rect(Vector2(10, 10), box), "top-left inclusive")
	t.ok(EditActions.point_in_screen_rect(Vector2(30, 30), box), "bottom-right inclusive")
	t.ok(EditActions.point_in_screen_rect(Vector2(20, 20), box), "center")
	t.ok(not EditActions.point_in_screen_rect(Vector2(31, 20), box), "outside right")
	t.ok(not EditActions.point_in_screen_rect(Vector2(9, 10), box), "outside left")

	var points := {
		"in": Vector2(20, 20),
		"tl": Vector2(10, 10),
		"br": Vector2(30, 30),
		"out": Vector2(31, 20),
		"out2": Vector2(9, 10),
		"skip": "not-a-point",
	}
	t.eq(EditActions.ids_in_screen_rect(points, box), ["br", "in", "tl"] as Array[String], "sorted hits")
	t.eq(EditActions.ids_in_screen_rect({}, box), [] as Array[String], "empty points")
	t.eq(EditActions.ids_in_screen_rect(points, Rect2()), [] as Array[String], "empty rect misses interior")
	t.eq(
		EditActions.ids_in_screen_rect({"a": Vector2(0, 0)}, Rect2()),
		["a"] as Array[String],
		"zero rect hits the origin",
	)

	t.eq(EditActions.hover_status_text("eggeizr1", "Geyser 1"), "eggeizr1 Geyser 1 — click to select")
	t.eq(EditActions.hover_status_text("npscr1", ""), "npscr1  — click to select")


func _select_apply(t) -> void:
	var logs: Array = []
	var log := func(msg): logs.append(str(msg))
	UndoStack.clear()
	MapState.selected_ids = ["keep"] as Array[String]

	EditActions.select_id("", true, log)
	t.eq(MapState.selected_ids, ["keep"] as Array[String], "shift empty click keeps")
	t.eq(logs.size(), 0, "shift empty click is silent")

	EditActions.select_id("", false, log)
	t.eq(MapState.selected_ids, [] as Array[String], "empty click clears")
	t.ok(not logs.is_empty() and logs[logs.size() - 1] == "selection cleared")
	t.ok(not UndoStack.can_undo(), "clearing selection is not an undo step")

	EditActions.select_id("a", false, log)
	t.eq(MapState.selected_ids, ["a"] as Array[String], "replace with one")
	EditActions.select_id("b", true, log)
	t.eq(MapState.selected_ids, ["a", "b"] as Array[String], "shift adds")
	EditActions.select_id("a", true, log)
	t.eq(MapState.selected_ids, ["b"] as Array[String], "shift toggles off")
	EditActions.select_id("c", false, log)
	t.eq(MapState.selected_ids, ["c"] as Array[String], "click replaces")
	t.ok(not UndoStack.can_undo(), "select_id is not an undo step")

	logs.clear()
	EditActions.select_marquee(["x", "y", "x", ""], false, log)
	t.eq(MapState.selected_ids, ["x", "y"] as Array[String], "marquee replace dedupes")
	t.eq(logs[logs.size() - 1], "selected 2 objects")

	logs.clear()
	EditActions.select_marquee(["y", "z"], true, log)
	t.eq(MapState.selected_ids, ["x", "y", "z"] as Array[String], "shift marquee unions")
	t.eq(logs[logs.size() - 1], "added 1 to selection")

	logs.clear()
	EditActions.select_marquee([], true, log)
	t.eq(MapState.selected_ids, ["x", "y", "z"] as Array[String], "empty shift marquee keeps")
	t.eq(logs.size(), 0)

	logs.clear()
	EditActions.select_marquee([], false, log)
	t.eq(MapState.selected_ids, [] as Array[String], "empty marquee clears")
	t.eq(logs[logs.size() - 1], "selection cleared")
	t.ok(not UndoStack.can_undo(), "marquee is not an undo step")

	logs.clear()
	EditActions.select_marquee(["only"], false, log)
	t.eq(logs[logs.size() - 1], "selected 1 object")

	# Pure helper path used by the viewport: screen points → ids → apply.
	var pts := {"g1": Vector2(5, 5), "s1": Vector2(50, 50), "b1": Vector2(200, 8)}
	var hits := EditActions.ids_in_screen_rect(pts, EditActions.screen_rect_from_drag(Vector2(0, 0), Vector2(60, 60)))
	t.eq(hits, ["g1", "s1"] as Array[String])
	EditActions.select_marquee(hits, false, log)
	t.eq(MapState.selected_ids, ["g1", "s1"] as Array[String])


func _status_and_help(t) -> void:
	var bar: Node = load("res://project/ui/status/StatusBar.tscn").instantiate()
	t.tree.root.add_child(bar)
	await t.tree.process_frame
	var sel: Label = bar.find_child("SelectionCount", true, false)
	t.ok(sel != null, "status bar has a selection count label")
	t.ok(not sel.visible, "count hidden by default")
	bar.set_selection_count(0, true)
	t.ok(sel.visible)
	t.eq(sel.text, "0 selected")
	bar.set_selection_count(3, true)
	t.eq(sel.text, "3 selected")
	bar.set_selection_count(1, false)
	t.ok(not sel.visible)
	t.eq(sel.text, "")
	bar.queue_free()
	await t.tree.process_frame

	var help: Node = load("res://project/ui/help/HelpWindow.tscn").instantiate()
	t.tree.root.add_child(help)
	await t.tree.process_frame
	var body: RichTextLabel = help.find_child("Body", true, false)
	var text := body.text.to_lower()
	t.ok("box-select" in text or "marquee" in text, "help documents box-select")
	t.ok("shift" in text, "help mentions Shift-add")
	t.ok("team" in text, "help mentions team assign")
	t.ok("view" in text, "help mentions view filters")
	help.queue_free()
	await t.tree.process_frame


func _markers_style(t) -> void:
	var markers := ObjectMarkers.new()
	t.tree.root.add_child(markers)
	markers.highlight(["missing"])
	markers.set_hover("also-missing")
	t.eq(markers.hovered_id(), "also-missing")
	t.eq(markers.screen_points(null), {}, "no camera → no points")
	markers.set_hover("")
	t.eq(markers.hovered_id(), "")
	markers.reset()
	markers.queue_free()
