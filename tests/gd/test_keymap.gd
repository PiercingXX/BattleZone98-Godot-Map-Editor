extends RefCounted
## Keymap schemes: resolve(), conflict check, Settings persistence.


func run(t) -> void:
	var snap := _snapshot_settings()
	Settings.keymap_scheme = "godot"

	_resolve_godot(t)
	_resolve_gimp(t)
	_conflicts(t)
	_help_text(t)
	_persist(t)

	_restore_settings(snap)


func _resolve_godot(t) -> void:
	var s := Keymap.SCHEME_GODOT
	t.eq(Keymap.resolve(_key(KEY_1), s), "tool.fly")
	t.eq(Keymap.resolve(_key(KEY_2), s), "tool.raise")
	t.eq(Keymap.resolve(_key(KEY_3), s), "tool.lower")
	t.eq(Keymap.resolve(_key(KEY_4), s), "tool.flatten")
	t.eq(Keymap.resolve(_key(KEY_5), s), "tool.smooth")
	t.eq(Keymap.resolve(_key(KEY_6), s), "tool.ramp")
	t.eq(Keymap.resolve(_key(KEY_7), s), "tool.paint")
	t.eq(Keymap.resolve(_key(KEY_8), s), "tool.place")
	t.eq(Keymap.resolve(_key(KEY_9), s), "tool.select")
	t.eq(Keymap.resolve(_key(KEY_0), s), "tool.noise")
	t.eq(Keymap.resolve(_key(KEY_B), s), "tool.qsel")
	t.eq(Keymap.resolve(_key(KEY_R), s), "tool.rsel")
	t.eq(Keymap.resolve(_key(KEY_U), s), "tool.wand")
	t.eq(Keymap.resolve(_key(KEY_C), s), "tool.clone")
	t.eq(Keymap.resolve(_key(KEY_A, true), s), "select.all")
	t.eq(Keymap.resolve(_key(KEY_D, true), s), "select.none")
	t.eq(Keymap.resolve(_key(KEY_I, true, true), s), "select.invert")
	t.eq(Keymap.resolve(_key(KEY_F), s), "frame")
	t.eq(Keymap.resolve(_key(KEY_SPACE), s), "top_down")
	t.eq(Keymap.resolve(_key(KEY_KP_7), s), "map_mode")
	t.eq(Keymap.format_action("map_mode", s), "KP 7")
	t.eq(Keymap.resolve(_key(KEY_H), s), "slope_overlay")
	t.eq(Keymap.resolve(_key(KEY_G), s), "grid")
	t.eq(Keymap.resolve(_key(KEY_V), s), "walk")
	t.eq(Keymap.resolve(_key(KEY_F1), s), "help")
	t.eq(Keymap.resolve(_key(KEY_TAB), s), "focus")
	t.eq(Keymap.format_action("focus", s), "Tab")
	t.eq(Keymap.resolve(_key(KEY_Z, true), s), "undo")
	t.eq(Keymap.resolve(_key(KEY_Z, true, true), s), "redo")
	t.eq(Keymap.resolve(_key(KEY_S, true), s), "save")
	t.eq(Keymap.resolve(_key(KEY_0, false, true), s), "team.0")
	t.eq(Keymap.resolve(_key(KEY_7, false, true), s), "team.7")
	t.eq(Keymap.format_action("team.2", s), "Shift+2")
	t.eq(Keymap.resolve(_key(KEY_1, true, false, true), s), "bookmark.store.1")
	t.eq(Keymap.resolve(_key(KEY_5, true, false, true), s), "bookmark.store.5")
	t.eq(Keymap.resolve(_key(KEY_1, false, false, true), s), "bookmark.recall.1")
	t.eq(Keymap.resolve(_key(KEY_4, false, false, true), s), "bookmark.recall.4")
	t.eq(Keymap.format_action("bookmark.store.2", s), "Ctrl+Alt+2")
	t.eq(Keymap.format_action("bookmark.recall.3", s), "Alt+3")
	t.eq(Keymap.resolve(_key(KEY_F, true), s), "", "Ctrl+F is not frame")
	t.eq(Keymap.resolve(_key(KEY_ESCAPE), s), "", "Escape is not a godot binding")
	t.eq(Keymap.resolve(_key(KEY_W), s), "", "W is not a godot tool")
	t.eq(Keymap.resolve(InputEventMouseButton.new(), s), "", "non-key is empty")
	t.eq(Keymap.format_action("undo", s), "Ctrl+Z")
	t.eq(Keymap.format_action("redo", s), "Ctrl+Shift+Z")
	t.eq(Keymap.format_action("save", s), "Ctrl+S")


