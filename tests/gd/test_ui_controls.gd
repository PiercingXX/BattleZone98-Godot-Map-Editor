extends RefCounted
## Reusable controls the panels keep re-implementing: spinbox+slider, a
## two-handle band, a section header. All must construct headless and take
## their colours from the theme chain, never from a literal.


func run(t) -> void:
	await _spin_slider(t)
	_range_slider(t)
	_section_header(t)
	_theme_probe(t)


func _spin_slider(t) -> void:
	# Range.value_changed only fires for a node inside the tree in Godot 4.7,
	# so the sync path is tested attached, the way a panel runs it.
	var ctl := SpinSlider.make(5.0, 200.0, 1.0, 40.0, "m")
	t.tree.root.add_child(ctl)
	await t.tree.process_frame
	t.near(ctl.get_value(), 40.0, 0.001, "starts where it was told")
	t.near(ctl.slider().value, 40.0, 0.001, "slider agrees")
	t.eq(ctl.spin_box().suffix, "m")
	t.ok(ctl.slider().visible, "a bounded field shows its slider")

	var seen: Array = []
	ctl.value_changed.connect(func(v: float) -> void: seen.append(v))
	ctl.spin_box().value = 90.0
	t.eq(seen.size(), 1, "editing the spinbox reports once")
	t.near(seen[0], 90.0, 0.001)
	t.near(ctl.slider().value, 90.0, 0.001, "and moves the slider")

	seen.clear()
	ctl.slider().value = 120.0
	t.eq(seen.size(), 1, "editing the slider reports once")
	t.near(ctl.spin_box().value, 120.0, 0.001, "and moves the spinbox")

	seen.clear()
	ctl.set_value_silent(60.0)
	t.eq(seen.size(), 0, "a scripted write is silent")
	t.near(ctl.value, 60.0, 0.001, "value reads back through the property")
	ctl.value = 61.0
	t.near(ctl.spin_box().value, 61.0, 0.001, "assigning value writes through")
	t.eq(seen.size(), 0)

	ctl.set_value_silent(9999.0)
	t.near(ctl.get_value(), 200.0, 0.001, "clamped to max")
	ctl.set_value_silent(-5.0)
	t.near(ctl.get_value(), 5.0, 0.001, "clamped to min")
	ctl.queue_free()

	var ints := SpinSlider.make(0.0, 10.0, 1.0, 0.0, "", true)
	ints.set_value_silent(3.6)
	t.near(ints.get_value(), 4.0, 0.001, "a rounded field holds integers")
	ints.free()

	var free_form := SpinSlider.make_unbounded(1.0, 12345.0)
	t.ok(not free_form.slider().visible,
		"an unbounded field hides a slider it cannot honestly draw")
	t.near(free_form.get_value(), 12345.0, 0.001)
	free_form.free()


