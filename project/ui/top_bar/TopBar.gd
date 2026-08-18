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
signal view_changed
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
const VIEW_GEYSERS := 0
const VIEW_SCRAP := 1
const VIEW_SPAWNS := 2
const VIEW_BUILDINGS := 3
const VIEW_UNITS := 4
const VIEW_PROPS := 5
const VIEW_WATER := 6
const VIEW_PLANTS := 7
const VIEW_SKY := 8
const VIEW_GHOST_VARIANTS := 9
const VIEW_BALANCE := 10
const VIEW_AIPATHS := 11

var _busy: bool = false
var _testing: bool = false
var _open_menu: PopupMenu
var _scheme_menu: PopupMenu
var _view_menu: PopupMenu
var _btn_test: Button
var _btn_map: Button
var _map_mode: bool = false

@onready var _map_label: Label = %MapLabel
@onready var _variant: OptionButton = %Variant
@onready var _btn_open: Button = %Open
@onready var _btn_new: Button = %New
@onready var _btn_save: Button = %Save
@onready var _btn_validate: Button = %Validate
@onready var _btn_undo: Button = %Undo
@onready var _btn_redo: Button = %Redo
@onready var _btn_frame: Button = %Frame
@onready var _more: MenuButton = %More
@onready var _view: MenuButton = %View


func _ready() -> void:
	_install_open_menu()
	_install_view_menu()
	_install_test_button()
	_install_map_button()
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
	pop.add_item("Screenshot viewport", MORE_SCREENSHOT)
	pop.add_item("Install into game (addon)", MORE_INSTALL)
	pop.add_item("Assemble pack", MORE_PACK)
	pop.add_item("Publish for workshop…", MORE_PUBLISH)
	pop.add_separator()
	pop.add_item("Re-probe install", MORE_PROBE)
	pop.add_item("Save As…", MORE_SAVE_AS)
	pop.add_item("Export heightmap PNG…", MORE_EXPORT_HEIGHTMAP)
	pop.add_item("Import heightmap PNG…", MORE_IMPORT_HEIGHTMAP)
	pop.add_item("Hotkeys  F1", MORE_HELP)
	pop.add_item("Preferences…", MORE_PREFS)
	_scheme_menu = PopupMenu.new()
	_scheme_menu.name = "KeymapScheme"
	_scheme_menu.add_radio_check_item("Godot", MORE_SCHEME_GODOT)
	_scheme_menu.add_radio_check_item("GIMP", MORE_SCHEME_GIMP)
	pop.add_child(_scheme_menu)
	pop.add_submenu_item("Keyboard scheme", _scheme_menu.name)
	_scheme_menu.id_pressed.connect(func(id): more_selected.emit(id))
	pop.id_pressed.connect(func(id):
		if id == MORE_SAVE_AS:
			save_as_requested.emit()
		else:
			more_selected.emit(id)
	)
	pop.about_to_popup.connect(_refresh_more)
	_apply_chrome_icons()
	MapState.session_changed.connect(_refresh_actions)
	MapState.features_changed.connect(_refresh_view_menu)
	MapState.objects_mutated.connect(_refresh_variant_counts)
	UndoStack.changed.connect(_refresh_actions)
	Backend.call_started.connect(func(_v): set_busy(true))
	Backend.call_finished.connect(func(_v, _r): set_busy(false))
	Backend.call_failed.connect(func(_v, _e): set_busy(false))
	_refresh_actions()


func _install_test_button() -> void:
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


func _install_view_menu() -> void:
	if _view == null:
		return
	_view_menu = _view.get_popup()
	_view_menu.hide_on_checkable_item_selection = false
	_view_menu.clear()
	_view_menu.add_check_item("Geysers", VIEW_GEYSERS)
	_view_menu.add_check_item("Scrap", VIEW_SCRAP)
	_view_menu.add_check_item("Spawns", VIEW_SPAWNS)
	_view_menu.add_check_item("Buildings", VIEW_BUILDINGS)
	_view_menu.add_check_item("Units", VIEW_UNITS)
	_view_menu.add_check_item("Props", VIEW_PROPS)
	_view_menu.add_separator()
	_view_menu.add_check_item("Water", VIEW_WATER)
	_view_menu.add_check_item("Plants", VIEW_PLANTS)
	_view_menu.add_check_item("Sky", VIEW_SKY)
	_view_menu.add_separator()
	_view_menu.add_check_item("Ghost other variants", VIEW_GHOST_VARIANTS)
	_view_menu.add_separator()
	_view_menu.add_check_item("Balance", VIEW_BALANCE)
	_view_menu.add_check_item("AI Paths", VIEW_AIPATHS)
	_view_menu.id_pressed.connect(_on_view_id)
	_view_menu.about_to_popup.connect(_refresh_view_menu)
	_refresh_view_menu()


