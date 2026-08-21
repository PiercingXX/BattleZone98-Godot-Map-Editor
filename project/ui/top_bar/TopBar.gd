extends PanelContainer
## Brand, map label, file actions, tools, variant, undo.

signal open_requested
signal gallery_requested
signal recent_open_requested(path: String)
signal new_requested
signal save_requested
signal save_as_requested
signal validate_requested
signal more_selected(id: int)
signal variant_changed
signal undo_requested
signal redo_requested
signal frame_requested
signal map_mode_requested
signal test_requested

const MORE_IMPORT := 0
const MORE_RENDER := 1
const MORE_INSTALL := 2
const MORE_PACK := 3
const MORE_PROBE := 4
const MORE_HELP := 5
const MORE_SAVE_AS := 6
const MORE_SCHEME_GODOT := 7
const MORE_SCHEME_GIMP := 8
const MORE_EXPORT_HEIGHTMAP := 9
const MORE_IMPORT_HEIGHTMAP := 10
const MORE_PUBLISH := 11
const MORE_SCREENSHOT := 12
const MORE_PREFS := 13
const OPEN_BROWSE_ID := 0
const OPEN_GALLERY_ID := 1

var _busy: bool = false
var _testing: bool = false
var _open_menu: PopupMenu
var _btn_test: Button
var _btn_map: Button
var _map_mode: bool = false
## id → Button for the secondary action row (former "More" menu).
var _actions: Dictionary = {}
var _scheme_opt: OptionButton

@onready var _map_label: Label = %MapLabel
@onready var _variant: OptionButton = %Variant
@onready var _btn_open: Button = %Open
@onready var _btn_new: Button = %New
@onready var _btn_save: Button = %Save
@onready var _btn_validate: Button = %Validate
@onready var _btn_undo: Button = %Undo
@onready var _btn_redo: Button = %Redo
@onready var _btn_frame: Button = %Frame
@onready var _row2: HBoxContainer = %Row2


func _ready() -> void:
	_install_open_menu()
	_install_test_button()
	_install_map_button()
	%New.pressed.connect(func(): new_requested.emit())
	%Save.pressed.connect(func(): save_requested.emit())
	%Validate.pressed.connect(func(): validate_requested.emit())
	%Undo.pressed.connect(_on_undo)
	%Redo.pressed.connect(_on_redo)
	%Frame.pressed.connect(_on_frame)
	_variant.item_selected.connect(func(_i): variant_changed.emit())
	_install_action_row()
	_apply_chrome_icons()
	MapState.session_changed.connect(_refresh_actions)
	MapState.objects_mutated.connect(_refresh_variant_counts)
	UndoStack.changed.connect(_refresh_actions)
	Backend.call_started.connect(func(_v): set_busy(true))
	Backend.call_finished.connect(func(_v, _r): set_busy(false))
	Backend.call_failed.connect(func(_v, _e): set_busy(false))
	_refresh_actions()


## Secondary action row: everything the old "More" menu hid, grouped
## file / capture / game / system, always visible.
func _install_action_row() -> void:
	if _row2 == null:
		return
	_action_button("SaveAs", "Save As…", MORE_SAVE_AS)
	_action_button("ImportPng", "Import PNG", MORE_IMPORT_HEIGHTMAP)
	_action_button("ExportPng", "Export PNG", MORE_EXPORT_HEIGHTMAP)
	_row2_sep()
	_action_button("Assets", "Assets", MORE_IMPORT)
	_action_button("Thumbnail", "Thumbnail", MORE_RENDER)
	_action_button("Screenshot", "Screenshot", MORE_SCREENSHOT)
	_row2_sep()
	_action_button("Install", "Install", MORE_INSTALL)
	_action_button("Pack", "Pack", MORE_PACK)
	_action_button("Publish", "Publish", MORE_PUBLISH)
	# Utility cluster hugs the right edge; a spacer eats the slack.
	var spacer := Control.new()
	spacer.name = "Row2Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row2.add_child(spacer)
	_action_button("Probe", "Probe", MORE_PROBE)
	_scheme_opt = OptionButton.new()
	_scheme_opt.name = "KeymapScheme"
	_scheme_opt.flat = true
	_scheme_opt.focus_mode = Control.FOCUS_NONE
	_scheme_opt.add_item("Keys: Godot", MORE_SCHEME_GODOT)
	_scheme_opt.add_item("Keys: GIMP", MORE_SCHEME_GIMP)
	_scheme_opt.tooltip_text = "Keyboard scheme"
	_scheme_opt.item_selected.connect(func(i: int) -> void:
		more_selected.emit(_scheme_opt.get_item_id(i))
	)
	_row2.add_child(_scheme_opt)
	_action_button("Hotkeys", "Hotkeys", MORE_HELP)
	_action_button("Prefs", "Prefs", MORE_PREFS)
	_refresh_action_row()


