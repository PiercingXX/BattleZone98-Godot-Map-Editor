extends RefCounted
## Rebindable keymap: the action registry, user overrides on disk, conflict
## reporting, reset-to-default, and the Preferences rebinding surface.


func run(t) -> void:
	var snap := _snapshot()
	Settings.keymap_scheme = Keymap.SCHEME_GODOT
	Keymap.reset_every_scheme()

	_registry(t)
	_extensible(t)
	_round_trip(t)
	_per_scheme(t)
	_conflicts(t)
	_reset(t)
	_junk(t)
	await _prefs_ui(t)

	_restore(snap)


func _registry(t) -> void:
	var ids := KeymapRegistry.ids()
	t.ok(ids.size() >= Keymap.ALL_ACTIONS.size(), "registry covers the shipped set")
	for action in Keymap.ALL_ACTIONS:
		t.ok(KeymapRegistry.has_action(str(action)), "registry knows %s" % action)
		var entry := KeymapRegistry.get_action(str(action))
		t.ok(not entry.label.is_empty(), "%s has a label" % action)
		t.ok(not entry.tooltip.is_empty(), "%s has a tooltip" % action)
		t.ok(not entry.category.is_empty(), "%s has a category" % action)
	var cats := KeymapRegistry.categories()
	t.ok(cats.has(KeymapRegistry.CAT_TOOLS))
	t.ok(cats.has(KeymapRegistry.CAT_BOOKMARKS))
	t.eq(
		KeymapRegistry.ids_in(KeymapRegistry.CAT_TOOLS).size(),
		Keymap.TOOL_ACTIONS.size(), "every shipped tool is seeded",
	)
	t.eq(KeymapRegistry.ids_in(KeymapRegistry.CAT_TEAMS).size(), 8)
	# Both shipped schemes still bind every shipped action, unchanged.
	for scheme in [Keymap.SCHEME_GODOT, Keymap.SCHEME_GIMP]:
		var table := KeymapRegistry.defaults_for(scheme)
		for action in Keymap.ALL_ACTIONS:
			t.ok(table.has(str(action)), "%s default binds %s" % [scheme, action])
		t.eq(Keymap.find_conflicts_in(table).size(), 0, "%s ships clean" % scheme)
	t.eq(
		KeyAction.format_chord(Keymap.default_binding("undo", Keymap.SCHEME_GODOT)),
		"Ctrl+Z",
	)
	t.eq(
		KeyAction.format_chord(Keymap.default_binding("tool.lower", Keymap.SCHEME_GIMP)),
		"Shift+W",
	)


func _extensible(t) -> void:
	# What a new tool or the command palette does at load time.
	KeymapRegistry.register(
		"test.palette", "Test palette", "Registered by the test",
		KeymapRegistry.CAT_SESSION, KeyAction.chord(KEY_J, true),
		{Keymap.SCHEME_GIMP: KeyAction.chord(KEY_J, false, true)},
	)
	t.ok("test.palette" in Keymap.all_actions(), "registry list is open")
	t.ok(not ("test.palette" in Keymap.ALL_ACTIONS), "the constant stays the shipped set")
	t.eq(Keymap.resolve(_key(KEY_J, true), Keymap.SCHEME_GODOT), "test.palette")
	t.eq(Keymap.resolve(_key(KEY_J, false, true), Keymap.SCHEME_GIMP), "test.palette")
	t.eq(Keymap.action_label("test.palette"), "Test palette")
	t.eq(Keymap.action_category("test.palette"), KeymapRegistry.CAT_SESSION)
	t.ok("test.palette" in Keymap.actions_in(KeymapRegistry.CAT_SESSION))
	KeymapRegistry.unregister("test.palette")
	t.ok(not ("test.palette" in Keymap.all_actions()), "unregister removes the row")
	t.eq(Keymap.resolve(_key(KEY_J, true), Keymap.SCHEME_GODOT), "", "and its chord")


