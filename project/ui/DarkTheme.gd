extends RefCounted
class_name DarkTheme
## Token-driven dark editor chrome. StyleBoxes are built only from TOKENS.

const TOKENS := {
	"bg": Color(0.12, 0.12, 0.13, 1),
	"bg_mid": Color(0.16, 0.16, 0.17, 1),
	"panel": Color(0.20, 0.20, 0.22, 1),
	"accent": Color(0.22, 0.52, 0.78, 1),
	"accent_hover": Color(0.30, 0.60, 0.88, 1),
	"text": Color(0.90, 0.90, 0.92, 1),
	"text_dim": Color(0.62, 0.62, 0.64, 1),
	"danger": Color(0.82, 0.28, 0.26, 1),
	"radii": {"sm": 4, "md": 8},
	"spacing": {"sm": 4, "md": 8},
}


static func tokens() -> Dictionary:
	return TOKENS.duplicate(true)


static func token(key: String) -> Variant:
	return TOKENS.get(key)


static func make() -> Theme:
	var t := Theme.new()
	var bg: Color = TOKENS["bg"]
	var bg_mid: Color = TOKENS["bg_mid"]
	var panel: Color = TOKENS["panel"]
	var accent: Color = TOKENS["accent"]
	var accent_hover: Color = TOKENS["accent_hover"]
	var text: Color = TOKENS["text"]
	var dim: Color = TOKENS["text_dim"]
	var danger: Color = TOKENS["danger"]
	var radii: Dictionary = TOKENS["radii"]
	var spacing: Dictionary = TOKENS["spacing"]
	var r_sm: int = int(radii["sm"])
	var r_md: int = int(radii["md"])
	var s_sm: int = int(spacing["sm"])
	var s_md: int = int(spacing["md"])
	var edge := bg.darkened(0.28)
	var raised := panel.lightened(0.08)
	var hover := panel.lightened(0.16)
	var well := bg
	var quiet_press := accent.darkened(0.28)
	var text_on_accent := Color(0.97, 0.97, 0.99, 1)

	t.default_font_size = 13
	t.set_color("font_color", "Label", text)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("separation", "HBoxContainer", s_md)
	t.set_constant("separation", "VBoxContainer", s_md)
	t.set_constant("h_separation", "GridContainer", s_sm)
	t.set_constant("v_separation", "GridContainer", s_sm)

	t.set_stylebox("panel", "PanelContainer", _fill(panel, edge, s_md, 1, r_md))
	t.set_stylebox("panel", "Panel", _fill(panel, edge, s_md, 1, r_md))
	t.set_constant("margin_left", "MarginContainer", s_md)
	t.set_constant("margin_right", "MarginContainer", s_md)
	t.set_constant("margin_top", "MarginContainer", s_md)
	t.set_constant("margin_bottom", "MarginContainer", s_md)

	_apply_button_set(
		t, "Button",
		_fill(raised, edge, s_md, 1, r_sm),
		_fill(hover, edge, s_md, 1, r_sm),
		_fill(quiet_press, edge, s_md, 1, r_sm),
		_fill(hover.lightened(0.04), accent, s_md, 1, r_sm),
		_fill(bg_mid, edge, s_md, 1, r_sm),
		_ring(accent, r_sm),
		text, text, text_on_accent, dim, s_sm
	)

	t.set_type_variation("ToolButton", "Button")
	_apply_button_set(
		t, "ToolButton",
		_fill(raised, edge, s_sm, 1, r_sm),
		_fill(hover, edge, s_sm, 1, r_sm),
		_fill(accent, accent.darkened(0.2), s_sm, 1, r_sm),
		_fill(accent_hover, accent_hover.darkened(0.15), s_sm, 1, r_sm),
		_fill(bg_mid, edge, s_sm, 1, r_sm),
		_ring(accent_hover, r_sm),
		text, text, text_on_accent, dim, s_sm
	)

	t.set_type_variation("DangerButton", "Button")
	_apply_button_set(
		t, "DangerButton",
		_fill(danger.darkened(0.25), edge, s_md, 1, r_sm),
		_fill(danger, edge, s_md, 1, r_sm),
		_fill(danger.lightened(0.08), edge, s_md, 1, r_sm),
		_fill(danger, accent, s_md, 1, r_sm),
		_fill(bg_mid, edge, s_md, 1, r_sm),
		_ring(accent, r_sm),
		text, text, text_on_accent, dim, s_sm
	)

	_apply_button_set(
		t, "OptionButton",
		_fill(raised, edge, s_md, 1, r_sm),
		_fill(hover, edge, s_md, 1, r_sm),
		_fill(quiet_press, edge, s_md, 1, r_sm),
		_fill(hover, accent, s_md, 1, r_sm),
		_fill(bg_mid, edge, s_md, 1, r_sm),
		_ring(accent, r_sm),
		text, text, text_on_accent, dim, s_sm
	)
	t.set_color("font_hover_pressed_color", "OptionButton", text_on_accent)

	var field := _fill(well, edge, s_sm + 2, 1, r_sm)
	var field_focus := _fill(well, accent, s_sm + 2, 2, r_sm)
	var field_ro := _fill(bg_mid, edge, s_sm + 2, 1, r_sm)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field_ro)
	t.set_color("font_color", "LineEdit", text)
	t.set_color("font_uneditable_color", "LineEdit", dim)
	t.set_color("font_placeholder_color", "LineEdit", dim)
	t.set_color("font_selected_color", "LineEdit", text_on_accent)
	t.set_color("caret_color", "LineEdit", text)
	t.set_color("selection_color", "LineEdit", accent)

	t.set_stylebox("normal", "TextEdit", field)
	t.set_stylebox("focus", "TextEdit", field_focus)
	t.set_stylebox("read_only", "TextEdit", field_ro)
	t.set_color("font_color", "TextEdit", text)
	t.set_color("font_placeholder_color", "TextEdit", dim)
	t.set_color("font_readonly_color", "TextEdit", dim)
	t.set_color("caret_color", "TextEdit", text)
	t.set_color("selection_color", "TextEdit", accent)

	_apply_button_set(
		t, "CheckBox",
		_fill(Color(0, 0, 0, 0), Color(0, 0, 0, 0), s_sm, 0, r_sm),
		_fill(hover, Color(0, 0, 0, 0), s_sm, 0, r_sm),
		_fill(quiet_press, Color(0, 0, 0, 0), s_sm, 0, r_sm),
		_fill(hover, Color(0, 0, 0, 0), s_sm, 0, r_sm),
		_fill(Color(0, 0, 0, 0), Color(0, 0, 0, 0), s_sm, 0, r_sm),
		_ring(accent, r_sm),
		text, text, text, dim, s_sm
	)
	t.set_constant("h_separation", "CheckBox", s_sm)

	var list_panel := _fill(well, edge, s_sm, 1, r_sm)
	var list_hover := _fill(hover, Color(0, 0, 0, 0), s_sm, 0, r_sm)
	var list_sel := _fill(accent, Color(0, 0, 0, 0), s_sm, 0, r_sm)
	t.set_stylebox("panel", "ItemList", list_panel)
	t.set_stylebox("focus", "ItemList", _fill(well, accent, s_sm, 2, r_sm))
	t.set_stylebox("hovered", "ItemList", list_hover)
	t.set_stylebox("hovered_selected", "ItemList", _fill(accent_hover, Color(0, 0, 0, 0), s_sm, 0, r_sm))
	t.set_stylebox("selected", "ItemList", list_sel)
	t.set_stylebox("selected_focus", "ItemList", list_sel)
	t.set_stylebox("cursor", "ItemList", _ring(accent, r_sm))
	t.set_color("font_color", "ItemList", text)
	t.set_color("font_hovered_color", "ItemList", text)
	t.set_color("font_selected_color", "ItemList", text_on_accent)
	t.set_constant("h_separation", "ItemList", s_sm)
	t.set_constant("v_separation", "ItemList", s_sm)

	t.set_stylebox("panel", "Tree", list_panel)
	t.set_stylebox("focus", "Tree", _fill(well, accent, s_sm, 2, r_sm))
	t.set_stylebox("hovered", "Tree", list_hover)
	t.set_stylebox("hovered_dimmed", "Tree", _fill(hover.darkened(0.08), Color(0, 0, 0, 0), s_sm, 0, r_sm))
	t.set_stylebox("selected", "Tree", list_sel)
	t.set_stylebox("selected_focus", "Tree", list_sel)
	t.set_stylebox("cursor", "Tree", _ring(accent, r_sm))
	t.set_stylebox("cursor_unfocused", "Tree", _ring(accent.darkened(0.2), r_sm))
	t.set_stylebox("button_pressed", "Tree", _fill(quiet_press, edge, s_sm, 1, r_sm))
	t.set_stylebox("title_button_normal", "Tree", _fill(raised, edge, s_sm, 1, r_sm))
	t.set_stylebox("title_button_hover", "Tree", _fill(hover, edge, s_sm, 1, r_sm))
	t.set_stylebox("title_button_pressed", "Tree", _fill(accent, edge, s_sm, 1, r_sm))
	t.set_color("font_color", "Tree", text)
	t.set_color("font_hovered_color", "Tree", text)
	t.set_color("font_selected_color", "Tree", text_on_accent)
	t.set_color("guide_color", "Tree", edge)
	t.set_constant("h_separation", "Tree", s_sm)
	t.set_constant("v_separation", "Tree", s_sm)
	t.set_constant("item_margin", "Tree", s_md)

	var track := _fill(well, edge, 2, 1, r_sm)
	var grab := _fill(accent, Color(0, 0, 0, 0), 2, 0, r_sm)
	var grab_hi := _fill(accent_hover, Color(0, 0, 0, 0), 2, 0, r_sm)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab_hi)
	t.set_stylebox("slider", "VSlider", track)
	t.set_stylebox("grabber_area", "VSlider", grab)
	t.set_stylebox("grabber_area_highlight", "VSlider", grab_hi)

	t.set_color("font_color", "SpinBox", text)
	t.set_stylebox("normal", "SpinBox", field)
	t.set_stylebox("up_background", "SpinBox", _fill(raised, edge, s_sm, 1, r_sm))
	t.set_stylebox("up_background_hovered", "SpinBox", _fill(hover, edge, s_sm, 1, r_sm))
	t.set_stylebox("up_background_pressed", "SpinBox", _fill(quiet_press, edge, s_sm, 1, r_sm))
	t.set_stylebox("up_background_disabled", "SpinBox", _fill(bg_mid, edge, s_sm, 1, r_sm))
	t.set_stylebox("down_background", "SpinBox", _fill(raised, edge, s_sm, 1, r_sm))
	t.set_stylebox("down_background_hovered", "SpinBox", _fill(hover, edge, s_sm, 1, r_sm))
	t.set_stylebox("down_background_pressed", "SpinBox", _fill(quiet_press, edge, s_sm, 1, r_sm))
	t.set_stylebox("down_background_disabled", "SpinBox", _fill(bg_mid, edge, s_sm, 1, r_sm))

	t.set_stylebox("panel", "PopupMenu", _fill(panel, edge, s_sm, 1, r_sm))
	t.set_stylebox("hover", "PopupMenu", _fill(accent, Color(0, 0, 0, 0), s_sm, 0, r_sm))
	t.set_stylebox("labeled_separator_left", "PopupMenu", _fill(edge, Color(0, 0, 0, 0), 0, 0, 0))
	t.set_stylebox("labeled_separator_right", "PopupMenu", _fill(edge, Color(0, 0, 0, 0), 0, 0, 0))
	t.set_color("font_color", "PopupMenu", text)
	t.set_color("font_hover_color", "PopupMenu", text_on_accent)
	t.set_color("font_accelerator_color", "PopupMenu", dim)
	t.set_color("font_disabled_color", "PopupMenu", dim)
	t.set_color("font_separator_color", "PopupMenu", dim)
	t.set_constant("v_separation", "PopupMenu", s_sm)
	t.set_constant("h_separation", "PopupMenu", s_sm)

	t.set_stylebox("panel", "TooltipPanel", _fill(bg_mid, accent.darkened(0.2), s_sm, 1, r_sm))
	t.set_color("font_color", "TooltipLabel", text)

	t.set_stylebox("panel", "AcceptDialog", _fill(panel, edge, s_md, 1, r_md))
	t.set_color("title_color", "Window", text)

	# Keep unused tokens referenced so the table is the single source of truth.
	t.set_color("font_outline_color", "Label", danger)
	t.set_constant("outline_size", "Label", 0)
	return t


