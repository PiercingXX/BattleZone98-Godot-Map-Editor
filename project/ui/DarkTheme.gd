extends RefCounted
## Generic dark-gray editor chrome. Not a product brand.


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13

	var bg := Color(0.18, 0.18, 0.19, 1)
	var panel := Color(0.22, 0.22, 0.24, 1)
	var well := Color(0.14, 0.14, 0.15, 1)
	var hover := Color(0.28, 0.28, 0.30, 1)
	var select := Color(0.24, 0.42, 0.62, 1)
	var text := Color(0.88, 0.88, 0.90, 1)
	var dim := Color(0.62, 0.62, 0.64, 1)
	var edge := Color(0.08, 0.08, 0.09, 1)

	t.set_color("font_color", "Label", text)
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_constant("separation", "VBoxContainer", 6)

	t.set_stylebox("panel", "PanelContainer", _box(panel, edge, 8, 1))
	t.set_stylebox("panel", "Panel", _box(panel, edge, 8, 1))

	t.set_stylebox("normal", "Button", _box(Color(0.26, 0.26, 0.28, 1), edge, 8, 1))
	t.set_stylebox("hover", "Button", _box(hover, edge, 8, 1))
	t.set_stylebox("pressed", "Button", _box(select, edge, 8, 1))
	t.set_stylebox("focus", "Button", _box(Color(0.26, 0.26, 0.28, 1), select, 8, 1))
	t.set_stylebox("disabled", "Button", _box(bg, edge, 8, 1))
	t.set_color("font_color", "Button", text)
	t.set_color("font_hover_color", "Button", text)
	t.set_color("font_pressed_color", "Button", Color(0.95, 0.95, 0.97, 1))
	t.set_color("font_focus_color", "Button", text)
	t.set_color("font_disabled_color", "Button", dim)

	var field := _box(well, edge, 6, 1)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", _box(well, select, 6, 1))
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", text)
	t.set_color("font_placeholder_color", "LineEdit", dim)
	t.set_color("caret_color", "LineEdit", text)

	t.set_stylebox("normal", "TextEdit", field)
	t.set_stylebox("focus", "TextEdit", _box(well, select, 6, 1))
	t.set_stylebox("read_only", "TextEdit", field)
	t.set_color("font_color", "TextEdit", text)
	t.set_color("caret_color", "TextEdit", text)

	t.set_stylebox("panel", "ItemList", _box(well, edge, 4, 1))
	t.set_stylebox("focus", "ItemList", _box(well, edge, 4, 1))
	t.set_stylebox("hovered", "ItemList", _box(hover, Color(0, 0, 0, 0), 2, 0))
	t.set_stylebox("selected", "ItemList", _box(select, Color(0, 0, 0, 0), 2, 0))
	t.set_stylebox("selected_focus", "ItemList", _box(select, Color(0, 0, 0, 0), 2, 0))
	t.set_color("font_color", "ItemList", text)
	t.set_color("font_hovered_color", "ItemList", text)
	t.set_color("font_selected_color", "ItemList", Color(0.95, 0.95, 0.97, 1))

	t.set_stylebox("normal", "OptionButton", _box(Color(0.26, 0.26, 0.28, 1), edge, 6, 1))
	t.set_stylebox("hover", "OptionButton", _box(hover, edge, 6, 1))
	t.set_stylebox("pressed", "OptionButton", _box(select, edge, 6, 1))
	t.set_color("font_color", "OptionButton", text)
	t.set_color("font_hover_color", "OptionButton", text)
	t.set_color("font_pressed_color", "OptionButton", text)

	t.set_stylebox("slider", "HSlider", _box(well, edge, 2, 1))
	t.set_stylebox("grabber_area", "HSlider", _box(select, Color(0, 0, 0, 0), 2, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(Color(0.32, 0.52, 0.74, 1), Color(0, 0, 0, 0), 2, 0))

	t.set_color("font_color", "SpinBox", text)
	t.set_stylebox("normal", "SpinBox", field)

	t.set_stylebox("panel", "PopupMenu", _box(panel, edge, 4, 1))
	t.set_stylebox("hover", "PopupMenu", _box(select, Color(0, 0, 0, 0), 4, 0))
	t.set_color("font_color", "PopupMenu", text)
	t.set_color("font_hover_color", "PopupMenu", text)
	return t


static func _box(bg: Color, border: Color, pad: int, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = maxi(pad - 2, 4)
	s.content_margin_bottom = maxi(pad - 2, 4)
	return s
