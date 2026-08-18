extends PanelContainer
## Single owner of the status label, plus cursor / map / fps / log / view toggles.

signal log_toggled(on: bool)

var _kind: String = "info"

@onready var _cursor: Label = %Cursor
@onready var _map: Label = %MapInfo
@onready var _status: Label = %Status
@onready var _debug: Label = %Debug
@onready var _log: Button = %Log
@onready var _walk: Button = %Walk
@onready var _grid: Button = %Grid
@onready var _slope: Button = %Slope
var _sel: Label
var _tsel: Label


func _ready() -> void:
	_log.toggled.connect(func(on): log_toggled.emit(on))
	_walk.toggled.connect(_on_walk)
	_grid.toggled.connect(_on_grid)
	_slope.toggled.connect(_on_slope)
	_walk.set_pressed_no_signal(Settings.walk_mode)
	tooltip_text = "Unsaved sessions autosave every 30s. A crash does not lose the session. Save (Ctrl+S) writes the map files."
	_sel = Label.new()
	_sel.name = "SelectionCount"
	_sel.visible = false
	_sel.add_theme_color_override("font_color", Color(1.0, 0.88, 0.38))
	_tsel = Label.new()
	_tsel.name = "TerrainSelection"
	_tsel.visible = false
	_tsel.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	var inner: HBoxContainer = $Inner
	inner.add_child(_sel)
	inner.move_child(_sel, _map.get_index() + 1)
	inner.add_child(_tsel)
	inner.move_child(_tsel, _sel.get_index() + 1)
	MapState.selection_changed.connect(_refresh_terrain_selection)
	_refresh_terrain_selection()
	set_status("info", "starting")


func _process(_delta: float) -> void:
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


func set_status(kind: String, text: String) -> void:
	if kind == "transient" and _kind in ["busy", "error"]:
		return
	_kind = kind
	_status.text = text
	if kind == "error":
		_status.add_theme_color_override("font_color", Color(0.95, 0.35, 0.32))
	else:
		_status.remove_theme_color_override("font_color")


func set_cursor(text: String) -> void:
	_cursor.text = text


func set_map_info(text: String) -> void:
	_map.text = text


func set_debug(text: String) -> void:
	_debug.text = text


func set_selection_count(count: int, show: bool) -> void:
	if _sel == null:
		return
	_sel.visible = show
	_sel.text = "%d selected" % count if show else ""


func set_terrain_selection_text(text: String, show: bool) -> void:
	if _tsel == null:
		return
	_tsel.visible = show
	_tsel.text = text if show else ""


func _refresh_terrain_selection() -> void:
	if _tsel == null:
		return
	if MapState.selection_empty():
		set_terrain_selection_text("", false)
		return
	set_terrain_selection_text(
		"selection: %d cells (~%.0f m²)" % [
			MapState.selection_cell_count(),
			MapState.selection_area_m2(),
		],
		true,
	)


func set_log_visible(on: bool) -> void:
	_log.set_pressed_no_signal(on)


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
	EditorFeedback.log("slope overlay %s" % ("on" if on else "off"))


func _shell() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("editor_shell")
