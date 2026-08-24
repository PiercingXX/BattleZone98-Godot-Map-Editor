extends RefCounted
## DockLayout: snapshot / apply / retitle for the draggable right docks.


func run(t) -> void:
	var a := TabContainer.new()
	var b := TabContainer.new()
	t.tree.root.add_child(a)
	t.tree.root.add_child(b)
	var hist := _panel("HistoryPanel")
	var find_p := _panel("FindingsPanel")
	var pal := _panel("PalettePanel")
	a.add_child(hist)
	a.add_child(find_p)
	b.add_child(pal)
	await t.tree.process_frame

	var docks := {"Dock1": a, "Dock2": b}
	var snap := DockLayout.snapshot(docks)
	t.eq(snap["Dock1"]["tabs"], ["HistoryPanel", "FindingsPanel"], "snapshot records tab order")
	t.eq(snap["Dock2"]["tabs"], ["PalettePanel"])

	# Simulate a GIMP-style drag: Findings moves to the other dock, in
	# front of Palette, and the arrangement is restored from the data.
	var moved := {
		"Dock1": {"tabs": ["HistoryPanel"], "current": 0},
		"Dock2": {"tabs": ["FindingsPanel", "PalettePanel"], "current": 1},
	}
	DockLayout.apply(docks, moved)
	await t.tree.process_frame
	t.eq(a.get_tab_count(), 1, "dock1 kept one panel")
	t.eq(str(a.get_tab_control(0).name), "HistoryPanel")
	t.eq(b.get_tab_count(), 2, "dock2 gained the dragged panel")
	t.eq(str(b.get_tab_control(0).name), "FindingsPanel", "dragged panel lands in order")
	t.eq(b.current_tab, 1, "current tab restored")

	DockLayout.retitle(docks)
	t.eq(a.get_tab_title(0), "History", "titles come from the panel map")
	t.eq(b.get_tab_title(0), "Findings")
	t.eq(b.get_tab_title(1), "Tool")

	# Unknown panels and docks are ignored, not crashed on.
	DockLayout.apply(docks, {"DockX": {"tabs": ["Nope"]}, "Dock1": {"tabs": ["Ghost"]}})
	t.eq(a.get_tab_count(), 1, "unknown names leave the layout alone")

	a.queue_free()
	b.queue_free()
	await t.tree.process_frame


func _panel(name: String) -> Control:
	var c := PanelContainer.new()
	c.name = name
	return c
