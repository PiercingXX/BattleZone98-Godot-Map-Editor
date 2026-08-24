extends RefCounted
## View filters: category classification, hidden-skips-selection, Settings persist.


func run(t) -> void:
	var snap := _snapshot()
	_classification(t)
	_hidden_skips_selection(t)
	_settings_persist(t)
	_team_colors(t)
	await _view_menu(t)
	_restore(snap)


func _classification(t) -> void:
	var saved_index: Dictionary = MapState.asset_index.duplicate(true)
	MapState.asset_index = {
		"classes": [
			{"prjid": "avapc", "category": "craft"},
			{"prjid": "abuild", "category": "building"},
			{"prjid": "loose01", "category": "environment"},
			{"prjid": "weird", "category": "other"},
			{"prjid": "geysx", "category": "geyser"},
		],
	}
	t.eq(ObjectMarkers.classify_record({"prjid": "avapc"}), "units", "index craft → units")
	t.eq(ObjectMarkers.classify_record({"prjid": "abuild"}), "buildings", "index building")
	t.eq(ObjectMarkers.classify_record({"prjid": "loose01"}), "props", "environment → props")
	t.eq(ObjectMarkers.classify_record({"prjid": "weird"}), "props", "other → props")
	t.eq(ObjectMarkers.classify_record({"prjid": "geysx"}), "geysers", "index geyser")
	t.eq(ObjectMarkers.classify_record({"prjid": "eggeizr1"}), "geysers", "prefix geiz")
	t.eq(ObjectMarkers.classify_record({"prjid": "npscr1"}), "scrap", "prefix npscr")
	t.eq(ObjectMarkers.classify_record({"prjid": "sscr_1"}), "scrap", "sscr_1")
	t.eq(ObjectMarkers.classify_record({"prjid": "pspwn_1"}), "spawns", "prefix pspwn")
	t.eq(ObjectMarkers.classify_record({"prjid": "player"}), "units", "player is craft/units")
	t.eq(ObjectMarkers.classify_record({"prjid": "unknownthing"}), "props", "unknown → props")
	t.eq(ObjectMarkers.classify_record({"prjid": "rec", "category": "scrap"}), "scrap", "record category fallback")
	t.eq(ObjectMarkers.view_group_for_category("prop"), "props")
	t.eq(ObjectMarkers.view_group_for_category("spawn"), "spawns")
	MapState.asset_index = saved_index


func _hidden_skips_selection(t) -> void:
	var saved_session := MapState.has_session
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_sel: Array[String] = MapState.selected_ids.duplicate()
	var saved_variant := MapState.active_variant
	var saved_index: Dictionary = MapState.asset_index.duplicate(true)
	MapState.asset_index = {}
	MapState.has_session = true
	MapState.active_variant = ""
	MapState.objects = {
		"": [
			{"id": "g1", "prjid": "eggeizr1", "team": 0},
			{"id": "s1", "prjid": "npscr1", "team": 0},
			{"id": "u1", "prjid": "player", "team": 1},
		],
	}
	Settings.view_geysers = true
	Settings.view_scrap = true
	Settings.view_units = true
	Settings.view_spawns = true
	Settings.view_buildings = true
	Settings.view_props = true

	t.ok(ObjectMarkers.is_record_visible({"prjid": "npscr1"}), "scrap visible by default")
	Settings.view_scrap = false
	t.ok(not ObjectMarkers.is_record_visible({"prjid": "npscr1"}), "scrap hidden")
	t.ok(ObjectMarkers.is_record_visible({"prjid": "eggeizr1"}), "geyser still visible")

	var logs: Array = []
	var log := func(msg): logs.append(str(msg))
	EditActions.select_all_visible(log)
	t.eq(MapState.selected_ids, ["g1", "u1"] as Array[String], "select-all skips hidden scrap")
	t.ok("selected 2 objects" in logs[logs.size() - 1])

	MapState.selected_ids = ["g1", "s1", "u1"] as Array[String]
	logs.clear()
	var n := EditActions.deselect_hidden(log)
	t.eq(n, 1)
	t.eq(MapState.selected_ids, ["g1", "u1"] as Array[String], "hiding drops selected scrap")
	t.eq(logs[logs.size() - 1], "deselected 1 hidden object")

	t.eq(EditActions.filter_visible_ids(["g1", "s1", "missing"]), ["g1"] as Array[String])
	t.eq(EditActions.filter_visible_ids([]), [] as Array[String])

	logs.clear()
	t.eq(EditActions.deselect_hidden(log), 0, "second prune is a no-op")
	t.eq(logs.size(), 0)

	Settings.view_scrap = true
	MapState.has_session = saved_session
	MapState.objects = saved_objects
	MapState.selected_ids = saved_sel
	MapState.active_variant = saved_variant
	MapState.asset_index = saved_index