func _on_view_id(id: int) -> void:
	if _view_menu == null:
		return
	var idx := _view_menu.get_item_index(id)
	if idx < 0:
		return
	if _view_menu.is_item_disabled(idx):
		return
	if id == VIEW_GHOST_VARIANTS:
		ObjectMarkers.ghost_other_variants = not ObjectMarkers.ghost_other_variants
		Settings.view_ghost_variants = ObjectMarkers.ghost_other_variants
		Settings.save()
		EditorFeedback.log("view ghost_other_variants %s" % (
			"on" if ObjectMarkers.ghost_other_variants else "off"
		))
		view_changed.emit()
		_refresh_view_menu()
		return
	if id == VIEW_BALANCE:
		if not MapState.has_session:
			return
		BalanceOverlay.enabled = not BalanceOverlay.enabled
		Settings.view_balance = BalanceOverlay.enabled
		Settings.save()
		EditorFeedback.log("view balance %s" % ("on" if BalanceOverlay.enabled else "off"))
		view_changed.emit()
		_refresh_view_menu()
		return
	if id == VIEW_AIPATHS:
		if not MapState.has_session:
			return
		AiPathOverlay.enabled = not AiPathOverlay.enabled
		Settings.view_aipaths = AiPathOverlay.enabled
		Settings.save()
		EditorFeedback.log("view aipaths %s" % ("on" if AiPathOverlay.enabled else "off"))
		view_changed.emit()
		_refresh_view_menu()
		return
	var key := _view_key(id)
	if key.is_empty():
		return
	var on := not Settings.view_flag(key)
	Settings.set_view_group(key, on)
	Settings.save()
	EditorFeedback.log("view %s %s" % [key, "on" if on else "off"])
	view_changed.emit()
	_refresh_view_menu()


func _view_key(id: int) -> String:
	match id:
		VIEW_GEYSERS:
			return "geysers"
		VIEW_SCRAP:
			return "scrap"
		VIEW_SPAWNS:
			return "spawns"
		VIEW_BUILDINGS:
			return "buildings"
		VIEW_UNITS:
			return "units"
		VIEW_PROPS:
			return "props"
		VIEW_WATER:
			return "water"
		VIEW_PLANTS:
			return "plants"
		VIEW_SKY:
			return "sky"
	return ""


func _refresh_view_menu() -> void:
	if _view_menu == null or _view_menu.get_item_count() == 0:
		return
	_set_view_check(VIEW_GEYSERS, Settings.view_geysers, true, "")
	_set_view_check(VIEW_SCRAP, Settings.view_scrap, true, "")
	_set_view_check(VIEW_SPAWNS, Settings.view_spawns, true, "")
	_set_view_check(VIEW_BUILDINGS, Settings.view_buildings, true, "")
	_set_view_check(VIEW_UNITS, Settings.view_units, true, "")
	_set_view_check(VIEW_PROPS, Settings.view_props, true, "")
	_set_view_check(VIEW_WATER, Settings.view_water, true, "")
	var plants_ok := _plants_overlay_ready()
	_set_view_check(VIEW_PLANTS, Settings.view_plants, plants_ok, "no plant regions")
	_set_view_check(VIEW_SKY, Settings.view_sky, true, "")
	_set_view_check(
		VIEW_GHOST_VARIANTS,
		ObjectMarkers.ghost_other_variants,
		true,
		"Draw other BZN variants as unpickable ghosts",
	)
	_set_view_check(
		VIEW_BALANCE,
		BalanceOverlay.enabled,
		MapState.has_session,
		"Open a map first",
	)
	_set_view_check(
		VIEW_AIPATHS,
		AiPathOverlay.enabled,
		MapState.has_session,
		"Open a map first",
	)