func _range_slider(t) -> void:
	var band := RangeSlider.make(0.0, 90.0, 1.0, 12.0, 34.0)
	t.eq(band.band(), Vector2(12.0, 34.0))
	band.set_band(50.0, 20.0)
	t.eq(band.band(), Vector2(20.0, 50.0), "handles are always sorted")
	band.set_band(-30.0, 500.0)
	t.eq(band.band(), Vector2(0.0, 90.0), "clamped into the range")
	band.set_band(12.4, 33.6)
	t.eq(band.band(), Vector2(12.0, 34.0), "snapped to the step")
	t.near(band.ratio_of(45.0), 0.5, 0.001)
	t.near(band.value_at_ratio(0.0), 0.0, 0.001)
	t.near(band.value_at_ratio(1.0), 90.0, 0.001)
	t.near(band.ratio_of(-100.0), 0.0, 0.001, "ratio never leaves 0..1")

	var seen: Array = []
	band.range_changed.connect(
		func(lo: float, hi: float) -> void: seen.append(Vector2(lo, hi))
	)
	band.set_band(10.0, 20.0)
	t.eq(seen.size(), 0, "a scripted write is silent")
	band.set_band_notify(30.0, 10.0)
	t.eq(seen.size(), 1, "the notifying write reports once")
	t.eq(seen[0], Vector2(10.0, 30.0), "and reports sorted")
	seen.clear()
	band.set_band_notify(10.0, 30.0)
	t.eq(seen.size(), 0, "an unchanged band stays quiet")

	# Drive it like a mouse. Detached from any tree: the control must not
	# reach for a viewport it does not have.
	band.configure(0.0, 100.0, 1.0)
	band.size = Vector2(200.0, 20.0)
	band.set_band(0.0, 100.0)
	seen.clear()
	band._gui_input(_press(Vector2(100.0, 10.0)))
	t.eq(seen.size(), 1, "a click drags the nearest handle")
	t.near(band.low_value, 50.0, 1.0, "clicking mid-track moves the low handle")
	t.near(band.high_value, 100.0, 0.001, "the far handle stays put")
	band._gui_input(_motion(Vector2(194.0, 10.0)))
	t.near(band.low_value, band.high_value, 0.001,
		"handles may meet but never cross")
	t.ok(band.low_value <= band.high_value)
	var ended: Array = []
	band.drag_ended.connect(
		func(lo: float, hi: float) -> void: ended.append(Vector2(lo, hi))
	)
	band._gui_input(_release(Vector2(194.0, 10.0)))
	t.eq(ended.size(), 1, "release closes the gesture once")
	band._gui_input(_motion(Vector2(6.0, 10.0)))
	t.near(band.low_value, band.high_value, 0.001,
		"motion after release is ignored")
	t.ok(band._get_minimum_size().y >= 14.0, "the band has a clickable height")
	band.free()


func _section_header(t) -> void:
	var head := SectionHeader.make("Brush")
	t.eq(head.caption, "Brush")
	t.ok(head.get_node("Caption") is Label)
	t.eq(head.get_node("Caption").text, "Brush")
	t.ok(head.get_node("Rule") is Panel, "a hairline rule fills the row")
	t.ok(head.get_node_or_null("Toggle") == null,
		"plain headers do not collapse")
	head.caption = "Terrain selection"
	t.eq(head.get_node("Caption").text, "Terrain selection",
		"the caption is live")
	head.free()

	var fold := SectionHeader.make("Features", true)
	t.ok(fold.get_node_or_null("Toggle") is Button)
	t.ok(fold.is_open())
	var seen: Array = []
	fold.toggled_open.connect(func(on: bool) -> void: seen.append(on))
	fold.get_node("Toggle").pressed.emit()
	t.eq(seen.size(), 1)
	t.eq(seen[0], false)
	t.ok(not fold.is_open())
	fold.set_open(false)
	t.eq(seen.size(), 1, "setting the state it already has is quiet")
	fold.set_open(true)
	t.eq(seen.size(), 2)
	t.eq(seen[1], true)
	fold.free()


func _theme_probe(t) -> void:
	var probe := Label.new()
	var fallback := Color(0.1, 0.2, 0.3, 1)
	t.eq(ThemeProbe.color(probe, "no_such_color", "Label", fallback), fallback,
		"an absent colour falls back")
	t.eq(ThemeProbe.constant(probe, "no_such_constant", "Label", 7), 7)
	t.eq(ThemeProbe.constant(probe, "sep", "NoSuchType", 3), 3)
	# Godot answers every font_size query from the default theme, so the
	# fallback is a guard, not the usual path; assert the lookup, not the miss.
	t.ok(ThemeProbe.font_size(probe, "font_size", "Label", 11) > 0,
		"a font size present in the chain is used")
	t.ok(ThemeProbe.stylebox(probe, "no_such_box", "Label") == null)
	t.eq(ThemeProbe.color(null, "font_color", "Label", fallback), fallback,
		"a detached probe still answers")

	var theme := Theme.new()
	theme.set_color("accent", "Editor", Color(1, 0, 0, 1))
	probe.theme = theme
	t.eq(ThemeProbe.accent(probe), Color(1, 0, 0, 1),
		"a theme that names an accent wins")
	var bare := Label.new()
	t.ok(ThemeProbe.accent(bare) is Color, "and one that does not still reads")
	t.ok(ThemeProbe.dim_text(bare) != ThemeProbe.text(bare),
		"dim text is distinct from body text")
	probe.free()
	bare.free()


func _press(at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	return ev


func _release(at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = at
	return ev


func _motion(at: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	return ev
