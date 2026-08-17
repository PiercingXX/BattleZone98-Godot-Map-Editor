extends RefCounted
## Findings: empty state, Validate enablement, click-select, double-click fly.


func run(t) -> void:
	var saved_session := MapState.has_session
	MapState.has_session = false

	var panel: Node = load("res://project/ui/findings/FindingsPanel.tscn").instantiate()
	t.tree.root.add_child(panel)
	await t.tree.process_frame

	var list: ItemList = panel.find_child("List", true, false)
	var validate: Button = panel.find_child("Validate", true, false)
	t.ok(validate.disabled, "Validate disabled with no map")
	t.ok(list.item_count >= 1)
	t.ok(list.is_item_disabled(0), "empty placeholder disabled")

	var selected: Array = []
	var flown: Array = []
	var validates: Array = []
	panel.finding_selected.connect(func(f): selected.append(f.get("title", "")))
	panel.finding_activated.connect(func(f): flown.append(f.get("title", "")))
	panel.validate_requested.connect(func(): validates.append(1))
	validate.pressed.emit()
	t.eq(validates.size(), 0, "Validate does not emit without a session")

	MapState.has_session = true
	MapState.session_changed.emit()
	t.ok(not validate.disabled, "Validate enabled with a session")
	validate.pressed.emit()
	t.eq(validates.size(), 1)

	var findings := [
		{"severity": "error", "title": "missing player", "object_id": "p1", "world_pos": [10, 2, 20]},
		{"severity": "warning", "title": "no position"},
		{"severity": "info", "title": "somewhere", "world_pos": [1, 2, 3]},
	]
	panel.set_findings(findings, false)
	t.eq(list.item_count, 3)
	t.ok("error" in list.get_item_text(0))

	list.item_selected.emit(0)
	t.eq(selected, ["missing player"])
	list.item_activated.emit(0)
	t.eq(flown, ["missing player"])

	list.item_selected.emit(1)
	t.eq(selected.size(), 1, "finding without object/pos does not emit select")
	list.item_activated.emit(1)
	t.eq(flown.size(), 1, "finding without object/pos does not emit fly")

	list.item_selected.emit(2)
	t.eq(selected, ["missing player", "somewhere"], "world_pos-only still selects")

	panel.set_findings(findings, true)
	t.ok(list.get_item_text(0).begins_with("(stale)"), "stale prefix")

	panel.set_findings([], false)
	t.ok(list.is_item_disabled(0), "empty-after-validate placeholder")
	t.ok("No findings" in list.get_item_text(0))

	MapState.has_session = false
	MapState.session_changed.emit()
	t.ok(validate.disabled, "Validate disables when the map closes")

	panel.queue_free()
	await t.tree.process_frame
	MapState.has_session = saved_session