func _resolve_gimp(t) -> void:
	var s := Keymap.SCHEME_GIMP
	t.eq(Keymap.resolve(_key(KEY_ESCAPE), s), "tool.fly")
	t.eq(Keymap.resolve(_key(KEY_W), s), "tool.raise")
	t.eq(Keymap.resolve(_key(KEY_W, false, true), s), "tool.lower")
	t.eq(Keymap.resolve(_key(KEY_F, false, true), s), "tool.flatten")
	t.eq(Keymap.resolve(_key(KEY_U, false, true), s), "tool.smooth")
	t.eq(Keymap.resolve(_key(KEY_K), s), "tool.ramp")
	t.eq(Keymap.resolve(_key(KEY_P), s), "tool.paint")
	t.eq(Keymap.resolve(_key(KEY_I), s), "tool.place")
	t.eq(Keymap.resolve(_key(KEY_M), s), "tool.select")
	t.eq(Keymap.resolve(_key(KEY_N), s), "tool.noise")
	t.eq(Keymap.resolve(_key(KEY_Q), s), "tool.qsel", "GIMP Quick Mask analog")
	t.eq(Keymap.resolve(_key(KEY_R), s), "tool.rsel", "GIMP Rectangle Select")
	t.eq(Keymap.resolve(_key(KEY_U), s), "tool.wand", "GIMP Fuzzy Select")
	t.eq(Keymap.resolve(_key(KEY_C), s), "tool.clone", "GIMP Clone")
	t.eq(Keymap.resolve(_key(KEY_A, true), s), "select.all")
	t.eq(Keymap.resolve(_key(KEY_D, true), s), "select.none")
	t.eq(Keymap.resolve(_key(KEY_I, true, true), s), "select.invert")
	t.eq(Keymap.resolve(_key(KEY_1), s), "", "number row is not a gimp tool")
	t.eq(Keymap.resolve(_key(KEY_R, false, true), s), "", "Shift+R stays rotate-selection")
	t.eq(Keymap.resolve(_key(KEY_F), s), "frame", "F still frames")
	t.eq(Keymap.resolve(_key(KEY_SPACE), s), "top_down")
	t.eq(Keymap.resolve(_key(KEY_KP_7), s), "map_mode", "gimp keeps KP 7")
	t.eq(Keymap.resolve(_key(KEY_H), s), "slope_overlay")
	t.eq(Keymap.resolve(_key(KEY_G), s), "grid")
	t.eq(Keymap.resolve(_key(KEY_V), s), "walk")
	t.eq(Keymap.resolve(_key(KEY_F1), s), "help")
	t.eq(Keymap.resolve(_key(KEY_TAB), s), "focus", "gimp keeps Tab focus")
	t.eq(Keymap.resolve(_key(KEY_Z, true), s), "undo")
	t.eq(Keymap.resolve(_key(KEY_Z, true, true), s), "redo")
	t.eq(Keymap.resolve(_key(KEY_S, true), s), "save")
	t.eq(Keymap.resolve(_key(KEY_0, false, true), s), "team.0", "gimp keeps Shift+0 team")
	t.eq(Keymap.resolve(_key(KEY_3, false, true), s), "team.3")
	t.eq(Keymap.resolve(_key(KEY_2, true, false, true), s), "bookmark.store.2", "gimp keeps bookmarks")
	t.eq(Keymap.resolve(_key(KEY_5, false, false, true), s), "bookmark.recall.5")
	t.eq(Keymap.format_action("tool.lower", s), "Shift+W")
	t.eq(Keymap.format_action("tool.smooth", s), "Shift+U")
	t.eq(Keymap.format_action("tool.fly", s), "Esc")


func _conflicts(t) -> void:
	t.eq(Keymap.find_conflicts(Keymap.SCHEME_GODOT).size(), 0, "godot has no clashes")
	t.eq(Keymap.find_conflicts(Keymap.SCHEME_GIMP).size(), 0, "gimp has no clashes")
	for scheme in [Keymap.SCHEME_GODOT, Keymap.SCHEME_GIMP]:
		var table := Keymap.bindings_for(scheme)
		for action in Keymap.ALL_ACTIONS:
			t.ok(table.has(action), "%s binds %s" % [scheme, action])
	var boom := {
		"tool.fly": Keymap.make_binding(KEY_F),
		"frame": Keymap.make_binding(KEY_F),
	}
	var found: Array = Keymap.find_conflicts_in(boom)
	t.eq(found.size(), 1, "detector reports a tool vs non-tool clash")
	var actions: PackedStringArray = found[0].get("actions", PackedStringArray())
	t.ok("tool.fly" in actions and "frame" in actions)
	var clean := {
		"tool.fly": Keymap.make_binding(KEY_ESCAPE),
		"frame": Keymap.make_binding(KEY_F),
	}
	t.eq(Keymap.find_conflicts_in(clean).size(), 0, "distinct chords are clean")