func _round_trip(t) -> void:
	var s := Keymap.SCHEME_GODOT
	t.ok(Keymap.set_binding("tool.raise", Keymap.make_binding(KEY_J), s))
	t.ok(Keymap.has_override("tool.raise", s))
	t.eq(Keymap.format_action("tool.raise", s), "J")
	t.eq(Keymap.resolve(_key(KEY_J), s), "tool.raise", "the override resolves")
	t.eq(Keymap.resolve(_key(KEY_2), s), "", "the shipped chord is free again")
	t.ok(FileAccess.file_exists(KeymapStore.PATH), "an override writes the config dir")

	# Survive a full trip through the file, as a restart would.
	Keymap.reload_overrides()
	t.eq(Keymap.format_action("tool.raise", s), "J", "override survives a reload")
	t.eq(Keymap.resolve(_key(KEY_J), s), "tool.raise")
	var on_disk := KeymapStore.load_overrides()
	t.ok(on_disk.has(s))
	t.eq(int(on_disk[s]["tool.raise"]["keycode"]), KEY_J)

	# Rebinding back to the shipped chord drops the override rather than
	# pinning today's default forever.
	t.ok(Keymap.set_binding("tool.raise", Keymap.make_binding(KEY_2), s))
	t.ok(not Keymap.has_override("tool.raise", s), "back to stock clears the override")
	t.eq(Keymap.resolve(_key(KEY_2), s), "tool.raise")

	t.ok(not Keymap.set_binding("nope.nothing", Keymap.make_binding(KEY_J), s),
		"unknown actions are rejected")


func _per_scheme(t) -> void:
	Keymap.set_binding("frame", Keymap.make_binding(KEY_Y), Keymap.SCHEME_GODOT)
	t.eq(Keymap.format_action("frame", Keymap.SCHEME_GODOT), "Y")
	t.eq(Keymap.format_action("frame", Keymap.SCHEME_GIMP), "F", "gimp keeps its own")
	t.ok(not Keymap.has_override("frame", Keymap.SCHEME_GIMP))
	Keymap.reset_binding("frame", Keymap.SCHEME_GODOT)
	t.eq(Keymap.format_action("frame", Keymap.SCHEME_GODOT), "F")


func _conflicts(t) -> void:
	var s := Keymap.SCHEME_GODOT
	var clash := Keymap.conflicts_with("undo", Keymap.make_binding(KEY_S, true), s)
	t.eq(clash.size(), 1, "Ctrl+S is taken")
	t.eq(str(clash[0]), "save")
	var text := Keymap.conflict_text("undo", Keymap.make_binding(KEY_S, true), s)
	t.ok("Ctrl+S" in text, "the clash names the chord")
	t.ok("Save" in text, "the clash names the action it would steal")
	t.ok("Session" in text, "and where to find it")
	t.eq(Keymap.conflict_text("undo", Keymap.make_binding(KEY_J, true, true), s), "",
		"a free chord reports nothing")
	t.eq(Keymap.conflicts_with("save", Keymap.make_binding(KEY_S, true), s).size(), 0,
		"an action does not clash with itself")

	# Cleared bindings own no chord, so two of them are not a clash.
	t.ok(Keymap.unbind("walk", s))
	t.eq(Keymap.format_action("walk", s), "Unassigned")
	t.eq(Keymap.resolve(_key(KEY_V), s), "", "a cleared action stops resolving")
	t.ok(Keymap.unbind("grid", s))
	t.eq(Keymap.find_conflicts(s).size(), 0, "two cleared actions are not a conflict")
	Keymap.reset_binding("walk", s)
	Keymap.reset_binding("grid", s)
	t.eq(Keymap.resolve(_key(KEY_V), s), "walk")


