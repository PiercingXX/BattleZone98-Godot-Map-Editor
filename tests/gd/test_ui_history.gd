extends RefCounted
## History panel: named steps, highlight, click jumps via undo/redo.


func run(t) -> void:
	UndoStack.clear()
	var panel: Node = load("res://project/ui/history/HistoryPanel.tscn").instantiate()
	t.tree.root.add_child(panel)
	await t.tree.process_frame

	var list: ItemList = panel.find_child("List", true, false)
	var toggle: Button = panel.find_child("Toggle", true, false)
	t.ok(list != null and toggle != null)
	t.ok(toggle.button_pressed, "starts expanded")
	t.ok(list.visible)
	t.eq(list.item_count, 1)
	t.ok(list.is_item_disabled(0), "empty placeholder")
	t.ok("No edits" in list.get_item_text(0))

	toggle.button_pressed = false
	t.ok(not list.visible, "collapse hides the list")
	toggle.button_pressed = true
	t.ok(list.visible)

	var log: Array = []
	UndoStack.push(_Cmd.new(log, "a"))
	UndoStack.push(_Cmd.new(log, "b"))
	UndoStack.push(_Cmd.new(log, "raise", "raise stroke"))
	t.eq(list.item_count, 3)
	t.eq(list.get_item_text(0), "step a")
	t.eq(list.get_item_text(1), "step b")
	t.eq(list.get_item_text(2), "raise stroke")
	t.eq(UndoStack.current_index(), 2)
	t.ok(list.is_selected(2), "current step highlighted")

	list.item_clicked.emit(0, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	t.eq(UndoStack.current_index(), 0, "click jumps backward")
	t.eq(log, ["do:a", "do:b", "do:raise", "undo:raise", "undo:b"], "jump undoes in order")
	t.ok(list.is_selected(0))

	list.item_clicked.emit(2, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	t.eq(UndoStack.current_index(), 2, "click jumps forward")
	t.eq(log, [
		"do:a", "do:b", "do:raise", "undo:raise", "undo:b", "do:b", "do:raise",
	], "jump redos in order")

	list.item_clicked.emit(0, Vector2.ZERO, MOUSE_BUTTON_RIGHT)
	t.eq(UndoStack.current_index(), 2, "right-click does not jump")

	panel.queue_free()
	await t.tree.process_frame
	UndoStack.clear()


class _Cmd:
	extends RefCounted
	var log: Array
	var tag: String
	var label: String

	func _init(p_log: Array, p_tag: String, p_label: String = "") -> void:
		log = p_log
		tag = p_tag
		label = p_label

	func do() -> void:
		log.append("do:%s" % tag)

	func undo() -> void:
		log.append("undo:%s" % tag)

	func describe() -> String:
		return label if not label.is_empty() else "step %s" % tag