func _help_text(t) -> void:
	var godot_help := Keymap.help_text(Keymap.SCHEME_GODOT)
	t.ok("Scheme: Godot" in godot_help)
	t.ok("9 select" in godot_help)
	t.ok("B qsel" in godot_help)
	t.ok("R rsel" in godot_help)
	t.ok("U wand" in godot_help)
	t.ok("Ctrl+A" in godot_help)
	t.ok("G grid" in godot_help)
	t.ok("Ctrl+Z" in godot_help)
	t.ok("Tab focus" in godot_help, "help lists focus mode")
	t.ok("2D/3D" in godot_help, "help lists map mode")
	t.ok("KP 7" in godot_help, "help lists numpad 7")
	t.ok("Shift+0" in godot_help, "help lists team assign")
	t.ok("Alt+1" in godot_help, "help lists camera bookmarks")
	t.ok("measure" in godot_help)
	t.ok("30s" in godot_help)
	var gimp_help := Keymap.help_text(Keymap.SCHEME_GIMP)
	t.ok("Scheme: GIMP" in gimp_help)
	t.ok("M select" in gimp_help)
	t.ok("Q qsel" in gimp_help)
	t.ok("R rsel" in gimp_help)
	t.ok("U wand" in gimp_help)
	t.ok("Shift+W" in gimp_help)
	t.ok("9 select" in gimp_help, "other-scheme line still lists Godot 9 select")


func _persist(t) -> void:
	t.eq(Keymap.normalize_scheme(""), "godot")
	t.eq(Keymap.normalize_scheme("GIMP"), "gimp")
	t.eq(Keymap.normalize_scheme("Blender"), "godot")
	Settings.keymap_scheme = "godot"
	t.eq(Keymap.active_scheme(), "godot")
	Settings.keymap_scheme = "gimp"
	Settings.save()
	t.eq(Keymap.active_scheme(), "gimp")
	Settings.keymap_scheme = "godot"
	t.eq(Settings.keymap_scheme, "godot", "in-memory flip before reload")
	Settings._load()
	t.eq(Settings.keymap_scheme, "gimp", "gimp persists across save/_load")
	t.eq(Keymap.active_scheme(), "gimp")
	Settings.keymap_scheme = "maya"
	Settings.save()
	t.eq(Settings.keymap_scheme, "godot", "save coerces unknown schemes")
	Settings._cfg.set_value("input", "keymap_scheme", "blender")
	Settings._cfg.save(Settings.PATH)
	Settings._load()
	t.eq(Settings.keymap_scheme, "godot", "load coerces unknown schemes")


func _key(keycode: int, ctrl: bool = false, shift: bool = false, alt: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	return ev


func _snapshot_settings() -> Dictionary:
	var cfg: Variant = null
	if FileAccess.file_exists(Settings.PATH):
		cfg = FileAccess.get_file_as_string(Settings.PATH)
	return {
		"game_root": Settings.game_root,
		"last_map_dir": Settings.last_map_dir,
		"last_save_dir": Settings.last_save_dir,
		"walk_mode": Settings.walk_mode,
		"last_cache_fingerprint": Settings.last_cache_fingerprint,
		"keymap_scheme": Settings.keymap_scheme,
		"recent_maps": Settings.recent_maps.duplicate(),
		"cfg": cfg,
	}


func _restore_settings(snap: Dictionary) -> void:
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
	Settings.game_root = str(snap["game_root"])
	Settings.last_map_dir = str(snap["last_map_dir"])
	Settings.last_save_dir = str(snap["last_save_dir"])
	Settings.walk_mode = bool(snap["walk_mode"])
	Settings.last_cache_fingerprint = str(snap["last_cache_fingerprint"])
	Settings.keymap_scheme = str(snap["keymap_scheme"])
	Settings.recent_maps.clear()
	for path in snap["recent_maps"]:
		Settings.recent_maps.append(str(path))