func _action_button(node_name: String, label: String, id: int) -> void:
	# Flat, text-only, quiet until hover: a secondary toolbar, not a
	# second wall of primary buttons.
	var b := Button.new()
	b.name = node_name
	b.text = label
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	if id == MORE_SAVE_AS:
		b.pressed.connect(func() -> void: save_as_requested.emit())
	else:
		b.pressed.connect(func() -> void: more_selected.emit(id))
	_row2.add_child(b)
	_actions[id] = b


func _row2_sep() -> void:
	var sep := VSeparator.new()
	_row2.add_child(sep)


func _install_test_button() -> void:
	## Terrain test, not a play-test: the build ships with every script
	## stripped, so a pack map loads as a plain mission instead of dying in
	## the pack's own game mode. See BzPackage._install_addon.
	if _btn_validate == null:
		return
	_btn_test = Button.new()
	_btn_test.name = "Test"
	_btn_test.text = "Test"
	_btn_test.pressed.connect(_on_test)
	EditorIcons.apply_button(_btn_test, "test", true)
	var parent := _btn_validate.get_parent()
	parent.add_child(_btn_test)
	parent.move_child(_btn_test, _btn_validate.get_index() + 1)


func _on_test() -> void:
	if _btn_test != null and _btn_test.disabled:
		return
	test_requested.emit()


func set_testing(value: bool) -> void:
	_testing = value
	_refresh_actions()


func _shell() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("editor_shell")


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
	_open_menu.add_item("Gallery…", OPEN_GALLERY_ID)
	if Settings.recent_maps.is_empty():
		return
	_open_menu.add_separator()
	var id := OPEN_GALLERY_ID + 1
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
	if id == OPEN_GALLERY_ID:
		gallery_requested.emit()
		return
	var idx := _open_menu.get_item_index(id)
	if idx < 0:
		return
	var path := str(_open_menu.get_item_metadata(idx))
	if path.is_empty() or _open_menu.is_item_disabled(idx) or not FileAccess.file_exists(path):
		EditorFeedback.log("file moved")
		return
	recent_open_requested.emit(path)


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


func _install_map_button() -> void:
	if _btn_frame == null:
		return
	_btn_map = Button.new()
	_btn_map.name = "MapMode"
	_btn_map.toggle_mode = true
	_btn_map.focus_mode = Control.FOCUS_ALL
	_btn_map.text = "3D"
	_btn_map.pressed.connect(_on_map_mode)
	var parent := _btn_frame.get_parent()
	parent.add_child(_btn_map)
	parent.move_child(_btn_map, _btn_frame.get_index() + 1)
	_refresh_map_button()


func _on_map_mode() -> void:
	if _btn_map != null and _btn_map.disabled:
		set_map_mode(_map_mode)
		return
	if not MapState.has_session:
		EditorFeedback.log("open a map first")
		set_map_mode(false)
		return
	map_mode_requested.emit()


func set_map_mode(on: bool) -> void:
	_map_mode = on
	_refresh_map_button()


func _refresh_map_button() -> void:
	if _btn_map == null:
		return
	_btn_map.set_pressed_no_signal(_map_mode)
	_btn_map.text = "2D" if _map_mode else "3D"
	var session := MapState.has_session
	_btn_map.disabled = not session
	if session:
		_btn_map.tooltip_text = "%s map mode  (%s)" % [
			"2D" if _map_mode else "3D",
			Keymap.format_action(Keymap.ACTION_MAP_MODE),
		]
	else:
		_btn_map.tooltip_text = "Open a map first"


func set_map_label(text: String) -> void:
	_map_label.text = text


func set_busy(value: bool) -> void:
	_busy = value
	_refresh_actions()


func fill_variants(variants: Array, active: String) -> void:
	_variant.clear()
	for v in variants:
		_variant.add_item(_variant_item_label(str(v)))
		_variant.set_item_metadata(_variant.item_count - 1, v)
		if str(v) == active:
			_variant.select(_variant.item_count - 1)
	_refresh_actions()


func _variant_item_label(variant: String) -> String:
	return "%s (%d)" % [
		EditActions.variant_display_name(variant),
		EditActions.variant_object_count(variant),
	]


func _refresh_variant_counts() -> void:
	if _variant == null:
		return
	for i in _variant.item_count:
		var v := str(_variant.get_item_metadata(i))
		_variant.set_item_text(i, _variant_item_label(v))


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
		_btn_new.tooltip_text = "Busy…" if _busy else "New map"
	if _btn_save:
		_btn_save.disabled = not can_act
		_btn_save.tooltip_text = "Save  (%s)" % Keymap.format_action(Keymap.ACTION_SAVE) if can_act else (
			"Busy…" if _busy else "Open a map first"
		)
	if _btn_validate:
		_btn_validate.disabled = not can_act
		_btn_validate.tooltip_text = "Validate the open map" if can_act else (
			"Busy…" if _busy else "Open a map first"
		)
	_refresh_test_button(session)
	if _btn_undo:
		_btn_undo.disabled = not UndoStack.can_undo()
		_btn_undo.tooltip_text = "Undo  (%s)" % Keymap.format_action(Keymap.ACTION_UNDO) if UndoStack.can_undo() else "Nothing to undo"
	if _btn_redo:
		_btn_redo.disabled = not UndoStack.can_redo()
		_btn_redo.tooltip_text = "Redo  (%s)" % Keymap.format_action(Keymap.ACTION_REDO) if UndoStack.can_redo() else "Nothing to redo"
	if _btn_frame:
		_btn_frame.disabled = not session
		_btn_frame.tooltip_text = "Frame the map  (%s)" % Keymap.format_action(Keymap.ACTION_FRAME) if session else "Open a map first"
	_refresh_map_button()
	if _variant:
		_variant.disabled = not session or _variant.item_count == 0
		_variant.tooltip_text = "Active variant (DM / _S / _ST / _SW)" if session else "Open a map first"
	_refresh_action_row()


