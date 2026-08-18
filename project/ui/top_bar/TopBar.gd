extends PanelContainer
## Brand, map label, file actions, tools, variant, undo.

signal open_requested
signal recent_open_requested(path: String)
signal new_requested
signal save_requested
signal save_as_requested
signal validate_requested
signal more_selected(id: int)
signal tool_selected(name: String)
signal variant_changed
signal undo_requested
signal redo_requested
signal frame_requested

const MORE_IMPORT := 0
const MORE_RENDER := 1
const MORE_INSTALL := 2
const MORE_PACK := 3
const MORE_PROBE := 4
const MORE_HELP := 5
const MORE_SAVE_AS := 6
const OPEN_BROWSE_ID := 0

var _setting_tool: bool = false
var _busy: bool = false
var _open_menu: PopupMenu

@onready var _map_label: Label = %MapLabel
@onready var _variant: OptionButton = %Variant
@onready var _btn_open: Button = %Open
@onready var _btn_new: Button = %New
@onready var _btn_save: Button = %Save
@onready var _btn_validate: Button = %Validate
@onready var _btn_undo: Button = %Undo
@onready var _btn_redo: Button = %Redo
@onready var _btn_frame: Button = %Frame
@onready var _tools: HBoxContainer = %Tools
@onready var _more: MenuButton = %More


func _ready() -> void:
	_install_open_menu()
	%New.pressed.connect(func(): new_requested.emit())
	%Save.pressed.connect(func(): save_requested.emit())
	%Validate.pressed.connect(func(): validate_requested.emit())
	%Undo.pressed.connect(_on_undo)
	%Redo.pressed.connect(_on_redo)
	%Frame.pressed.connect(_on_frame)
	_variant.item_selected.connect(func(_i): variant_changed.emit())
	var pop: PopupMenu = _more.get_popup()
	pop.add_item("Import assets", MORE_IMPORT)
	pop.add_item("Render thumbnail", MORE_RENDER)
	pop.add_item("Install into game (addon)", MORE_INSTALL)
	pop.add_item("Assemble pack", MORE_PACK)
	pop.add_separator()
	pop.add_item("Re-probe install", MORE_PROBE)
	pop.add_item("Save As…", MORE_SAVE_AS)
	pop.add_item("Hotkeys  F1", MORE_HELP)
	pop.id_pressed.connect(func(id):
		if id == MORE_SAVE_AS:
			save_as_requested.emit()
		else:
			more_selected.emit(id)
	)
	pop.about_to_popup.connect(_refresh_more)
	for child in _tools.get_children():
		if child is Button:
			var tool_name := String(child.name).to_lower()
			child.pressed.connect(_on_tool_button.bind(tool_name))
	ToolState.tool_changed.connect(set_tool)
	MapState.session_changed.connect(_refresh_actions)
	UndoStack.changed.connect(_refresh_actions)
	Backend.call_started.connect(func(_v): set_busy(true))
	Backend.call_finished.connect(func(_v, _r): set_busy(false))
	Backend.call_failed.connect(func(_v, _e): set_busy(false))
	_refresh_actions()


func _install_open_menu() -> void:
	_open_menu = PopupMenu.new()
	_open_menu.name = "OpenMenu"
	_btn_open.add_child(_open_menu)
	_btn_open.pressed.connect(_on_open_pressed)
	_open_menu.id_pressed.connect(_on_open_menu_id)
	_open_menu.about_to_popup.connect(refresh_open_menu)
	refresh_open_menu()


func _on_open_pressed() -> void:
	if _busy:
		EditorFeedback.log("Busy…")
		return
	refresh_open_menu()
	var r := _btn_open.get_global_rect()
	_open_menu.popup(Rect2i(int(r.position.x), int(r.position.y + r.size.y), 0, 0))


func refresh_open_menu() -> void:
	if _open_menu == null:
		return
	_open_menu.clear()
	_open_menu.add_item("Browse…", OPEN_BROWSE_ID)
	if Settings.recent_maps.is_empty():
		return
	_open_menu.add_separator()
	var id := 1
	for path in Settings.recent_maps:
		var cleaned := str(path)
		var label := cleaned.get_file()
		if label.is_empty():
			label = cleaned
		_open_menu.add_item(label, id)
		var idx := _open_menu.get_item_index(id)
		_open_menu.set_item_metadata(idx, cleaned)
		if FileAccess.file_exists(cleaned):
			_open_menu.set_item_tooltip(idx, cleaned)
		else:
			_open_menu.set_item_disabled(idx, true)
			_open_menu.set_item_tooltip(idx, "file moved")
		id += 1