func _settings_persist(t) -> void:
	Settings.view_geysers = true
	Settings.view_scrap = false
	Settings.view_spawns = true
	Settings.view_buildings = false
	Settings.view_units = true
	Settings.view_props = false
	Settings.view_water = false
	Settings.view_plants = true
	Settings.view_sky = true
	Settings.view_ghost_variants = true
	Settings.view_balance = true
	Settings.view_aipaths = false
	Settings.view_grid = true
	Settings.view_slope = false
	Settings.view_labels = true
	Settings.save()
	Settings.view_geysers = false
	Settings.view_scrap = true
	Settings.view_buildings = true
	Settings.view_props = true
	Settings.view_water = true
	Settings.view_sky = false
	Settings.view_labels = false
	Settings._load()
	t.eq(Settings.view_geysers, true, "view_geysers persists")
	t.eq(Settings.view_scrap, false, "view_scrap persists")
	t.eq(Settings.view_spawns, true)
	t.eq(Settings.view_buildings, false)
	t.eq(Settings.view_units, true)
	t.eq(Settings.view_props, false)
	t.eq(Settings.view_water, false, "view_water persists")
	t.eq(Settings.view_plants, true)
	t.eq(Settings.view_sky, true, "view_sky persists")
	t.eq(Settings.view_ghost_variants, true, "view_ghost_variants persists")
	t.eq(Settings.view_balance, true)
	t.eq(Settings.view_aipaths, false)
	t.eq(Settings.view_grid, true)
	t.eq(Settings.view_slope, false)
	t.eq(Settings.view_labels, true, "view_labels persists")
	t.eq(Settings.view_flag("scrap"), false)
	t.eq(Settings.view_group_visible("scrap"), false)
	t.ok(Settings.view_group_visible("units"))


func _team_colors(t) -> void:
	t.eq(ObjectMarkers.team_color(0), Color(0.55, 0.55, 0.58), "team 0 grey")
	t.ok(ObjectMarkers.team_color(1).g > ObjectMarkers.team_color(1).r, "team 1 green")
	t.ok(ObjectMarkers.team_color(2).r > ObjectMarkers.team_color(2).g, "team 2 red")
	t.ok(ObjectMarkers.team_color(3).b > ObjectMarkers.team_color(3).r, "team 3 blue")
	t.ok(ObjectMarkers.team_color(4).r > 0.7 and ObjectMarkers.team_color(4).g > 0.7, "team 4 yellow")
	t.ok(ObjectMarkers.team_color(5) != ObjectMarkers.team_color(1), "team 5 is a new cycle color")
	t.eq(ObjectMarkers.team_color(8), ObjectMarkers.team_color(1), "team 8 wraps the 7-color cycle")


