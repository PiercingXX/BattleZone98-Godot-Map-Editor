extends RefCounted
## The shell reaches the libraries that ship as class_name globals: the new
## sculpt kernels, the command palette and the minimap dock. Each of these
## was self-contained and unreachable until scenes/main.tscn wired it.

const ToolRailScript = preload("res://project/ui/tool_rail/ToolRail.gd")

const NEW_TOOLS: PackedStringArray = ["erode", "dilate", "setheight", "setangle"]


func run(t) -> void:
	_tables(t)
	_icons(t)
	await _shell(t)


## The tool tables agree with each other: rail order, icon map, keymap.
func _tables(t) -> void:
	for name in NEW_TOOLS:
		var node_name := name.capitalize()
		t.ok(node_name in ToolRailScript.ORDER, "%s is on the rail" % name)
		t.ok(ToolRailScript.ACTIONS.has(node_name), "%s has a rail action" % name)
		t.ok(EditorIcons.TOOL_ICONS.has(node_name), "%s has an icon" % name)
		t.ok(ToolState.is_height_brush(name), "%s is a height kernel" % name)
		t.ok(ToolState.is_brush_tool(name), "%s shows the brush ring" % name)
		t.ok(ToolState.is_stroke_tool(name), "%s opens a stroke" % name)
		var action := "tool.%s" % name
		t.ok(action in Keymap.TOOL_ACTIONS, "%s is a tool action" % action)
		t.ok(action in Keymap.ALL_ACTIONS, "%s ships" % action)
		t.ok(KeymapRegistry.has_action(action), "%s is seeded" % action)
	# Both shipped schemes bind all four, and neither scheme gained a clash.
	for scheme in [Keymap.SCHEME_GODOT, Keymap.SCHEME_GIMP]:
		var table := KeymapRegistry.defaults_for(scheme)
		for name in NEW_TOOLS:
			t.ok(KeyAction.is_bound(table.get("tool.%s" % name, {})),
				"%s binds tool.%s" % [scheme, name])
		t.eq(Keymap.find_conflicts_in(table).size(), 0, "%s stays clean" % scheme)
	t.eq(Keymap.resolve(_key(KEY_E), Keymap.SCHEME_GODOT), "tool.erode")
	t.eq(Keymap.resolve(_key(KEY_E, false, true), Keymap.SCHEME_GODOT), "tool.dilate")
	t.eq(Keymap.resolve(_key(KEY_T), Keymap.SCHEME_GIMP), "tool.setheight")
	t.eq(Keymap.resolve(_key(KEY_T, false, true), Keymap.SCHEME_GIMP), "tool.setangle")
	t.eq(str(DockLayout.TITLES.get("MinimapPanel", "")), "Minimap")


## Missing art silently falls back to the fly glyph, so assert the files.
func _icons(t) -> void:
	for name in NEW_TOOLS:
		t.ok(EditorIcons.texture(name) != null, "%s.svg imports" % name)