func _refresh_test_button(session: bool) -> void:
	if _btn_test == null:
		return
	var root := not Settings.game_root.is_empty()
	if _testing:
		_btn_test.disabled = false
		_btn_test.tooltip_text = "Cancel the in-game test poll (does not close the game)"
		return
	if not session:
		_btn_test.disabled = true
		_btn_test.tooltip_text = "Open a map first"
		return
	if not root:
		_btn_test.disabled = true
		_btn_test.tooltip_text = "Probe an install first"
		return
	if _busy:
		_btn_test.disabled = true
		_btn_test.tooltip_text = "Busy…"
		return
	_btn_test.disabled = false
	_btn_test.tooltip_text = (
		"Terrain test: installs into addon/ with scripts stripped and launches via Steam, so the map loads as a plain mission. Pack maps ask which variant's layout to load. Polls BZLogger.txt for Sim Startup (8 = loaded). Press again to cancel the poll."
	)


func _refresh_action_row() -> void:
	if _actions.is_empty():
		return
	var session := MapState.has_session
	var root := not Settings.game_root.is_empty()
	_set_action(MORE_IMPORT, not _busy and root, "Probe an install first" if not root else "Busy…", "Import / refresh the asset index")
	_set_action(MORE_RENDER, not _busy and session, "Open a map first", "Render a map thumbnail")
	_set_action(MORE_SCREENSHOT, not _busy, "Busy…", "Screenshot the viewport")
	_set_action(MORE_INSTALL, not _busy and session and root, "Needs an open map and a game install", "Install into the game (addon)")
	_set_action(MORE_PACK, not _busy and session, "Open a map first", "Assemble a distributable pack")
	_set_action(MORE_PUBLISH, not _busy and session, "Busy…" if _busy else "Open a map first", "Publish for workshop")
	_set_action(MORE_PROBE, not _busy, "Busy…", "Re-probe the game install")
	_set_action(MORE_SAVE_AS, not _busy and session, "Open a map first", "Save a copy elsewhere")
	var hmap_ok := not _busy and session and MapState.has_heightmap()
	var hmap_tip := "Busy…" if _busy else ("Open a map first" if not session else "Map has no heightmap")
	_set_action(MORE_EXPORT_HEIGHTMAP, hmap_ok, hmap_tip, "Export the heightmap as 16-bit PNG")
	_set_action(MORE_IMPORT_HEIGHTMAP, hmap_ok, hmap_tip, "Import a 16-bit PNG heightmap")
	_set_action(MORE_HELP, true, "", "Keyboard reference  (%s)" % Keymap.format_action(Keymap.ACTION_HELP))
	_set_action(MORE_PREFS, true, "", "Editor preferences")
	_refresh_scheme_opt()


func _set_action(id: int, enabled: bool, disabled_tip: String, ok_tip: String) -> void:
	var b: Button = _actions.get(id)
	if b == null:
		return
	b.disabled = not enabled
	b.tooltip_text = ok_tip if enabled else disabled_tip


func refresh_keymap() -> void:
	_refresh_map_button()
	_refresh_action_row()


func _refresh_scheme_opt() -> void:
	if _scheme_opt == null:
		return
	var want := (
		MORE_SCHEME_GIMP
		if Keymap.active_scheme() == Keymap.SCHEME_GIMP
		else MORE_SCHEME_GODOT
	)
	var idx := _scheme_opt.get_item_index(want)
	if idx >= 0 and _scheme_opt.selected != idx:
		_scheme_opt.select(idx)


func _apply_chrome_icons() -> void:
	EditorIcons.apply_button(_btn_open, "open", true)
	EditorIcons.apply_button(_btn_new, "new", true)
	EditorIcons.apply_button(_btn_save, "save", true)
	EditorIcons.apply_button(_btn_validate, "validate", true)
	if _btn_test:
		EditorIcons.apply_button(_btn_test, "test", true)
	EditorIcons.apply_button(_btn_undo, "undo", false)
	EditorIcons.apply_button(_btn_redo, "redo", false)
	EditorIcons.apply_button(_btn_frame, "frame", false)
