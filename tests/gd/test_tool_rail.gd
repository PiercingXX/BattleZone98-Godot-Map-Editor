extends RefCounted
## ToolRail: GIMP-style left toolbox — buttons, signals, keymap tooltips.


func run(t) -> void:
	var saved_scheme: String = Settings.keymap_scheme
	var saved_tool: String = ToolState.tool
	Settings.keymap_scheme = "godot"

	var rail: Node = load("res://project/ui/tool_rail/ToolRail.tscn").instantiate()
	t.tree.root.add_child(rail)
	await t.tree.process_frame

	for id in [
		"Fly", "Raise", "Lower", "Flatten", "Smooth", "Ramp", "Noise",
		"Paint", "Clone", "Place", "Select", "Qsel", "Rsel", "Wand",
	]:
		var b := _btn(rail, id)
		t.ok(b != null, "rail has %s" % id)
		t.ok(b.icon != null, "%s has an icon" % id)
		t.eq(b.text, "", "%s is icon-only" % id)
		t.eq(str(b.theme_type_variation), "ToolButton")

	var tools: Array = []
	rail.tool_selected.connect(func(n): tools.append(n))
	_btn(rail, "Raise").pressed.emit()
	_btn(rail, "Place").pressed.emit()
	_btn(rail, "Noise").pressed.emit()
	_btn(rail, "Qsel").pressed.emit()
	_btn(rail, "Wand").pressed.emit()
	t.eq(tools, ["raise", "place", "noise", "qsel", "wand"], "buttons emit lower-case names")

	rail.set_tool("flatten")
	t.ok(_btn(rail, "Flatten").button_pressed, "set_tool flatten presses Flat")
	rail.set_tool("select")
	t.ok(_btn(rail, "Select").button_pressed, "set_tool select")
	rail.set_tool("rsel")
	t.ok(_btn(rail, "Rsel").button_pressed, "set_tool rsel")
	rail.set_tool("clone")
	t.ok(_btn(rail, "Clone").button_pressed, "set_tool clone")

	rail.refresh_keymap()
	t.eq(_btn(rail, "Raise").tooltip_text, "Raise  (2)", "godot scheme tooltip")
	Settings.keymap_scheme = "gimp"
	rail.refresh_keymap()
	t.eq(_btn(rail, "Raise").tooltip_text, "Raise  (W)", "tooltips follow the active scheme")

	rail.queue_free()
	await t.tree.process_frame
	Settings.keymap_scheme = saved_scheme
	ToolState.set_tool(saved_tool if saved_tool != "" else "fly")


func _btn(root: Node, name: String) -> Button:
	return root.find_child(name, true, false) as Button