static func _apply_button_set(
	t: Theme,
	cls: String,
	normal: StyleBox,
	hover: StyleBox,
	pressed: StyleBox,
	hover_pressed: StyleBox,
	disabled: StyleBox,
	focus: StyleBox,
	font_n: Color,
	font_h: Color,
	font_p: Color,
	font_d: Color,
	icon_sep: int
) -> void:
	t.set_stylebox("normal", cls, normal)
	t.set_stylebox("hover", cls, hover)
	t.set_stylebox("pressed", cls, pressed)
	t.set_stylebox("hover_pressed", cls, hover_pressed)
	t.set_stylebox("disabled", cls, disabled)
	t.set_stylebox("focus", cls, focus)
	t.set_color("font_color", cls, font_n)
	t.set_color("font_hover_color", cls, font_h)
	t.set_color("font_pressed_color", cls, font_p)
	t.set_color("font_hover_pressed_color", cls, font_p)
	t.set_color("font_focus_color", cls, font_h)
	t.set_color("font_disabled_color", cls, font_d)
	t.set_color("icon_normal_color", cls, font_n)
	t.set_color("icon_hover_color", cls, font_h)
	t.set_color("icon_pressed_color", cls, font_p)
	t.set_color("icon_hover_pressed_color", cls, font_p)
	t.set_color("icon_focus_color", cls, font_h)
	t.set_color("icon_disabled_color", cls, font_d)
	t.set_constant("h_separation", cls, icon_sep)
	t.set_constant("icon_max_width", cls, 16)


static func _fill(bg: Color, border: Color, pad: int, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = maxi(pad - 4, 4) if pad >= 6 else maxi(pad, 4)
	s.content_margin_bottom = maxi(pad - 4, 4) if pad >= 6 else maxi(pad, 4)
	return s


static func _ring(accent: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = accent
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.set_expand_margin_all(2)
	return s
