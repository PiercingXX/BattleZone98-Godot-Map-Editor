extends PanelContainer
class_name StatusBar
## Single owner of the status label, plus cursor / map / fps / log / view toggles.

signal log_toggled(on: bool)
signal goto_submitted(text: String)

var _kind: String = "info"
var _goto: LineEdit
var _activity: HBoxContainer
var _activity_spin: Label
var _activity_label: Label
var _spin_i: int = 0
var _spin_acc: float = 0.0

const _SPIN_FRAMES: PackedStringArray = ["◐", "◓", "◑", "◒"]

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
	_refresh_autosave_tooltip()
	_install_activity()
	Backend.call_started.connect(_on_backend_started)
	Backend.call_finished.connect(_on_backend_finished)
	Backend.call_failed.connect(_on_backend_failed)
	if Settings.has_signal("prefs_changed"):
		Settings.prefs_changed.connect(_refresh_autosave_tooltip)
	_sel = Label.new()
	_sel.name = "SelectionCount"
	_sel.visible = false
	_sel.add_theme_color_override("font_color", Color(1.0, 0.88, 0.38))
	_tsel = Label.new()
	_tsel.name = "TerrainSelection"
	_tsel.visible = false
	_tsel.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	var inner: HBoxContainer = $Inner
	_goto = LineEdit.new()
	_goto.name = "Goto"
	_goto.placeholder_text = "x, z"
	_goto.custom_minimum_size = Vector2(96, 0)
	_goto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_goto.editable = false
	_goto.tooltip_text = "Open a map first"
	_goto.text_submitted.connect(_on_goto_submitted)
	inner.add_child(_goto)
	inner.move_child(_goto, _cursor.get_index() + 1)
	inner.add_child(_sel)
	inner.move_child(_sel, _map.get_index() + 1)
	inner.add_child(_tsel)
	inner.move_child(_tsel, _sel.get_index() + 1)
	MapState.selection_changed.connect(_refresh_terrain_selection)
	MapState.session_changed.connect(_refresh_goto)
	_refresh_terrain_selection()
	_refresh_goto()
	set_status("info", "starting")


func _process(delta: float) -> void:
	if _activity != null and _activity.visible:
		_spin_acc += delta
		if _spin_acc >= 0.12:
			_spin_acc = 0.0
			_spin_i = (_spin_i + 1) % _SPIN_FRAMES.size()
			if _activity_spin:
				_activity_spin.text = _SPIN_FRAMES[_spin_i]
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


func _install_activity() -> void:
	_activity = HBoxContainer.new()
	_activity.name = "Activity"
	_activity.visible = false
	_activity.add_theme_constant_override("separation", 6)
	_activity_spin = Label.new()
	_activity_spin.name = "ActivitySpin"
	_activity_spin.text = _SPIN_FRAMES[0]
	_activity_spin.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	_activity_label = Label.new()
	_activity_label.name = "ActivityLabel"
	_activity_label.text = ""
	_activity_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	_activity.add_child(_activity_spin)
	_activity.add_child(_activity_label)
	var inner: HBoxContainer = $Inner
	inner.add_child(_activity)
	inner.move_child(_activity, _status.get_index())


func _on_backend_started(verb: String) -> void:
	_show_activity(verb)


func _on_backend_finished(_verb: String, _result: Dictionary) -> void:
	_hide_activity_if_idle()


func _on_backend_failed(_verb: String, _error: Dictionary) -> void:
	_hide_activity_if_idle()


func _show_activity(verb: String) -> void:
	if _activity == null:
		return
	_activity.visible = true
	if _activity_label:
		_activity_label.text = verb_activity_text(verb)
	_spin_i = 0
	_spin_acc = 0.0
	if _activity_spin:
		_activity_spin.text = _SPIN_FRAMES[0]


func _hide_activity_if_idle() -> void:
	if Backend.busy:
		var pending := str(Backend.get("_pending_verb"))
		if not pending.is_empty():
			_show_activity(pending)
			return
	if _activity:
		_activity.visible = false
		if _activity_label:
			_activity_label.text = ""


static func verb_activity_text(verb: String) -> String:
	match verb:
		"assets":
			return "importing assets…"
		"save":
			return "saving…"
		"open":
			return "opening…"
		"new":
			return "creating…"
		"validate":
			return "validating…"
		"render":
			return "rendering…"
		"package":
			return "packaging…"
		"probe":
			return "probing…"
		"worlds":
			return "loading worlds…"
		_:
			return "%s…" % verb


func _refresh_autosave_tooltip() -> void:
	var n := Settings.coerce_autosave_interval(Settings.autosave_interval_s)
	if n <= 0:
		tooltip_text = "Autosave is off. A crash does not lose a session that was saved. Save (Ctrl+S) writes the map files."
	else:
		tooltip_text = (
			"Unsaved sessions autosave every %ds. A crash does not lose the session. Save (Ctrl+S) writes the map files."
			% n
		)


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


func _on_goto_submitted(text: String) -> void:
	if not MapState.has_session:
		EditorFeedback.log("open a map first")
		return
	goto_submitted.emit(text)


func _refresh_goto() -> void:
	if _goto == null:
		return
	var session := MapState.has_session
	_goto.editable = session
	if session:
		_goto.tooltip_text = "Go to x, z  (Enter)"
	else:
		_goto.tooltip_text = "Open a map first"
		_goto.text = ""


func _shell() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("editor_shell")