func _shell(t) -> void:
	var saved_session := MapState.has_session
	var saved_worker: Callable = Backend.test_worker
	var saved_tool := ToolState.tool
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

	var rail: Node = scene.find_child("ToolRail", true, false)
	t.ok(rail != null, "shell hosts the tool rail")
	for name in NEW_TOOLS:
		var btn: Button = rail.find_child(name.capitalize(), true, false)
		t.ok(btn != null, "rail has a %s button" % name)
		t.ok(btn.icon != null, "%s button carries its glyph" % name)
	# The rail names its buttons after capitalize(), so a press has to come
	# back out as the lower-case tool id the sculpt kernels switch on.
	var erode: Button = rail.find_child("Erode", true, false)
	erode.button_pressed = true
	erode.pressed.emit()
	t.eq(ToolState.tool, "erode", "the rail reaches ToolState")
	t.eq(scene.get("_sculpt").mode, "erode", "and ToolState reaches the sculpt tool")

	# The mouse path itself: _on_lmb_down has to recognise each new kernel as
	# a stroke tool, or the rail switches the tool and nothing sculpts.
	var saved_field = MapState.field
	MapState.has_session = true
	for name in NEW_TOOLS:
		MapState.field = _slope(32, 32)
		var before: PackedInt32Array = MapState.field.heights.duplicate()
		ToolState.set_tool(name)
		UndoStack.clear()
		scene._on_lmb_down(Vector3(40.0, 20.0, 40.0), {"normal": Vector3.UP}, false)
		t.ok(bool(scene.get("_stroking")), "%s opens a stroke on mouse-down" % name)
		# _process marches the dabs; drive one directly so mouse-up has a
		# captured region to turn into an undo command.
		scene.get("_sculpt").stamp(MapState.field, 45.0, 45.0)
		scene._on_lmb_up()
		t.ok(not bool(scene.get("_stroking")), "%s closes it on mouse-up" % name)
		t.ok(MapState.field.heights != before, "%s changed the field" % name)
		t.ok(UndoStack.can_undo(), "%s landed on the undo stack" % name)
		UndoStack.undo()
		t.eq(MapState.field.heights, before, "%s undoes clean" % name)
	UndoStack.clear()
	# Ctrl+click anchors the set-angle plane instead of starting a stroke.
	ToolState.set_tool("setangle")
	ToolState.clear_angle_origin()
	scene._on_lmb_down(Vector3(55.0, 20.0, 65.0), {"normal": Vector3.UP}, false, false, true)
	t.ok(ToolState.has_angle_origin(), "Ctrl+click sets the angle origin")
	t.ok(not bool(scene.get("_stroking")), "and does not open a stroke")
	ToolState.clear_angle_origin()
	MapState.field = saved_field
	MapState.has_session = false

	var minimap: Node = scene.find_child("MinimapPanel", true, false)
	t.ok(minimap != null, "shell hosts the minimap dock")
	t.ok(minimap.get_signal_connection_list("fly_requested").size() > 0,
		"minimap click-to-fly is wired")
	t.ok(minimap.get("_camera") != null, "minimap draws the shell camera")
	t.ok(minimap.get("_range_source") != null, "minimap reads the terrain range map")

	var palette: Node = scene.find_child("CommandPalette", true, false)
	t.ok(palette is CommandPalette, "shell hosts the command palette")
	t.ok(palette.registry() != null and palette.registry().size() > 0,
		"the palette scanned the built-in commands")
	t.ok(palette.context.has_hook(CommandContext.HOOK_LOG))
	t.ok(palette.context.has_hook(CommandContext.HOOK_ACTION))
	t.ok(palette.context.has_hook(CommandContext.HOOK_VALIDATE))
	t.ok(palette.context.has_hook(CommandContext.HOOK_REFRESH_VIEW))
	t.ok(CommandPalette.is_open_chord(_key(KEY_P, true, true)), "Ctrl+Shift+P opens it")
	palette.open_palette()
	t.ok(palette.visible_ids().size() > 0, "the palette lists something")
	palette.hide()

	var help: Node = scene.find_child("HelpWindow", true, false)
	help.refresh()
	t.ok(not str(help.find_child("Body", true, false).get("text")).is_empty(),
		"F1 help still renders with the generated tool reference appended")

	scene.queue_free()
	await t.tree.process_frame
	Backend.test_worker = saved_worker
	MapState.has_session = saved_session
	ToolState.tool = saved_tool


func _key(code: int, ctrl := false, shift := false, alt := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl
	k.shift_pressed = shift
	k.alt_pressed = alt
	return k


func _stub(_verb: String, _args: PackedStringArray) -> Dictionary:
	return {"ok": true, "installs": [], "warnings": [], "worlds": [], "classes": []}


## A west-to-east ramp. Flat ground gives the morphological kernels nothing
## to shave or swell, so the "did it edit" assertion would pass vacuously.
func _slope(gx: int, gz: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	for z in gz:
		for x in gx:
			field.heights[z * gx + x] = 100 + x * 20
	return field
