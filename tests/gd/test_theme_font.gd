extends RefCounted
## DarkTheme's named StyleBox library and the independent font-size setting.

const EXPECTED_BOXES: PackedStringArray = [
	"panel", "well", "empty",
	"button_normal", "button_hover", "button_pressed",
	"button_hover_pressed", "button_disabled", "option_hover_pressed",
	"tool_normal", "tool_hover", "tool_pressed", "tool_hover_pressed",
	"tool_disabled",
	"danger_normal", "danger_hover", "danger_pressed",
	"danger_hover_pressed", "danger_disabled",
	"check_hover", "check_pressed",
	"field_normal", "field_focus", "field_readonly",
	"list_hover", "list_hover_selected", "list_selected", "list_dimmed",
	"list_focus",
	"step_normal", "step_hover", "step_pressed", "step_disabled",
	"title_pressed",
	"slider_track", "slider_grabber", "slider_grabber_highlight",
	"popup_panel", "popup_hover", "separator", "tooltip_panel",
	"focus_ring", "focus_ring_tool", "focus_ring_quiet",
]


func run(t) -> void:
	var snap := _snapshot()
	_library(t)
	_theme_carries_library(t)
	_font_size(t)
	await _applies_to_root(t)
	_restore(snap)


func _library(t) -> void:
	var lib := DarkTheme.styleboxes()
	var names := DarkTheme.stylebox_names()
	for name in EXPECTED_BOXES:
		t.ok(lib.has(str(name)), "library has %s" % name)
		t.ok(names.has(str(name)), "stylebox_names lists %s" % name)
		t.ok(DarkTheme.stylebox(str(name)) is StyleBox, "%s is a StyleBox" % name)
	t.eq(names.size(), lib.size(), "names and library agree")
	t.eq(DarkTheme.stylebox("no_such_box"), null)

	# Every box is mixed from the tokens; nothing is invented alongside them.
	var tok := DarkTheme.tokens()
	var p := DarkTheme.palette()
	t.eq(p["accent"], tok["accent"])
	t.eq(p["edge"], (tok["bg"] as Color).darkened(0.28))
	var tool_pressed := lib["tool_pressed"] as StyleBoxFlat
	t.eq(tool_pressed.bg_color, tok["accent"], "the active tool is accent fill")
	var grabber := lib["slider_grabber"] as StyleBoxFlat
	t.eq(grabber.bg_color, tok["accent"])
	var ring := lib["focus_ring"] as StyleBoxFlat
	t.ok(not ring.draw_center, "a focus ring draws no centre")
	t.eq(ring.border_color, tok["accent"])


func _theme_carries_library(t) -> void:
	var theme := DarkTheme.make()
	t.ok(theme is Theme)
	for name in EXPECTED_BOXES:
		t.ok(
			theme.has_stylebox(str(name), DarkTheme.STYLE_TYPE),
			"theme carries %s under %s" % [name, DarkTheme.STYLE_TYPE],
		)
		t.ok(theme.get_stylebox(str(name), DarkTheme.STYLE_TYPE) is StyleBox)
	# The library is what the class defaults are built from, not a copy of it.
	t.eq(
		theme.get_stylebox("pressed", "ToolButton"),
		theme.get_stylebox("tool_pressed", DarkTheme.STYLE_TYPE),
		"ToolButton pressed IS the named box",
	)
	t.eq(
		theme.get_stylebox("panel", "PanelContainer"),
		theme.get_stylebox("panel", DarkTheme.STYLE_TYPE),
	)
	t.eq(
		theme.get_stylebox("focus", "Button"),
		theme.get_stylebox("focus_ring", DarkTheme.STYLE_TYPE),
	)


func _font_size(t) -> void:
	t.eq(Settings.coerce_ui_font_size(13), 13)
	t.eq(Settings.coerce_ui_font_size(4), Settings.UI_FONT_SIZE_MIN, "tiny clamps up")
	t.eq(Settings.coerce_ui_font_size(99), Settings.UI_FONT_SIZE_MAX, "huge clamps down")
	t.eq(Settings.coerce_ui_font_size("16"), 16)
	t.eq(Settings.coerce_ui_font_size("16.4"), 16)
	t.eq(Settings.coerce_ui_font_size("nope"), Settings.UI_FONT_SIZE_DEFAULT)
	t.eq(Settings.coerce_ui_font_size(null), Settings.UI_FONT_SIZE_DEFAULT)
	t.eq(Settings.coerce_ui_font_size(INF), Settings.UI_FONT_SIZE_DEFAULT)

	Settings.ui_font_size = Settings.UI_FONT_SIZE_DEFAULT
	Settings.ui_scale = 1.0
	t.eq(DarkTheme.make().default_font_size, Settings.UI_FONT_SIZE_DEFAULT)

	Settings.ui_font_size = 19
	Settings.save()
	t.eq(DarkTheme.make().default_font_size, 19, "the theme reads Settings")
	t.eq(Settings.ui_scale, 1.0, "font size leaves ui scale alone")
	Settings.ui_font_size = Settings.UI_FONT_SIZE_DEFAULT
	Settings._load()
	t.eq(Settings.ui_font_size, 19, "font size persists")
	t.eq(Settings.ui_scale, 1.0)

	# Scaling the chrome must not move the type, and vice versa.
	Settings.ui_scale = 1.5
	Settings.save()
	Settings._load()
	t.eq(Settings.ui_font_size, 19, "ui scale does not drag font size along")
	t.eq(DarkTheme.make().default_font_size, 19)
	t.eq(DarkTheme.make(11).default_font_size, 11, "an explicit size wins")
	t.eq(DarkTheme.make(0).default_font_size, 19, "0 means: ask Settings")


func _applies_to_root(t) -> void:
	var root := Control.new()
	t.tree.root.add_child(root)
	await t.tree.process_frame
	Settings.ui_font_size = 15
	var theme := DarkTheme.apply_to(root)
	t.ok(root.theme == theme, "apply_to seats the theme on the root Control")
	t.eq(root.theme.default_font_size, 15)
	var child := Label.new()
	root.add_child(child)
	await t.tree.process_frame
	t.eq(child.get_theme_default_font_size(), 15, "children inherit the size")
	t.eq(DarkTheme.apply_to(null, 12).default_font_size, 12, "a null root is harmless")
	root.queue_free()
	await t.tree.process_frame


func _snapshot() -> Dictionary:
	var cfg: Variant = null
	if FileAccess.file_exists(Settings.PATH):
		cfg = FileAccess.get_file_as_string(Settings.PATH)
	return {
		"cfg": cfg,
		"font": Settings.ui_font_size,
		"ui_scale": Settings.ui_scale,
	}


func _restore(snap: Dictionary) -> void:
	if snap["cfg"] == null:
		if FileAccess.file_exists(Settings.PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
		Settings._cfg = ConfigFile.new()
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		if f:
			f.store_string(str(snap["cfg"]))
			f.close()
		Settings._load()
	Settings.ui_font_size = int(snap["font"])
	Settings.ui_scale = float(snap["ui_scale"])
