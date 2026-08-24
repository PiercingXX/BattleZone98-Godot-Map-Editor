extends PanelContainer
## GIMP-style vertical toolbox on the left edge: icon-only tool buttons,
## then view toggles (walk/grid/slope/log) below a separator.

signal tool_selected(name: String)
signal log_toggled(on: bool)

const CAPTIONS := {
	"Flatten": "Flat",
	"Qsel": "QSel",
	"Rsel": "RSel",
	"Dilate": "Grow",
	"Setheight": "Set H",
	"Setangle": "Set °",
}
const ACTIONS := {
	"Fly": Keymap.ACTION_FLY,
	"Raise": Keymap.ACTION_RAISE,
	"Lower": Keymap.ACTION_LOWER,
	"Flatten": Keymap.ACTION_FLATTEN,
	"Smooth": Keymap.ACTION_SMOOTH,
	"Ramp": Keymap.ACTION_RAMP,
	"Paint": Keymap.ACTION_PAINT,
	"Place": Keymap.ACTION_PLACE,
	"Select": Keymap.ACTION_SELECT,
	"Noise": Keymap.ACTION_NOISE,
	"Qsel": Keymap.ACTION_QSEL,
	"Rsel": Keymap.ACTION_RSEL,
	"Wand": Keymap.ACTION_WAND,
	"Clone": Keymap.ACTION_CLONE,
	"Erode": Keymap.ACTION_ERODE,
	"Dilate": Keymap.ACTION_DILATE,
	"Setheight": Keymap.ACTION_SET_HEIGHT,
	"Setangle": Keymap.ACTION_SET_ANGLE,
}
## Rail order mirrors the workflow: navigate, sculpt, paint, terrain-select.
## Place / Select live on ObjectToolsBar, not here.
const ORDER: PackedStringArray = [
	"Fly", "Raise", "Lower", "Flatten", "Smooth", "Ramp", "Noise",
	"Erode", "Dilate", "Setheight", "Setangle",
	"Paint", "Clone", "Qsel", "Rsel", "Wand",
]

var _setting_tool: bool = false
var _walk: Button
var _grid: Button
var _slope: Button
var _log: Button

@onready var _tools: VBoxContainer = %Tools


func _ready() -> void:
	_install_buttons()
	_install_toggles()
	refresh_keymap()
	ToolState.tool_changed.connect(set_tool)
	set_tool(ToolState.tool)


func _install_buttons() -> void:
	if _tools == null:
		return
	var group := ButtonGroup.new()
	for id in ORDER:
		if _tools.get_node_or_null(id) != null:
			continue
		var b := Button.new()
		b.name = id
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_ALL
		b.theme_type_variation = "ToolButton"
		b.button_group = group
		EditorIcons.apply_button(b, str(EditorIcons.TOOL_ICONS.get(id, "fly")), false)
		b.pressed.connect(_on_tool_button.bind(id.to_lower()))
		_tools.add_child(b)


func _install_toggles() -> void:
	if _tools == null:
		return
	var sep := HSeparator.new()
	sep.name = "ToggleSep"
	_tools.add_child(sep)
	_walk = _make_toggle("Walk", "walk", "Walk-the-surface  (V)")
	_grid = _make_toggle("Grid", "grid", "Terrain grid  (G)")
	_slope = _make_toggle("Slope", "slope", "Slope tint  (H)")
	_log = _make_toggle("Log", "log", "Toggle console  (`)")
	_walk.toggled.connect(_on_walk)
	_grid.toggled.connect(_on_grid)
	_slope.toggled.connect(_on_slope)
	_log.toggled.connect(func(on: bool) -> void: log_toggled.emit(on))
	_walk.set_pressed_no_signal(Settings.walk_mode)


func _make_toggle(id: String, icon: String, tip: String) -> Button:
	var b := Button.new()
	b.name = id
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = "ToolButton"
	b.tooltip_text = tip
	EditorIcons.apply_button(b, icon, false)
	_tools.add_child(b)
	return b


func set_log_visible(on: bool) -> void:
	if _log:
		_log.set_pressed_no_signal(on)


func _process(_delta: float) -> void:
	# Mirror external state changes (keymap toggles, settings restore).
	if _walk and _walk.button_pressed != Settings.walk_mode:
		_walk.set_pressed_no_signal(Settings.walk_mode)
	var shell := _shell()
	if shell == null:
		return
	if _grid:
		_grid.set_pressed_no_signal(bool(shell.get("_show_grid")))
	if _slope and shell.get("_terrain") != null:
		var terrain: Object = shell.get("_terrain")
		_slope.set_pressed_no_signal(bool(terrain.get("_show_slope")))


func _on_walk(on: bool) -> void:
	if Settings.walk_mode == on:
		return
	Settings.walk_mode = on
	Settings.save()
	EditorFeedback.log("walk mode %s" % on)


func _on_grid(on: bool) -> void:
	var shell := _shell()
	if shell == null:
		_grid.set_pressed_no_signal(false)
		return
	if bool(shell.get("_show_grid")) == on:
		return
	shell.set("_show_grid", on)
	if shell.has_method("_apply_grid"):
		shell.call("_apply_grid")
	Settings.view_grid = on
	Settings.save()
	EditorFeedback.log("grid %s" % ("on" if on else "off"))


func _on_slope(on: bool) -> void:
	var shell := _shell()
	if shell == null or shell.get("_terrain") == null:
		_slope.set_pressed_no_signal(false)
		return
	var terrain: Object = shell.get("_terrain")
	if bool(terrain.get("_show_slope")) == on:
		return
	if terrain.has_method("set_slope_overlay"):
		terrain.call("set_slope_overlay", on)
	Settings.view_slope = on
	Settings.save()
	EditorFeedback.log("slope overlay %s" % ("on" if on else "off"))


func _shell() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("editor_shell")


func _on_tool_button(tool_name: String) -> void:
	if _setting_tool:
		return
	tool_selected.emit(tool_name)


func set_tool(name: String) -> void:
	if _tools == null:
		return
	_setting_tool = true
	var node := _tools.get_node_or_null(name.capitalize())
	if node is Button:
		(node as Button).button_pressed = true
	_setting_tool = false


func refresh_keymap() -> void:
	if _tools == null:
		return
	for id in ACTIONS:
		var node := _tools.get_node_or_null(str(id))
		if not (node is Button):
			continue
		var caption := str(CAPTIONS.get(str(id), str(id)))
		(node as Button).tooltip_text = "%s  (%s)" % [
			caption, Keymap.format_action(str(ACTIONS[id])),
		]