func _reset(t) -> void:
	var s := Keymap.SCHEME_GODOT
	Keymap.set_binding("tool.paint", Keymap.make_binding(KEY_Y), s)
	Keymap.set_binding("tool.place", Keymap.make_binding(KEY_X), s)
	Keymap.set_binding("tool.paint", Keymap.make_binding(KEY_Y), Keymap.SCHEME_GIMP)
	t.eq(Keymap.overrides_for(s).size(), 2)
	Keymap.reset_binding("tool.paint", s)
	t.eq(Keymap.overrides_for(s).size(), 1, "per-action reset drops one row")
	t.eq(Keymap.format_action("tool.paint", s), "7")
	Keymap.reset_all(s)
	t.eq(Keymap.overrides_for(s).size(), 0, "reset-all clears the scheme")
	t.eq(Keymap.overrides_for(Keymap.SCHEME_GIMP).size(), 1, "the other scheme survives")
	Keymap.reset_every_scheme()
	t.eq(Keymap.overrides_for(Keymap.SCHEME_GIMP).size(), 0)
	t.ok(not FileAccess.file_exists(KeymapStore.PATH), "stock means no file at all")
	for action in Keymap.ALL_ACTIONS:
		var bind := Keymap.binding_for(str(action), s)
		t.ok(KeyAction.is_bound(bind), "%s is bound again" % action)


func _junk(t) -> void:
	t.eq(KeymapStore.coerce_table("nonsense").size(), 0)
	t.eq(KeymapStore.coerce_table({"a": 7}).size(), 0, "non-chord values are dropped")
	t.eq(KeymapStore.coerce_table({"a": {"keycode": KEY_J}}).size(), 1)
	t.eq(KeyAction.coerce_chord({"ctrl": true}).size(), 0, "a chord needs a keycode")
	t.ok(not KeyAction.is_bound(KeyAction.chord(KeyAction.UNBOUND)))
	t.ok(KeyAction.is_modifier_key(KEY_SHIFT))
	t.ok(not KeyAction.is_modifier_key(KEY_S))


func _prefs_ui(t) -> void:
	var s := Keymap.SCHEME_GODOT
	Settings.keymap_scheme = s
	var dlg: Node = load("res://project/ui/prefs/PrefsDialog.tscn").instantiate()
	t.tree.root.add_child(dlg)
	await t.tree.process_frame
	dlg.refresh()

	var tree: Tree = dlg.find_child("Bindings", true, false)
	t.ok(tree is Tree, "Preferences lists the bindings")
	t.ok(dlg.find_child("RebindKey", true, false) is Button)
	t.ok(dlg.find_child("ResetAllKeys", true, false) is Button)
	t.ok(dlg.find_child("FontSize", true, false) is HSlider)
	t.eq(_row_shortcut(tree, "tool.raise"), "2", "rows show the live chord")
	t.ok(_row_count(tree) >= Keymap.ALL_ACTIONS.size(), "every action gets a row")

	# A free chord binds straight away.
	_select(tree, "tool.raise")
	dlg._begin_capture()
	dlg._capture_key(_key(KEY_J))
	t.eq(Keymap.format_action("tool.raise", s), "J", "capture rebinds")
	t.eq(_row_shortcut(tree, "tool.raise"), "J", "and the list redraws")

	# A modifier alone is not a chord; Esc backs out.
	dlg._begin_capture()
	dlg._capture_key(_key(KEY_SHIFT))
	t.eq(Keymap.format_action("tool.raise", s), "J", "a lone modifier is ignored")
	dlg._capture_key(_key(KEY_ESCAPE))
	t.ok("cancel" in dlg.binding_status(), "Esc cancels the capture")
	t.eq(Keymap.format_action("tool.raise", s), "J")

	# A taken chord names its owner instead of silently winning.
	_select(tree, "tool.lower")
	dlg._begin_capture()
	dlg._capture_key(_key(KEY_J))
	t.ok("already" in dlg.binding_status(), "the clash is reported")
	t.ok("Raise" in dlg.binding_status(), "and names what it would steal")
	t.eq(Keymap.format_action("tool.lower", s), "3", "nothing changed yet")
	dlg._cancel_pending()
	t.eq(Keymap.format_action("tool.lower", s), "3", "cancel leaves both alone")

	dlg._begin_capture()
	dlg._capture_key(_key(KEY_J))
	dlg._confirm_pending()
	t.eq(Keymap.format_action("tool.lower", s), "J", "reassign takes the chord")
	t.eq(Keymap.format_action("tool.raise", s), "Unassigned", "the loser is cleared")
	t.eq(Keymap.find_conflicts(s).size(), 0, "no chord ends up owned twice")

	# Per-action reset, then the whole scheme.
	_select(tree, "tool.raise")
	dlg._reset_selected()
	t.eq(Keymap.format_action("tool.raise", s), "2")
	dlg._reset_all_bindings()
	t.eq(Keymap.format_action("tool.lower", s), "3", "reset all restores the scheme")
	t.eq(Keymap.overrides_for(s).size(), 0)

	# Clear leaves the action listed but unbound.
	_select(tree, "tool.clone")
	dlg._clear_selected()
	t.eq(_row_shortcut(tree, "tool.clone"), "Unassigned")
	dlg._reset_selected()
	t.eq(_row_shortcut(tree, "tool.clone"), "C")

	# Font size moves on its own; UI scale does not follow.
	var before_scale := Settings.ui_scale
	var font: HSlider = dlg.find_child("FontSize", true, false)
	font.value = 18
	t.eq(Settings.ui_font_size, 18, "the slider writes Settings")
	t.eq(Settings.ui_scale, before_scale, "font size does not touch ui scale")
	t.eq(DarkTheme.make().default_font_size, 18, "and the theme follows")

	dlg.queue_free()
	await t.tree.process_frame