func _on_open_menu_id(id: int) -> void:
	if id == OPEN_BROWSE_ID:
		open_requested.emit()
		return
	var idx := _open_menu.get_item_index(id)
	if idx < 0:
		return
	var path := str(_open_menu.get_item_metadata(idx))
	if path.is_empty() or _open_menu.is_item_disabled(idx) or not FileAccess.file_exists(path):
		EditorFeedback.log("file moved")
		return
	recent_open_requested.emit(path)


func _on_tool_button(tool_name: String) -> void:
	if _setting_tool:
		return
	tool_selected.emit(tool_name)


func _on_undo() -> void:
	if not UndoStack.can_undo():
		EditorFeedback.log("nothing to undo")
		return
	undo_requested.emit()


func _on_redo() -> void:
	if not UndoStack.can_redo():
		EditorFeedback.log("nothing to redo")
		return
	redo_requested.emit()


func _on_frame() -> void:
	if not MapState.has_session:
		EditorFeedback.log("open a map to frame")
		return
	frame_requested.emit()


func set_map_label(text: String) -> void:
	_map_label.text = text


func set_busy(value: bool) -> void:
	_busy = value
	_refresh_actions()


func set_tool(name: String) -> void:
	_setting_tool = true
	var node := _tools.get_node_or_null(name.capitalize())
	if name == "flatten":
		node = _tools.get_node_or_null("Flatten")
	if node is Button:
		(node as Button).button_pressed = true
	_setting_tool = false


func fill_variants(variants: Array, active: String) -> void:
	_variant.clear()
	for v in variants:
		var label := "DM" if str(v) == "" else str(v)
		_variant.add_item(label)
		_variant.set_item_metadata(_variant.item_count - 1, v)
		if str(v) == active:
			_variant.select(_variant.item_count - 1)
	_refresh_actions()


func selected_variant() -> String:
	if _variant.selected < 0:
		return ""
	return str(_variant.get_item_metadata(_variant.selected))


func _refresh_actions() -> void:
	var session := MapState.has_session
	var can_act := session and not _busy
	if _btn_open:
		_btn_open.disabled = _busy
		_btn_open.tooltip_text = "Busy…" if _busy else "Open a map"
	if _btn_new:
		_btn_new.disabled = _busy
	if _btn_save:
		_btn_save.disabled = not can_act
		_btn_save.tooltip_text = "Save  (Ctrl+S)" if can_act else (
			"Busy…" if _busy else "Open a map first"
		)
	if _btn_validate:
		_btn_validate.disabled = not can_act
		_btn_validate.tooltip_text = "Validate the open map" if can_act else (
			"Busy…" if _busy else "Open a map first"
		)
	if _btn_undo:
		_btn_undo.disabled = not UndoStack.can_undo()
		_btn_undo.tooltip_text = "Undo  (Ctrl+Z)" if UndoStack.can_undo() else "Nothing to undo"
	if _btn_redo:
		_btn_redo.disabled = not UndoStack.can_redo()
		_btn_redo.tooltip_text = "Redo  (Ctrl+Shift+Z)" if UndoStack.can_redo() else "Nothing to redo"
	if _btn_frame:
		_btn_frame.disabled = not session
		_btn_frame.tooltip_text = "Frame the map  (F)" if session else "Open a map first"
	if _variant:
		_variant.disabled = not session or _variant.item_count == 0
		_variant.tooltip_text = "Active variant (DM / _S / _ST / _SW)" if session else "Open a map first"
	_refresh_more()


func _refresh_more() -> void:
	if _more == null:
		return
	var pop: PopupMenu = _more.get_popup()
	if pop.get_item_count() == 0:
		return
	var session := MapState.has_session
	var root := not Settings.game_root.is_empty()
	_set_more_item(pop, MORE_IMPORT, not _busy and root, "Probe an install first" if not root else "Import / refresh the asset index")
	_set_more_item(pop, MORE_RENDER, not _busy and session, "Open a map first")
	_set_more_item(pop, MORE_INSTALL, not _busy and session and root, "Needs an open map and a game install")
	_set_more_item(pop, MORE_PACK, not _busy and session, "Open a map first")
	_set_more_item(pop, MORE_PROBE, not _busy, "Busy…")
	_set_more_item(pop, MORE_SAVE_AS, not _busy and session, "Open a map first")
	_set_more_item(pop, MORE_HELP, true, "Keyboard reference  (F1)")


func _set_more_item(pop: PopupMenu, id: int, enabled: bool, disabled_tip: String) -> void:
	var idx := pop.get_item_index(id)
	if idx < 0:
		return
	pop.set_item_disabled(idx, not enabled)
	pop.set_item_tooltip(idx, disabled_tip if not enabled else "")
