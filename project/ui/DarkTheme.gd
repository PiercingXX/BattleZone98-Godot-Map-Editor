extends RefCounted
class_name DarkTheme
## Token-driven dark editor chrome.
##
## TOKENS is the only source of truth. Everything below is derived from it:
## palette() mixes the shades, styleboxes() builds one named StyleBox library,
## and make() assembles a Theme resource out of that library. No .tres is
## hand-authored anywhere, so no .tres can drift from the tokens.
##
## The whole library is also registered under the STYLE_TYPE theme type, so a
## control that needs one box by name can borrow it instead of newing its own
## StyleBoxFlat and re-deriving the shades by eye.

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

## Theme type the named StyleBox library is registered under.
const STYLE_TYPE := "EditorStyles"


static func tokens() -> Dictionary:
	return TOKENS.duplicate(true)


static func token(key: String) -> Variant:
	return TOKENS.get(key)


## Base text size in points. Independent of Settings.ui_scale: scale grows the
## whole chrome, this grows only the type, which is what a reader needs.
static func font_size() -> int:
	return Settings.coerce_ui_font_size(Settings.ui_font_size)


## Token colours plus the shades mixed from them. Nothing else may mix.
static func palette() -> Dictionary:
	var bg: Color = TOKENS["bg"]
	var panel: Color = TOKENS["panel"]
	var accent: Color = TOKENS["accent"]
	return {
		"bg": bg,
		"bg_mid": TOKENS["bg_mid"],
		"panel": panel,
		"accent": accent,
		"accent_hover": TOKENS["accent_hover"],
		"text": TOKENS["text"],
		"text_dim": TOKENS["text_dim"],
		"danger": TOKENS["danger"],
		"edge": bg.darkened(0.28),
		"raised": panel.lightened(0.08),
		"hover": panel.lightened(0.16),
		"well": bg,
		"quiet_press": accent.darkened(0.28),
		"text_on_accent": Color(0.97, 0.97, 0.99, 1),
		"clear": Color(0, 0, 0, 0),
	}


## name → StyleBox. The complete visual vocabulary of the editor.
static func styleboxes() -> Dictionary:
	var p := palette()
	var radii: Dictionary = TOKENS["radii"]
	var spacing: Dictionary = TOKENS["spacing"]
	var r_sm: int = int(radii["sm"])
	var r_md: int = int(radii["md"])
	var s_sm: int = int(spacing["sm"])
	var s_md: int = int(spacing["md"])
	var edge: Color = p["edge"]
	var raised: Color = p["raised"]
	var hover: Color = p["hover"]
	var accent: Color = p["accent"]
	var accent_hover: Color = p["accent_hover"]
	var danger: Color = p["danger"]
	var clear: Color = p["clear"]
	var press: Color = p["quiet_press"]
	var well: Color = p["well"]
	var bg_mid: Color = p["bg_mid"]
	return {
		"panel": _fill(p["panel"], edge, s_md, 1, r_md),
		"well": _fill(well, edge, s_sm, 1, r_sm),
		"empty": _fill(clear, clear, s_sm, 0, r_sm),

		"button_normal": _fill(raised, edge, s_md, 1, r_sm),
		"button_hover": _fill(hover, edge, s_md, 1, r_sm),
		"button_pressed": _fill(press, edge, s_md, 1, r_sm),
		"button_hover_pressed": _fill(hover.lightened(0.04), accent, s_md, 1, r_sm),
		"button_disabled": _fill(bg_mid, edge, s_md, 1, r_sm),
		"option_hover_pressed": _fill(hover, accent, s_md, 1, r_sm),

		"tool_normal": _fill(raised, edge, s_sm, 1, r_sm),
		"tool_hover": _fill(hover, edge, s_sm, 1, r_sm),
		"tool_pressed": _fill(accent, accent.darkened(0.2), s_sm, 1, r_sm),
		"tool_hover_pressed": _fill(
			accent_hover, accent_hover.darkened(0.15), s_sm, 1, r_sm
		),
		"tool_disabled": _fill(bg_mid, edge, s_sm, 1, r_sm),

		"danger_normal": _fill(danger.darkened(0.25), edge, s_md, 1, r_sm),
		"danger_hover": _fill(danger, edge, s_md, 1, r_sm),
		"danger_pressed": _fill(danger.lightened(0.08), edge, s_md, 1, r_sm),
		"danger_hover_pressed": _fill(danger, accent, s_md, 1, r_sm),
		"danger_disabled": _fill(bg_mid, edge, s_md, 1, r_sm),

		"check_hover": _fill(hover, clear, s_sm, 0, r_sm),
		"check_pressed": _fill(press, clear, s_sm, 0, r_sm),

		"field_normal": _fill(well, edge, s_sm + 2, 1, r_sm),
		"field_focus": _fill(well, accent, s_sm + 2, 2, r_sm),
		"field_readonly": _fill(bg_mid, edge, s_sm + 2, 1, r_sm),

		"list_hover": _fill(hover, clear, s_sm, 0, r_sm),
		"list_hover_selected": _fill(accent_hover, clear, s_sm, 0, r_sm),
		"list_selected": _fill(accent, clear, s_sm, 0, r_sm),
		"list_dimmed": _fill(hover.darkened(0.08), clear, s_sm, 0, r_sm),
		"list_focus": _fill(well, accent, s_sm, 2, r_sm),

		"step_normal": _fill(raised, edge, s_sm, 1, r_sm),
		"step_hover": _fill(hover, edge, s_sm, 1, r_sm),
		"step_pressed": _fill(press, edge, s_sm, 1, r_sm),
		"step_disabled": _fill(bg_mid, edge, s_sm, 1, r_sm),
		"title_pressed": _fill(accent, edge, s_sm, 1, r_sm),

		"slider_track": _fill(well, edge, 2, 1, r_sm),
		"slider_grabber": _fill(accent, clear, 2, 0, r_sm),
		"slider_grabber_highlight": _fill(accent_hover, clear, 2, 0, r_sm),

		"popup_panel": _fill(p["panel"], edge, s_sm, 1, r_sm),
		"popup_hover": _fill(accent, clear, s_sm, 0, r_sm),
		"separator": _fill(edge, clear, 0, 0, 0),
		"tooltip_panel": _fill(bg_mid, accent.darkened(0.2), s_sm, 1, r_sm),

		"focus_ring": _ring(accent, r_sm),
		"focus_ring_tool": _ring(accent_hover, r_sm),
		"focus_ring_quiet": _ring(accent.darkened(0.2), r_sm),
	}


