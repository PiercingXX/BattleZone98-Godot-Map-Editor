extends RefCounted
## CommandPalette: debounced fuzzy filter, arrow forwarding, Enter, Escape.


func run(t) -> void:
	var saved_session := MapState.has_session
	MapState.has_session = false

	var reg := CommandRegistry.new()
	reg.scan(PackedStringArray([CommandRegistry.BUILTIN_DIR]))
	var actions: Array[String] = []
	var ctx := CommandContext.new()
	ctx.bind(CommandContext.HOOK_ACTION, func(a: String) -> void:
		actions.append(a)
	)

	var pal := CommandPalette.new()
	pal.context = ctx
	t.tree.root.add_child(pal)
	await t.tree.process_frame
	pal.set_registry(reg)

	var search: LineEdit = pal.find_child("Search", true, false)
	var list: ItemList = pal.find_child("Results", true, false)
	var detail: Label = pal.find_child("Detail", true, false)
	var status: Label = pal.find_child("Status", true, false)
	t.ok(search != null and list != null, "palette is built in code")
	t.ok(not pal.visible, "the palette starts hidden")
	t.eq(pal.visible_ids().size(), reg.size(), "everything is listed at rest")
	t.eq(list.item_count, reg.size())
	t.eq(status.text, "%d commands" % reg.size(), "the count is on screen")

	# Category and chord ride along with the title: the palette doubles as
	# the discoverability surface for chords nobody remembers.
	var row := str(list.get_item_text(pal.visible_ids().find("help.hotkeys")))
	t.ok(row.begins_with("Hotkey list"))
	t.ok(row.contains("Help"), "category is shown")
	t.ok(row.contains(Keymap.format_action(Keymap.ACTION_HELP)), "chord shown")

	# Gated commands stay listed and greyed rather than disappearing.
	var frame_i := pal.visible_ids().find("view.frame_map")
	t.ok(frame_i >= 0, "a command you cannot run is still findable")
	t.eq(list.get_item_custom_fg_color(frame_i), CommandPalette.DIM_FG,
		"and is drawn as unavailable")
	t.ok(str(list.get_item_tooltip(frame_i)).begins_with("Unavailable"))
	var open_i := pal.visible_ids().find("help.hotkeys")
	t.ne(list.get_item_custom_fg_color(open_i), CommandPalette.DIM_FG,
		"a runnable command is not dimmed")

	# Debounce: typing does not re-rank until the timer fires.
	search.text = "frame"
	search.text_changed.emit("frame")
	t.eq(list.item_count, reg.size(), "the filter is debounced, not instant")
	var timer: Timer = pal.find_child("FilterDebounce", true, false)
	t.ok(timer != null and timer.one_shot)
	t.ok(timer.wait_time >= 0.2 and timer.wait_time <= 0.3, "~0.25 s")
	t.ok(not timer.is_stopped(), "a keystroke restarts the debounce")
	pal.flush_filter()
	t.ok(pal.visible_ids().size() < reg.size(), "the filter narrowed")
	t.eq(str(pal.visible_ids()[0]), "view.frame_map", "best match ranks first")

	search.text = "toggle"
	search.text_changed.emit("toggle")
	pal.flush_filter()
	var many := pal.visible_ids().size()
	t.ok(many >= 13, "fuzzy filter finds every view toggle")

	# Arrow keys are forwarded from the search box, so the caret never
	# leaves it.
	t.eq(list.get_selected_items()[0], 0)
	search.gui_input.emit(_key(KEY_DOWN))
	t.eq(list.get_selected_items()[0], 1, "Down moves the highlight")
	search.gui_input.emit(_key(KEY_DOWN))
	t.eq(list.get_selected_items()[0], 2)
	search.gui_input.emit(_key(KEY_UP))
	t.eq(list.get_selected_items()[0], 1, "Up moves it back")
	var paged := mini(1 + CommandPalette.PAGE_STEP, many - 1)
	search.gui_input.emit(_key(KEY_PAGEDOWN))
	t.eq(list.get_selected_items()[0], paged, "PageDown jumps a page")
	search.gui_input.emit(_key(KEY_PAGEUP))
	t.eq(list.get_selected_items()[0], maxi(0, paged - CommandPalette.PAGE_STEP))
	search.gui_input.emit(_key(KEY_PAGEUP))
	t.eq(list.get_selected_items()[0], 0, "PageUp clamps at the top")
	search.gui_input.emit(_key(KEY_UP))
	t.eq(list.get_selected_items()[0], 0, "and does not wrap past it")
	t.eq(search.text, "toggle", "arrows never edit the text")
	t.ok(not detail.text.is_empty(), "the highlighted command explains itself")

	# Enter invokes what is highlighted.
	var invoked: Array[String] = []
	pal.command_invoked.connect(func(id: String) -> void: invoked.append(id))
	pal.open_palette()
	t.ok(pal.visible, "open_palette shows it")
	t.eq(search.text, "", "and resets the filter")
	search.text = "hotkey"
	search.text_changed.emit("hotkey")
	search.gui_input.emit(_key(KEY_ENTER))
	t.eq(invoked, ["help.hotkeys"] as Array[String], "Enter runs the pick")
	t.eq(actions, [Keymap.ACTION_HELP] as Array[String], "and it reached the shell")
	t.ok(not pal.visible, "running dismisses the palette")

	# A gated command refuses, says so, and leaves the palette open.
	invoked.clear()
	actions.clear()
	pal.open_palette()
	search.text = "frame map"
	search.text_changed.emit("frame map")
	search.gui_input.emit(_key(KEY_ENTER))
	t.eq(invoked, [] as Array[String], "is_enabled() gates the palette too")
	t.eq(actions, [] as Array[String])
	t.ok(pal.visible, "and the palette stays up")
	t.ok(detail.text.begins_with("Unavailable"),
		"a greyed row still highlights and still explains itself")

	# Escape dismisses without running anything.
	search.gui_input.emit(_key(KEY_ESCAPE))
	t.ok(not pal.visible, "Escape dismisses")
	t.eq(invoked, [] as Array[String])

	# Enabling the map re-enables the entry on the next rebuild.
	MapState.has_session = true
	pal.open_palette()
	search.text = "frame map"
	search.text_changed.emit("frame map")
	pal.flush_filter()
	t.ne(list.get_item_custom_fg_color(0), CommandPalette.DIM_FG,
		"the gate lifts with a session")
	search.gui_input.emit(_key(KEY_ENTER))
	t.eq(invoked, ["view.frame_map"] as Array[String])

	# No match is a visible statement, not an empty box.
	pal.open_palette()
	search.text = "qqqqqq"
	search.text_changed.emit("qqqqqq")
	pal.flush_filter()
	t.eq(pal.visible_ids().size(), 0)
	t.eq(list.item_count, 1)
	t.ok(list.is_item_disabled(0))
	t.ok(str(list.get_item_text(0)).contains("qqqqqq"))
	t.ok(not pal.run_selected(), "Enter on a no-match does nothing")

	t.ok(CommandPalette.is_open_chord(_chord(KEY_P, true, true)),
		"the coordinator has one chord to wire")
	t.ok(not CommandPalette.is_open_chord(_chord(KEY_P, true, false)))
	t.ok(not CommandPalette.is_open_chord(_key(KEY_P)))

	pal.queue_free()
	MapState.has_session = saved_session


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _chord(code: Key, ctrl: bool, shift: bool) -> InputEventKey:
	var e := _key(code)
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	return e
