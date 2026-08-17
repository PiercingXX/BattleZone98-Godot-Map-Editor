extends RefCounted
## TopBar: session/busy/undo enablement, tools, variants, More menu.


func run(t) -> void:
	var saved_session := MapState.has_session
	var saved_root := Settings.game_root
	UndoStack.clear()
	MapState.has_session = false
	Settings.game_root = ""

	var bar: Node = load("res://project/ui/top_bar/TopBar.tscn").instantiate()
	t.tree.root.add_child(bar)
	await t.tree.process_frame

	t.ok(_btn(bar, "Save").disabled, "Save disabled with no map")
	t.ok(_btn(bar, "Validate").disabled, "Validate disabled with no map")
	t.ok(_btn(bar, "Frame").disabled, "Frame disabled with no map")
	t.ok(_btn(bar, "Undo").disabled, "Undo disabled when stack empty")
	t.ok(_btn(bar, "Redo").disabled, "Redo disabled when stack empty")
	t.ok(not _btn(bar, "Open").disabled, "Open stays available")
	t.ok(not _btn(bar, "New").disabled, "New stays available")
	t.ok((bar.find_child("Variant", true, false) as OptionButton).disabled, "variant empty/disabled")

	var tools: Array = []
	bar.tool_selected.connect(func(n): tools.append(n))
	_btn(bar, "Raise").pressed.emit()
	_btn(bar, "Place").pressed.emit()
	_btn(bar, "Noise").pressed.emit()
	t.eq(tools, ["raise", "place", "noise"], "tool buttons emit lower-case names")

	bar.set_tool("flatten")
	t.ok(_btn(bar, "Flatten").button_pressed, "set_tool flatten presses Flat")
	bar.set_tool("select")
	t.ok(_btn(bar, "Select").button_pressed, "set_tool select")

	var framed := [0]
	bar.frame_requested.connect(func(): framed[0] += 1)
	_btn(bar, "Frame").pressed.emit()
	t.eq(framed[0], 0, "Frame no-ops without a session (button disabled; signal not relied on)")

	MapState.has_session = true
	MapState.session_changed.emit()
	t.ok(not _btn(bar, "Save").disabled, "Save enabled with session")
	t.ok(not _btn(bar, "Validate").disabled, "Validate enabled with session")
	t.ok(not _btn(bar, "Frame").disabled, "Frame enabled with session")

	_btn(bar, "Frame").pressed.emit()
	t.eq(framed[0], 1, "Frame emits when a map is open")

	bar.fill_variants(["", "_S", "_ST", "_SW"], "_S")
	t.eq(bar.selected_variant(), "_S")
	var variant: OptionButton = bar.find_child("Variant", true, false)
	t.ok(not variant.disabled)
	t.eq(variant.get_item_text(0), "DM")
	var saw_variant := [false]
	bar.variant_changed.connect(func(): saw_variant[0] = true)
	variant.select(2)
	variant.item_selected.emit(2)
	t.ok(saw_variant[0], "variant dropdown emits")
	t.eq(bar.selected_variant(), "_ST")

	UndoStack.push(_Nop.new())
	t.ok(not _btn(bar, "Undo").disabled, "Undo enables after push")
	t.ok(_btn(bar, "Redo").disabled)
	UndoStack.undo()
	t.ok(_btn(bar, "Undo").disabled)
	t.ok(not _btn(bar, "Redo").disabled, "Redo enables after undo")

	bar.set_busy(true)
	t.ok(_btn(bar, "Open").disabled, "Open disabled while busy")
	t.ok(_btn(bar, "Save").disabled, "Save disabled while busy")
	t.ok(_btn(bar, "New").disabled, "New disabled while busy")
	bar.set_busy(false)
	t.ok(not _btn(bar, "Save").disabled, "Save re-enabled after busy, session still open")

	var pop: PopupMenu = (bar.find_child("More", true, false) as MenuButton).get_popup()
	t.ok(pop.is_item_disabled(pop.get_item_index(bar.MORE_IMPORT)), "Import disabled without game_root")
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_RENDER)), "Render enabled with session")
	t.ok(pop.is_item_disabled(pop.get_item_index(bar.MORE_INSTALL)), "Install needs game_root")
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_PACK)))
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_SAVE_AS)))
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_HELP)))

	Settings.game_root = "/tmp/fake-bz"
	bar._refresh_more()
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_IMPORT)), "Import enables with game_root")
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_INSTALL)), "Install enables with session+root")

	var more_ids: Array = []
	var save_as := [0]
	bar.more_selected.connect(func(id): more_ids.append(id))
	bar.save_as_requested.connect(func(): save_as[0] += 1)
	pop.id_pressed.emit(bar.MORE_PROBE)
	pop.id_pressed.emit(bar.MORE_SAVE_AS)
	t.eq(more_ids, [bar.MORE_PROBE], "Save As is intercepted")
	t.eq(save_as[0], 1)

	bar.queue_free()
	await t.tree.process_frame
	UndoStack.clear()
	MapState.has_session = saved_session
	Settings.game_root = saved_root


func _btn(root: Node, name: String) -> Button:
	return root.find_child(name, true, false) as Button


class _Nop:
	extends RefCounted
	func do() -> void:
		pass
	func undo() -> void:
		pass