func _select(tree: Tree, action: String) -> void:
	var item := _find_row(tree, action)
	if item != null:
		item.select(0)


func _row_shortcut(tree: Tree, action: String) -> String:
	var item := _find_row(tree, action)
	return item.get_text(1) if item != null else ""


func _find_row(tree: Tree, action: String) -> TreeItem:
	var root := tree.get_root()
	if root == null:
		return null
	var head := root.get_first_child()
	while head != null:
		var row := head.get_first_child()
		while row != null:
			if str(row.get_metadata(0)) == action:
				return row
			row = row.get_next()
		head = head.get_next()
	return null


func _row_count(tree: Tree) -> int:
	var n := 0
	var root := tree.get_root()
	if root == null:
		return 0
	var head := root.get_first_child()
	while head != null:
		var row := head.get_first_child()
		while row != null:
			n += 1
			row = row.get_next()
		head = head.get_next()
	return n


func _key(keycode: int, ctrl: bool = false, shift: bool = false, alt: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	return ev


func _snapshot() -> Dictionary:
	var keymap_cfg: Variant = null
	if FileAccess.file_exists(KeymapStore.PATH):
		keymap_cfg = FileAccess.get_file_as_string(KeymapStore.PATH)
	var settings_cfg: Variant = null
	if FileAccess.file_exists(Settings.PATH):
		settings_cfg = FileAccess.get_file_as_string(Settings.PATH)
	return {
		"keymap_cfg": keymap_cfg,
		"settings_cfg": settings_cfg,
		"scheme": Settings.keymap_scheme,
		"font": Settings.ui_font_size,
		"ui_scale": Settings.ui_scale,
	}


func _restore(snap: Dictionary) -> void:
	Keymap.reset_every_scheme()
	if snap["keymap_cfg"] != null:
		var f := FileAccess.open(KeymapStore.PATH, FileAccess.WRITE)
		if f:
			f.store_string(str(snap["keymap_cfg"]))
			f.close()
	Keymap.reload_overrides()
	Settings.keymap_scheme = str(snap["scheme"])
	Settings.ui_font_size = int(snap["font"])
	Settings.ui_scale = float(snap["ui_scale"])
	if snap["settings_cfg"] == null:
		if FileAccess.file_exists(Settings.PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
		Settings._cfg = ConfigFile.new()
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		if f:
			f.store_string(str(snap["settings_cfg"]))
			f.close()
		Settings._load()
