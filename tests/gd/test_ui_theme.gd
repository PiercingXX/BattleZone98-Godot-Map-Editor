extends RefCounted
## DarkTheme token table and StyleBox construction.


func run(t) -> void:
	var tok: Dictionary = DarkTheme.tokens()
	for key in [
		"bg", "bg_mid", "panel", "accent", "accent_hover",
		"text", "text_dim", "danger", "radii", "spacing",
	]:
		t.ok(tok.has(key), "token %s present" % key)
	t.ok(tok["bg"] is Color)
	t.ok(tok["bg_mid"] is Color)
	t.ok(tok["panel"] is Color)
	t.ok(tok["accent"] is Color)
	t.ok(tok["accent_hover"] is Color)
	t.ok(tok["text"] is Color)
	t.ok(tok["text_dim"] is Color)
	t.ok(tok["danger"] is Color)
	t.ok(tok["radii"] is Dictionary)
	t.ok(tok["spacing"] is Dictionary)
	t.eq(int(tok["radii"]["sm"]), 4, "radius sm is 4")
	t.eq(int(tok["radii"]["md"]), 8, "radius md is 8")
	t.eq(int(tok["spacing"]["sm"]), 4, "spacing sm is 4")
	t.eq(int(tok["spacing"]["md"]), 8, "spacing md is 8")
	t.ok(tok["accent"] != tok["accent_hover"], "accent-hover is distinct")
	t.ok(tok["text"] != tok["text_dim"], "text-dim is distinct")
	t.ok(tok["bg"] != tok["panel"], "bg layers are distinct")
	t.eq(DarkTheme.token("accent"), tok["accent"])

	var theme := DarkTheme.make()
	t.ok(theme is Theme)
	t.eq(theme.get_constant("separation", "HBoxContainer"), 8)
	t.eq(theme.get_constant("separation", "VBoxContainer"), 8)
	t.eq(theme.get_constant("margin_left", "MarginContainer"), 8)

	_assert_button_states(t, theme, "Button")
	_assert_button_states(t, theme, "OptionButton")
	_assert_button_states(t, theme, "CheckBox")
	_assert_button_states(t, theme, "ToolButton")

	var tool_pressed := theme.get_stylebox("pressed", "ToolButton") as StyleBoxFlat
	t.ok(tool_pressed != null, "ToolButton pressed style exists")
	t.eq(tool_pressed.bg_color, tok["accent"], "active tool is accent fill")

	var btn_hover := theme.get_stylebox("hover", "Button") as StyleBoxFlat
	var btn_normal := theme.get_stylebox("normal", "Button") as StyleBoxFlat
	t.ok(btn_hover.bg_color != btn_normal.bg_color, "Button hover differs from normal")

	var focus := theme.get_stylebox("focus", "Button") as StyleBoxFlat
	t.ok(focus != null)
	t.ok(not focus.draw_center, "Button focus is a ring")
	t.eq(focus.border_width_left, 2, "focus ring is 2 px")
	t.eq(focus.border_color, tok["accent"])

	var le_focus := theme.get_stylebox("focus", "LineEdit") as StyleBoxFlat
	t.ok(le_focus != null)
	t.eq(le_focus.border_color, tok["accent"])
	t.ok(le_focus.border_width_left >= 2, "LineEdit focus ring visible")

	var grab := theme.get_stylebox("grabber_area", "HSlider") as StyleBoxFlat
	t.ok(grab != null)
	t.eq(grab.bg_color, tok["accent"])
	var grab_hi := theme.get_stylebox("grabber_area_highlight", "HSlider") as StyleBoxFlat
	t.eq(grab_hi.bg_color, tok["accent_hover"])

	t.ok(theme.get_stylebox("hovered", "ItemList") is StyleBoxFlat)
	t.ok(theme.get_stylebox("selected", "ItemList") is StyleBoxFlat)
	var list_focus := theme.get_stylebox("focus", "ItemList") as StyleBoxFlat
	t.ok(list_focus.border_width_left >= 2)

	t.ok(theme.get_stylebox("hovered", "Tree") is StyleBoxFlat)
	t.ok(theme.get_stylebox("selected", "Tree") is StyleBoxFlat)
	var tree_focus := theme.get_stylebox("focus", "Tree") as StyleBoxFlat
	t.ok(tree_focus.border_width_left >= 2)
	var tree_sel := theme.get_stylebox("selected", "Tree") as StyleBoxFlat
	t.eq(tree_sel.bg_color, tok["accent"])

	var panel := theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	t.eq(panel.corner_radius_top_left, 8)


func _assert_button_states(t, theme: Theme, cls: String) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.ok(theme.get_stylebox(state, cls) is StyleBoxFlat, "%s has %s StyleBox" % [cls, state])
