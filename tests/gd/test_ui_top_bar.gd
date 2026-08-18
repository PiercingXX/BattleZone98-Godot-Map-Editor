extends RefCounted
## TopBar: session/busy/undo enablement, tools, variants, More menu.


func run(t) -> void:
	var saved_session := MapState.has_session
	var saved_root := Settings.game_root
	var saved_scheme := Settings.keymap_scheme
	var saved_scrap := Settings.view_scrap
	var saved_plants := Settings.view_plants
	var saved_field = MapState.field
	var saved_recent: Array[String] = []
	for recent_path in Settings.recent_maps:
		saved_recent.append(recent_path)
	UndoStack.clear()
	MapState.has_session = false
	MapState.field = HeightField.new()
	Settings.game_root = ""
	Settings.keymap_scheme = "godot"
	Settings.recent_maps.clear()

	var bar: Node = load("res://project/ui/top_bar/TopBar.tscn").instantiate()
	t.tree.root.add_child(bar)
	await t.tree.process_frame

	t.ok(_btn(bar, "Save").disabled, "Save disabled with no map")
	t.ok(_btn(bar, "Validate").disabled, "Validate disabled with no map")
	t.ok(_btn(bar, "Test") != null, "Test button exists")
	t.ok(_btn(bar, "Test").disabled, "Test disabled with no map")
	t.ok("map" in _btn(bar, "Test").tooltip_text.to_lower(), "Test tooltip says open a map")
	t.ok(_btn(bar, "Frame").disabled, "Frame disabled with no map")
	t.ok(_btn(bar, "MapMode") != null, "2D/3D toggle exists")
	t.ok(_btn(bar, "MapMode").disabled, "2D/3D disabled with no map")
	t.ok("map" in _btn(bar, "MapMode").tooltip_text.to_lower(), "2D/3D tooltip says open a map")
	t.eq(_btn(bar, "MapMode").text, "3D")
	t.ok(_btn(bar, "Undo").disabled, "Undo disabled when stack empty")
	t.ok(_btn(bar, "Redo").disabled, "Redo disabled when stack empty")
	t.ok(_btn(bar, "Open") is Button, "Open stays a Button")
	t.ok(not _btn(bar, "Open").disabled, "Open stays available")
	t.ok(not _btn(bar, "New").disabled, "New stays available")
	t.eq(_btn(bar, "Open").text, "Open", "Open keeps its label")
	t.eq(_btn(bar, "New").text, "New")
	t.eq(_btn(bar, "Save").text, "Save")
	t.eq(_btn(bar, "Validate").text, "Validate")
	t.ok(_btn(bar, "Open").icon != null, "Open has an icon")
	t.ok(_btn(bar, "Raise").icon != null, "tool row has icons")
	t.eq(_btn(bar, "Raise").text, "", "tool row is icon-only")
	t.eq(_btn(bar, "Qsel").text, "", "extra tools are icon-only")
	t.eq(_btn(bar, "Raise").theme_type_variation, "ToolButton")
	t.ok(_btn(bar, "Undo").icon != null and _btn(bar, "Undo").text == "")
	t.ok(_btn(bar, "Test").icon != null)
	t.eq(_btn(bar, "Test").text, "Test")
	t.ok((bar.find_child("Variant", true, false) as OptionButton).disabled, "variant empty/disabled")
	var more0: PopupMenu = (bar.find_child("More", true, false) as MenuButton).get_popup()
	t.eq(more0.get_item_text(more0.get_item_index(bar.MORE_PUBLISH)), "Publish for workshop…")
	t.ok(more0.is_item_disabled(more0.get_item_index(bar.MORE_PUBLISH)), "Publish needs a session")
	t.eq(more0.get_item_tooltip(more0.get_item_index(bar.MORE_PUBLISH)), "Open a map first")
	t.eq(more0.get_item_text(more0.get_item_index(bar.MORE_SCREENSHOT)), "Screenshot viewport")
	t.ok(not more0.is_item_disabled(more0.get_item_index(bar.MORE_SCREENSHOT)), "Screenshot stays available")
	t.eq(more0.get_item_text(more0.get_item_index(bar.MORE_PREFS)), "Preferences…")
	t.ok(not more0.is_item_disabled(more0.get_item_index(bar.MORE_PREFS)), "Preferences stays available")

	var tools: Array = []
	bar.tool_selected.connect(func(n): tools.append(n))
	_btn(bar, "Raise").pressed.emit()
	_btn(bar, "Place").pressed.emit()
	_btn(bar, "Noise").pressed.emit()
	_btn(bar, "Qsel").pressed.emit()
	_btn(bar, "Wand").pressed.emit()
	t.eq(tools, ["raise", "place", "noise", "qsel", "wand"], "tool buttons emit lower-case names")

	bar.set_tool("flatten")
	t.ok(_btn(bar, "Flatten").button_pressed, "set_tool flatten presses Flat")
	bar.set_tool("select")
	t.ok(_btn(bar, "Select").button_pressed, "set_tool select")
	bar.set_tool("rsel")
	t.ok(_btn(bar, "Rsel").button_pressed, "set_tool rsel")
	bar.set_tool("clone")
	t.ok(_btn(bar, "Clone").button_pressed, "set_tool clone")

	var framed := [0]
	bar.frame_requested.connect(func(): framed[0] += 1)
	_btn(bar, "Frame").pressed.emit()
	t.eq(framed[0], 0, "Frame no-ops without a session (button disabled; signal not relied on)")

	MapState.has_session = true
	MapState.session_changed.emit()
	t.ok(not _btn(bar, "Save").disabled, "Save enabled with session")
	t.ok(not _btn(bar, "Validate").disabled, "Validate enabled with session")
	t.ok(_btn(bar, "Test").disabled, "Test still needs a game install")
	t.ok("install" in _btn(bar, "Test").tooltip_text.to_lower() or "probe" in _btn(bar, "Test").tooltip_text.to_lower())
	t.ok(not _btn(bar, "Frame").disabled, "Frame enabled with session")
	t.ok(not _btn(bar, "MapMode").disabled, "2D/3D enabled with session")
	t.ok("KP 7" in _btn(bar, "MapMode").tooltip_text)
	var mapped := [0]
	bar.map_mode_requested.connect(func(): mapped[0] += 1)
	_btn(bar, "MapMode").pressed.emit()
	t.eq(mapped[0], 1, "2D/3D emits map_mode_requested")
	bar.set_map_mode(true)
	t.eq(_btn(bar, "MapMode").text, "2D")
	t.ok(_btn(bar, "MapMode").button_pressed)
	bar.set_map_mode(false)
	t.eq(_btn(bar, "MapMode").text, "3D")
	var more_early: PopupMenu = (bar.find_child("More", true, false) as MenuButton).get_popup()
	t.ok(more_early.is_item_disabled(more_early.get_item_index(bar.MORE_EXPORT_HEIGHTMAP)), "Export heightmap needs a grid")
	t.eq(more_early.get_item_tooltip(more_early.get_item_index(bar.MORE_EXPORT_HEIGHTMAP)), "Map has no heightmap")
	var hfield := HeightField.new()
	hfield.grid_x = 4
	hfield.grid_z = 4
	hfield.heights.resize(16)
	hfield.heights.fill(200)
	MapState.field = hfield
	bar._refresh_more()

	_btn(bar, "Frame").pressed.emit()
	t.eq(framed[0], 1, "Frame emits when a map is open")

	bar.fill_variants(["", "_S", "_ST", "_SW"], "_S")
	t.eq(bar.selected_variant(), "_S")
	var variant: OptionButton = bar.find_child("Variant", true, false)
	t.ok(not variant.disabled)
	t.eq(variant.get_item_text(0), "DM (0)")
	t.eq(variant.get_item_text(1), "_S (0)")
	var saw_variant := [false]
	bar.variant_changed.connect(func(): saw_variant[0] = true)
	variant.select(2)
	variant.item_selected.emit(2)
	t.ok(saw_variant[0], "variant dropdown emits")
	t.eq(bar.selected_variant(), "_ST")

	UndoStack.push(_Nop.new())
	t.ok(not _btn(bar, "Undo").disabled, "Undo enables after push")
	t.ok(_btn(bar, "Redo").disabled)
	UndoStack.undo()
	t.ok(_btn(bar, "Undo").disabled)
	t.ok(not _btn(bar, "Redo").disabled, "Redo enables after undo")

	bar.set_busy(true)
	t.ok(_btn(bar, "Open").disabled, "Open disabled while busy")
	t.ok(_btn(bar, "Save").disabled, "Save disabled while busy")
	t.ok(_btn(bar, "New").disabled, "New disabled while busy")
	t.ok(_btn(bar, "Test").disabled, "Test disabled while busy (not already running)")
	bar.set_testing(true)
	t.ok(not _btn(bar, "Test").disabled, "Test stays clickable to cancel")
	t.ok("cancel" in _btn(bar, "Test").tooltip_text.to_lower())
	bar.set_testing(false)
	bar.set_busy(false)
	t.ok(not _btn(bar, "Save").disabled, "Save re-enabled after busy, session still open")

	var pop: PopupMenu = (bar.find_child("More", true, false) as MenuButton).get_popup()
	t.ok(pop.is_item_disabled(pop.get_item_index(bar.MORE_IMPORT)), "Import disabled without game_root")
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_RENDER)), "Render enabled with session")
	t.ok(pop.is_item_disabled(pop.get_item_index(bar.MORE_INSTALL)), "Install needs game_root")
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_PACK)))
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_PUBLISH)), "Publish enabled with session")
	bar.set_busy(true)
	t.ok(pop.is_item_disabled(pop.get_item_index(bar.MORE_PUBLISH)), "Publish disabled while busy")
	t.eq(pop.get_item_tooltip(pop.get_item_index(bar.MORE_PUBLISH)), "Busy…")
	bar.set_busy(false)
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_SAVE_AS)))
	t.eq(pop.get_item_text(pop.get_item_index(bar.MORE_EXPORT_HEIGHTMAP)), "Export heightmap PNG…")
	t.eq(pop.get_item_text(pop.get_item_index(bar.MORE_IMPORT_HEIGHTMAP)), "Import heightmap PNG…")
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_EXPORT_HEIGHTMAP)), "Export heightmap enabled with grid")
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_IMPORT_HEIGHTMAP)), "Import heightmap enabled with grid")
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_HELP)))

	Settings.game_root = "/tmp/fake-bz"
	bar._refresh_actions()
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_IMPORT)), "Import enables with game_root")
	t.ok(not pop.is_item_disabled(pop.get_item_index(bar.MORE_INSTALL)), "Install enables with session+root")
	t.ok(not _btn(bar, "Test").disabled, "Test enables with session+root")
	var tested := [0]
	bar.test_requested.connect(func(): tested[0] += 1)
	_btn(bar, "Test").pressed.emit()
	t.eq(tested[0], 1, "Test emits test_requested")

	var more_ids: Array = []
	var save_as := [0]
	bar.more_selected.connect(func(id): more_ids.append(id))
	bar.save_as_requested.connect(func(): save_as[0] += 1)
	pop.id_pressed.emit(bar.MORE_PROBE)
	pop.id_pressed.emit(bar.MORE_SAVE_AS)
	t.eq(more_ids, [bar.MORE_PROBE], "Save As is intercepted")
	t.eq(save_as[0], 1)
	pop.id_pressed.emit(bar.MORE_PREFS)
	t.eq(more_ids, [bar.MORE_PROBE, bar.MORE_PREFS], "Preferences emits more_selected")

	var has_scheme := false
	for i in pop.item_count:
		if pop.get_item_text(i) == "Keyboard scheme":
			has_scheme = true
	t.ok(has_scheme, "More menu lists Keyboard scheme")
	var scheme_menu: PopupMenu = bar.find_child("KeymapScheme", true, false)
	t.ok(scheme_menu != null, "More owns a Keyboard scheme submenu")
	t.ok(scheme_menu.get_item_index(bar.MORE_SCHEME_GODOT) >= 0)
	t.ok(scheme_menu.get_item_index(bar.MORE_SCHEME_GIMP) >= 0)
	bar.refresh_keymap()
	t.ok(scheme_menu.is_item_checked(scheme_menu.get_item_index(bar.MORE_SCHEME_GODOT)), "Godot checked by default")
	t.ok(not scheme_menu.is_item_checked(scheme_menu.get_item_index(bar.MORE_SCHEME_GIMP)))
	Settings.keymap_scheme = "gimp"
	bar.refresh_keymap()
	t.ok(scheme_menu.is_item_checked(scheme_menu.get_item_index(bar.MORE_SCHEME_GIMP)), "GIMP checks after scheme flip")
	t.ok(not scheme_menu.is_item_checked(scheme_menu.get_item_index(bar.MORE_SCHEME_GODOT)))
	t.eq(_btn(bar, "Raise").tooltip_text, "Raise  (W)", "tooltips follow the active scheme")
	scheme_menu.id_pressed.emit(bar.MORE_SCHEME_GODOT)
	t.eq(more_ids, [bar.MORE_PROBE, bar.MORE_SCHEME_GODOT], "scheme submenu emits more_selected")
	Settings.keymap_scheme = "godot"
	bar.refresh_keymap()
	t.eq(_btn(bar, "Raise").tooltip_text, "Raise  (2)")

	var view: MenuButton = bar.find_child("View", true, false)
	t.ok(view != null, "View menu sits next to More")
	var view_pop: PopupMenu = view.get_popup()
	t.ok(view_pop.get_item_index(bar.VIEW_GEYSERS) >= 0)
	t.ok(view_pop.get_item_index(bar.VIEW_UNITS) >= 0)
	t.ok(view_pop.is_item_disabled(view_pop.get_item_index(bar.VIEW_PLANTS)))
	t.eq(view_pop.get_item_tooltip(view_pop.get_item_index(bar.VIEW_PLANTS)), "no plant regions")

	var menu: PopupMenu = bar.find_child("OpenMenu", true, false)
	t.ok(menu != null, "Open owns a recent-maps menu")
	bar.refresh_open_menu()
	t.eq(menu.get_item_text(0), "Browse…")
	t.eq(menu.get_item_id(0), bar.OPEN_BROWSE_ID)
	t.eq(menu.get_item_text(1), "Gallery…")
	t.eq(menu.get_item_id(1), bar.OPEN_GALLERY_ID)
	t.eq(menu.item_count, 2, "Browse… and Gallery… when no recents")
	var browsed := [0]
	bar.open_requested.connect(func(): browsed[0] += 1)
	menu.id_pressed.emit(bar.OPEN_BROWSE_ID)
	t.eq(browsed[0], 1, "Browse… keeps open_requested")
	var gallery_opens := [0]
	bar.gallery_requested.connect(func(): gallery_opens[0] += 1)
	menu.id_pressed.emit(bar.OPEN_GALLERY_ID)
	t.eq(gallery_opens[0], 1, "Gallery… emits gallery_requested")

	var tmp := OS.get_temp_dir().path_join("bz_topbar_recent_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var keep := tmp.path_join("keep.trn")
	var gone := tmp.path_join("gone.trn")
	var kf := FileAccess.open(keep, FileAccess.WRITE)
	kf.store_string("x")
	kf.close()
	Settings.recent_maps.clear()
	Settings.recent_maps.append(keep)
	Settings.recent_maps.append(gone)
	bar.refresh_open_menu()
	var keep_id := 2
	var gone_id := 3
	var keep_idx := menu.get_item_index(keep_id)
	var gone_idx := menu.get_item_index(gone_id)
	t.eq(menu.get_item_text(keep_idx), "keep.trn")
	t.ok(not menu.is_item_disabled(keep_idx), "existing recent is enabled")
	t.eq(menu.get_item_text(gone_idx), "gone.trn")
	t.ok(menu.is_item_disabled(gone_idx), "missing recent is disabled")
	t.eq(menu.get_item_tooltip(gone_idx), "file moved")
	var recents: Array = []
	bar.recent_open_requested.connect(func(p): recents.append(p))
	menu.id_pressed.emit(keep_id)
	t.eq(recents, [keep], "existing recent emits path")
	menu.id_pressed.emit(gone_id)
	t.eq(recents.size(), 1, "missing recent does not emit")

	bar.set_busy(true)
	t.eq(_btn(bar, "Open").tooltip_text, "Busy…")
	bar.set_busy(false)

	bar.queue_free()
	await t.tree.process_frame
	DirAccess.remove_absolute(keep)
	DirAccess.remove_absolute(tmp)
	UndoStack.clear()
	MapState.has_session = saved_session
	MapState.field = saved_field
	Settings.game_root = saved_root
	Settings.keymap_scheme = saved_scheme
	Settings.view_scrap = saved_scrap
	Settings.view_plants = saved_plants
	Settings.recent_maps.clear()
	for recent_path in saved_recent:
		Settings.recent_maps.append(recent_path)


func _btn(root: Node, name: String) -> Button:
	return root.find_child(name, true, false) as Button


class _Nop:
	extends RefCounted
	func do() -> void:
		pass
	func undo() -> void:
		pass