static func stylebox_names() -> PackedStringArray:
	var out := PackedStringArray()
	for name in styleboxes().keys():
		out.append(str(name))
	out.sort()
	return out


static func stylebox(name: String) -> StyleBox:
	return styleboxes().get(name, null)


## Assemble the Theme resource. font_size_override <= 0 reads Settings.
static func make(font_size_override: int = 0) -> Theme:
	var t := Theme.new()
	var p := palette()
	var sb := styleboxes()
	var spacing: Dictionary = TOKENS["spacing"]
	var s_sm: int = int(spacing["sm"])
	var s_md: int = int(spacing["md"])
	var text: Color = p["text"]
	var dim: Color = p["text_dim"]
	var accent: Color = p["accent"]
	var text_on_accent: Color = p["text_on_accent"]

	t.default_font_size = font_size_override if font_size_override > 0 else font_size()
	_register_library(t, sb)

	t.set_color("font_color", "Label", text)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("separation", "HBoxContainer", s_md)
	t.set_constant("separation", "VBoxContainer", s_md)
	t.set_constant("h_separation", "GridContainer", s_sm)
	t.set_constant("v_separation", "GridContainer", s_sm)

	t.set_stylebox("panel", "PanelContainer", sb["panel"])
	t.set_stylebox("panel", "Panel", sb["panel"])
	t.set_constant("margin_left", "MarginContainer", s_md)
	t.set_constant("margin_right", "MarginContainer", s_md)
	t.set_constant("margin_top", "MarginContainer", s_md)
	t.set_constant("margin_bottom", "MarginContainer", s_md)

	_apply_button_set(
		t, "Button",
		sb["button_normal"], sb["button_hover"], sb["button_pressed"],
		sb["button_hover_pressed"], sb["button_disabled"], sb["focus_ring"],
		text, text, text_on_accent, dim, s_sm
	)

	t.set_type_variation("ToolButton", "Button")
	_apply_button_set(
		t, "ToolButton",
		sb["tool_normal"], sb["tool_hover"], sb["tool_pressed"],
		sb["tool_hover_pressed"], sb["tool_disabled"], sb["focus_ring_tool"],
		text, text, text_on_accent, dim, s_sm
	)

	t.set_type_variation("DangerButton", "Button")
	_apply_button_set(
		t, "DangerButton",
		sb["danger_normal"], sb["danger_hover"], sb["danger_pressed"],
		sb["danger_hover_pressed"], sb["danger_disabled"], sb["focus_ring"],
		text, text, text_on_accent, dim, s_sm
	)

	_apply_button_set(
		t, "OptionButton",
		sb["button_normal"], sb["button_hover"], sb["button_pressed"],
		sb["option_hover_pressed"], sb["button_disabled"], sb["focus_ring"],
		text, text, text_on_accent, dim, s_sm
	)
	t.set_color("font_hover_pressed_color", "OptionButton", text_on_accent)

	for cls in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", cls, sb["field_normal"])
		t.set_stylebox("focus", cls, sb["field_focus"])
		t.set_stylebox("read_only", cls, sb["field_readonly"])
		t.set_color("font_color", cls, text)
		t.set_color("font_placeholder_color", cls, dim)
		t.set_color("caret_color", cls, text)
		t.set_color("selection_color", cls, accent)
	t.set_color("font_uneditable_color", "LineEdit", dim)
	t.set_color("font_selected_color", "LineEdit", text_on_accent)
	t.set_color("font_readonly_color", "TextEdit", dim)

	_apply_button_set(
		t, "CheckBox",
		sb["empty"], sb["check_hover"], sb["check_pressed"],
		sb["check_hover"], sb["empty"], sb["focus_ring"],
		text, text, text, dim, s_sm
	)
	t.set_constant("h_separation", "CheckBox", s_sm)

	t.set_stylebox("panel", "ItemList", sb["well"])
	t.set_stylebox("focus", "ItemList", sb["list_focus"])
	t.set_stylebox("hovered", "ItemList", sb["list_hover"])
	t.set_stylebox("hovered_selected", "ItemList", sb["list_hover_selected"])
	t.set_stylebox("selected", "ItemList", sb["list_selected"])
	t.set_stylebox("selected_focus", "ItemList", sb["list_selected"])
	t.set_stylebox("cursor", "ItemList", sb["focus_ring"])
	t.set_color("font_color", "ItemList", text)
	t.set_color("font_hovered_color", "ItemList", text)
	t.set_color("font_selected_color", "ItemList", text_on_accent)
	t.set_constant("h_separation", "ItemList", s_sm)
	t.set_constant("v_separation", "ItemList", s_sm)

	t.set_stylebox("panel", "Tree", sb["well"])
	t.set_stylebox("focus", "Tree", sb["list_focus"])
	t.set_stylebox("hovered", "Tree", sb["list_hover"])
	t.set_stylebox("hovered_dimmed", "Tree", sb["list_dimmed"])
	t.set_stylebox("selected", "Tree", sb["list_selected"])
	t.set_stylebox("selected_focus", "Tree", sb["list_selected"])
	t.set_stylebox("cursor", "Tree", sb["focus_ring"])
	t.set_stylebox("cursor_unfocused", "Tree", sb["focus_ring_quiet"])
	t.set_stylebox("button_pressed", "Tree", sb["step_pressed"])
	t.set_stylebox("title_button_normal", "Tree", sb["step_normal"])
	t.set_stylebox("title_button_hover", "Tree", sb["step_hover"])
	t.set_stylebox("title_button_pressed", "Tree", sb["title_pressed"])
	t.set_color("font_color", "Tree", text)
	t.set_color("font_hovered_color", "Tree", text)
	t.set_color("font_selected_color", "Tree", text_on_accent)
	t.set_color("guide_color", "Tree", p["edge"])
	t.set_constant("h_separation", "Tree", s_sm)
	t.set_constant("v_separation", "Tree", s_sm)
	t.set_constant("item_margin", "Tree", s_md)

	for cls in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", cls, sb["slider_track"])
		t.set_stylebox("grabber_area", cls, sb["slider_grabber"])
		t.set_stylebox("grabber_area_highlight", cls, sb["slider_grabber_highlight"])

	t.set_color("font_color", "SpinBox", text)
	t.set_stylebox("normal", "SpinBox", sb["field_normal"])
	for side in ["up", "down"]:
		t.set_stylebox("%s_background" % side, "SpinBox", sb["step_normal"])
		t.set_stylebox("%s_background_hovered" % side, "SpinBox", sb["step_hover"])
		t.set_stylebox("%s_background_pressed" % side, "SpinBox", sb["step_pressed"])
		t.set_stylebox("%s_background_disabled" % side, "SpinBox", sb["step_disabled"])

	t.set_stylebox("panel", "PopupMenu", sb["popup_panel"])
	t.set_stylebox("hover", "PopupMenu", sb["popup_hover"])
	t.set_stylebox("labeled_separator_left", "PopupMenu", sb["separator"])
	t.set_stylebox("labeled_separator_right", "PopupMenu", sb["separator"])
	t.set_color("font_color", "PopupMenu", text)
	t.set_color("font_hover_color", "PopupMenu", text_on_accent)
	t.set_color("font_accelerator_color", "PopupMenu", dim)
	t.set_color("font_disabled_color", "PopupMenu", dim)
	t.set_color("font_separator_color", "PopupMenu", dim)
	t.set_constant("v_separation", "PopupMenu", s_sm)
	t.set_constant("h_separation", "PopupMenu", s_sm)

	t.set_stylebox("panel", "TooltipPanel", sb["tooltip_panel"])
	t.set_color("font_color", "TooltipLabel", text)

	t.set_stylebox("panel", "AcceptDialog", sb["panel"])
	t.set_color("title_color", "Window", text)

	# Keep unused tokens referenced so the table is the single source of truth.
	t.set_color("font_outline_color", "Label", p["danger"])
	t.set_constant("outline_size", "Label", 0)
	return t


## Assign a freshly generated Theme to the root Control. The one call site a
## font-size or token change needs; every child inherits from here.
static func apply_to(root: Control, font_size_override: int = 0) -> Theme:
	var t := make(font_size_override)
	if root != null:
		root.theme = t
	return t


static func _register_library(t: Theme, sb: Dictionary) -> void:
	for name in sb.keys():
		t.set_stylebox(str(name), STYLE_TYPE, sb[name])


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