func _view_menu(t) -> void:
	Settings.view_scrap = true
	Settings.view_plants = true
	Settings.view_sky = false
	var panel: Node = load("res://project/ui/view/ViewPanel.tscn").instantiate()
	t.tree.root.add_child(panel)
	await t.tree.process_frame
	var scrap: CheckBox = panel.find_child("ViewScrap", true, false)
	var sky: CheckBox = panel.find_child("ViewSky", true, false)
	var plants: CheckBox = panel.find_child("ViewPlants", true, false)
	var geysers: CheckBox = panel.find_child("ViewGeysers", true, false)
	t.ok(geysers != null and sky != null, "panel lists the filters")
	var slope: CheckBox = panel.find_child("ViewSlope", true, false)
	var grid: CheckBox = panel.find_child("ViewGrid", true, false)
	var buildable: CheckBox = panel.find_child("ViewBuildable", true, false)
	var ai_trav: CheckBox = panel.find_child("ViewAiTraversable", true, false)
	t.ok(slope != null and grid != null, "View hosts slope/grid")
	t.ok(buildable != null and ai_trav != null, "View hosts buildable / AI traversable")
	t.eq(slope.text, "Slope Tint")
	t.eq(grid.text, "Terrain Grid")
	t.eq(buildable.text, "Buildable Area")
	t.eq(ai_trav.text, "Ai Traversible")
	t.ok(scrap.button_pressed, "scrap checked by default")
	t.ok(plants.disabled, "plants disabled without overlay/regions")
	t.eq(plants.tooltip_text, "no plant regions")
	var was_plants := Settings.view_plants
	t.eq(Settings.view_plants, was_plants, "disabled plants stays put")
	var saw := [0]
	panel.view_changed.connect(func(): saw[0] += 1)
	scrap.button_pressed = false
	t.eq(Settings.view_scrap, false, "View panel flips scrap")
	t.eq(saw[0], 1, "view_changed emits")
	t.ok(not scrap.button_pressed)
	sky.button_pressed = true
	t.ok(Settings.view_sky, "View panel flips sky")
	var was_slope := Settings.view_slope
	slope.button_pressed = not was_slope
	t.eq(Settings.view_slope, not was_slope, "View panel flips slope")
	slope.button_pressed = was_slope
	var was_grid := Settings.view_grid
	grid.button_pressed = not was_grid
	t.eq(Settings.view_grid, not was_grid, "View panel flips grid")
	grid.button_pressed = was_grid
	buildable.button_pressed = true
	t.ok(Settings.view_buildable, "View panel flips buildable")
	buildable.button_pressed = false
	ai_trav.button_pressed = true
	t.ok(Settings.view_ai_traversable, "View panel flips ai traversable")
	ai_trav.button_pressed = false
	panel.queue_free()
	await t.tree.process_frame


func _snapshot() -> Dictionary:
	var cfg: Variant = null
	if FileAccess.file_exists(Settings.PATH):
		cfg = FileAccess.get_file_as_string(Settings.PATH)
	return {
		"cfg": cfg,
		"view_geysers": Settings.view_geysers,
		"view_scrap": Settings.view_scrap,
		"view_spawns": Settings.view_spawns,
		"view_buildings": Settings.view_buildings,
		"view_units": Settings.view_units,
		"view_props": Settings.view_props,
		"view_water": Settings.view_water,
		"view_plants": Settings.view_plants,
		"view_sky": Settings.view_sky,
		"view_ghost_variants": Settings.view_ghost_variants,
		"view_balance": Settings.view_balance,
		"view_aipaths": Settings.view_aipaths,
		"view_grid": Settings.view_grid,
		"view_slope": Settings.view_slope,
		"view_buildable": Settings.view_buildable,
		"view_ai_traversable": Settings.view_ai_traversable,
		"view_labels": Settings.view_labels,
		"ghost": ObjectMarkers.ghost_other_variants,
		"balance": BalanceOverlay.enabled,
		"aipaths": AiPathOverlay.enabled,
		"session": MapState.has_session,
		"objects": MapState.objects.duplicate(true),
		"sel": MapState.selected_ids.duplicate(),
		"variant": MapState.active_variant,
		"index": MapState.asset_index.duplicate(true),
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
	Settings.view_geysers = bool(snap["view_geysers"])
	Settings.view_scrap = bool(snap["view_scrap"])
	Settings.view_spawns = bool(snap["view_spawns"])
	Settings.view_buildings = bool(snap["view_buildings"])
	Settings.view_units = bool(snap["view_units"])
	Settings.view_props = bool(snap["view_props"])
	Settings.view_water = bool(snap["view_water"])
	Settings.view_plants = bool(snap["view_plants"])
	Settings.view_sky = bool(snap["view_sky"])
	Settings.view_ghost_variants = bool(snap.get("view_ghost_variants", false))
	Settings.view_balance = bool(snap.get("view_balance", false))
	Settings.view_aipaths = bool(snap.get("view_aipaths", false))
	Settings.view_grid = bool(snap.get("view_grid", false))
	Settings.view_slope = bool(snap.get("view_slope", false))
	Settings.view_buildable = bool(snap.get("view_buildable", false))
	Settings.view_ai_traversable = bool(snap.get("view_ai_traversable", false))
	Settings.view_labels = bool(snap.get("view_labels", false))
	ObjectMarkers.ghost_other_variants = bool(snap.get("ghost", false))
	BalanceOverlay.enabled = bool(snap.get("balance", false))
	AiPathOverlay.enabled = bool(snap.get("aipaths", false))
	MapState.has_session = bool(snap["session"])
	MapState.objects = snap["objects"]
	MapState.selected_ids = snap["sel"]
	MapState.active_variant = str(snap["variant"])
	MapState.asset_index = snap["index"]