func _set_view_check(id: int, on: bool, enabled: bool, disabled_tip: String) -> void:
	var idx := _view_menu.get_item_index(id)
	if idx < 0:
		return
	_view_menu.set_item_checked(idx, on)
	_view_menu.set_item_disabled(idx, not enabled)
	if enabled:
		_view_menu.set_item_tooltip(idx, "")
	else:
		_view_menu.set_item_tooltip(idx, disabled_tip)


func _plants_overlay_ready() -> bool:
	var plants: Variant = MapState.features.get("plants", [])
	var has_regions := typeof(plants) == TYPE_ARRAY and not (plants as Array).is_empty()
	if not has_regions:
		return false
	var shell := _shell()
	if shell == null:
		return false
	var terrain: Object = shell.get("_terrain")
	if terrain == null:
		return false
	return (
		terrain.has_method("set_plants_overlay")
		or terrain.has_method("set_show_plants")
		or terrain.has_method("set_plants_visible")
	)


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
	if _more:
		_more.tooltip_text = "More"
	if _view:
		_view.tooltip_text = "View filters"
	if _variant:
		_variant.disabled = not session or _variant.item_count == 0
		_variant.tooltip_text = "Active variant (DM / _S / _ST / _SW)" if session else "Open a map first"
	_refresh_more()
	_refresh_view_menu()


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
		"Install into addon/ and launch via Steam. Polls BZLogger.txt for Sim Startup (8 = loaded). Press again to cancel the poll."
	)


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
	_set_more_item(pop, MORE_SCREENSHOT, not _busy, "Busy…")
	_set_more_item(pop, MORE_INSTALL, not _busy and session and root, "Needs an open map and a game install")
	_set_more_item(pop, MORE_PACK, not _busy and session, "Open a map first")
	var pub_ok := not _busy and session
	var pub_tip := "Busy…" if _busy else "Open a map first"
	_set_more_item(pop, MORE_PUBLISH, pub_ok, pub_tip)
	_set_more_item(pop, MORE_PROBE, not _busy, "Busy…")
	_set_more_item(pop, MORE_SAVE_AS, not _busy and session, "Open a map first")
	var hmap_ok := not _busy and session and MapState.has_heightmap()
	var hmap_tip := "Busy…" if _busy else ("Open a map first" if not session else "Map has no heightmap")
	_set_more_item(pop, MORE_EXPORT_HEIGHTMAP, hmap_ok, hmap_tip)
	_set_more_item(pop, MORE_IMPORT_HEIGHTMAP, hmap_ok, hmap_tip)
	_set_more_item(pop, MORE_HELP, true, "Keyboard reference  (%s)" % Keymap.format_action(Keymap.ACTION_HELP))
	_set_more_item(pop, MORE_PREFS, true, "Editor preferences")
	_refresh_scheme_menu()


func _set_more_item(pop: PopupMenu, id: int, enabled: bool, disabled_tip: String) -> void:
	var idx := pop.get_item_index(id)
	if idx < 0:
		return
	pop.set_item_disabled(idx, not enabled)
	pop.set_item_tooltip(idx, disabled_tip if not enabled else "")


func refresh_keymap() -> void:
	_refresh_scheme_menu()
	_refresh_map_button()
	_refresh_more()


func _refresh_scheme_menu() -> void:
	if _scheme_menu == null:
		return
	var scheme := Keymap.active_scheme()
	var godot_idx := _scheme_menu.get_item_index(MORE_SCHEME_GODOT)
	var gimp_idx := _scheme_menu.get_item_index(MORE_SCHEME_GIMP)
	if godot_idx >= 0:
		_scheme_menu.set_item_checked(godot_idx, scheme == Keymap.SCHEME_GODOT)
	if gimp_idx >= 0:
		_scheme_menu.set_item_checked(gimp_idx, scheme == Keymap.SCHEME_GIMP)


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
	if _more:
		EditorIcons.apply_button(_more, "more", false)
		_more.tooltip_text = "More"
	if _view:
		EditorIcons.apply_button(_view, "view", false)
		_view.tooltip_text = "View filters"
