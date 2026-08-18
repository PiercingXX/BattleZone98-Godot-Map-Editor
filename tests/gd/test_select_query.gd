extends RefCounted
## Query parser + matcher (pure) and select-by-query over MapState.


func run(t) -> void:
	_parser(t)
	_matcher(t)
	_select_by_query(t)
	await _ui_row(t)
	await _help(t)


func _parser(t) -> void:
	var empty := EditActions.parse_object_query("")
	t.ok(not bool(empty.get("ok", true)))
	t.eq(str(empty.get("error", "")), "enter a query")
	t.eq((empty.get("terms", ["x"]) as Array).size(), 0)

	var bare := EditActions.parse_object_query("  av*  ")
	t.ok(bool(bare.get("ok", false)), "bare text is a class glob")
	t.eq((bare.get("terms", []) as Array).size(), 1)
	t.eq(str((bare["terms"] as Array)[0].get("kind")), "class")
	t.eq(str((bare["terms"] as Array)[0].get("value")), "av*")

	var keyed := EditActions.parse_object_query("class:av* team:1 cat:craft label:base")
	t.ok(bool(keyed.get("ok", false)))
	var kinds: Array = []
	for term in keyed.get("terms", []):
		kinds.append(str(term.get("kind")))
	t.eq(kinds, ["class", "team", "cat", "label"])

	t.eq(str(EditActions.parse_object_query("class:").get("error", "")), "class: needs a glob")
	t.eq(str(EditActions.parse_object_query("team:x").get("error", "")), "team: needs a number")
	t.eq(str(EditActions.parse_object_query("cat:").get("error", "")), "cat: needs a category")
	t.eq(str(EditActions.parse_object_query("label:").get("error", "")), "label: needs a substring")
	t.eq(str(EditActions.parse_object_query("foo:bar").get("error", "")), "unknown term 'foo:'")
	t.ok(bool(EditActions.parse_object_query("team:0").get("ok", false)))
	t.ok(EditActions.OBJECT_QUERY_HELP.contains("class:<glob>"))
	t.ok(EditActions.OBJECT_QUERY_HELP.contains("team:<n>"))
	t.ok(EditActions.OBJECT_QUERY_HELP.contains("cat:<category>"))
	t.ok(EditActions.OBJECT_QUERY_HELP.contains("label:<substr>"))


func _matcher(t) -> void:
	var recs: Array = [
		{"id": "a", "prjid": "avapc", "team": 1, "label": "APC Alpha"},
		{"id": "b", "prjid": "gbtank", "team": 2, "label": "Tank Bravo"},
		{"id": "c", "prjid": "npscr1", "team": 0, "label": "scrap pile"},
		{"id": "d", "prjid": "avmisl", "team": 1, "label": "Missile"},
	]
	var index := {
		"classes": [
			{"prjid": "avapc", "category": "craft"},
			{"prjid": "gbtank", "category": "craft"},
			{"prjid": "npscr1", "category": "scrap"},
			{"prjid": "avmisl", "category": "craft"},
		],
	}
	t.ok(EditActions.class_glob_match("avapc", "av*"))
	t.ok(EditActions.class_glob_match("avapc", "*apc"))
	t.ok(EditActions.class_glob_match("avapc", "AVAPC"))
	t.ok(not EditActions.class_glob_match("gbtank", "av*"))
	t.ok(EditActions.class_glob_match("avapc", "*"))
	t.ok(not EditActions.class_glob_match("avapc", ""))

	t.eq(EditActions.category_for_record(recs[0], index), "craft")
	t.eq(EditActions.category_for_record(recs[2], index), "scrap")
	t.eq(
		EditActions.category_for_record({"prjid": "loose", "category": "prop"}, {}),
		"prop",
		"falls back to record category",
	)

	var class_av: Array = EditActions.parse_object_query("av*").get("terms", [])
	t.eq(EditActions.query_matching_ids(recs, class_av, index), ["a", "d"] as Array[String])
	var team1: Array = EditActions.parse_object_query("team:1").get("terms", [])
	t.eq(EditActions.query_matching_ids(recs, team1, index), ["a", "d"] as Array[String])
	var craft: Array = EditActions.parse_object_query("cat:craft").get("terms", [])
	t.eq(EditActions.query_matching_ids(recs, craft, index), ["a", "b", "d"] as Array[String])
	var lab: Array = EditActions.parse_object_query("label:tank").get("terms", [])
	t.eq(EditActions.query_matching_ids(recs, lab, index), ["b"] as Array[String])
	var anded: Array = EditActions.parse_object_query("av* team:1 cat:craft").get("terms", [])
	t.eq(EditActions.query_matching_ids(recs, anded, index), ["a", "d"] as Array[String])
	var none: Array = EditActions.parse_object_query("av* team:2").get("terms", [])
	t.eq(EditActions.query_matching_ids(recs, none, index), [] as Array[String])
	t.eq(EditActions.query_matching_ids([], class_av, index), [] as Array[String])
	t.eq(
		EditActions.query_matching_ids([{"prjid": "avapc", "team": 1}], class_av, index),
		[] as Array[String],
		"records without id are skipped",
	)


func _select_by_query(t) -> void:
	var saved_session := MapState.has_session
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_sel: Array[String] = MapState.selected_ids.duplicate()
	var saved_variant := MapState.active_variant
	var saved_index: Dictionary = MapState.asset_index.duplicate(true)
	var saved_scrap := Settings.view_scrap
	var saved_geysers := Settings.view_geysers
	var saved_units := Settings.view_units
	MapState.has_session = true
	MapState.active_variant = ""
	MapState.asset_index = {
		"classes": [
			{"prjid": "avapc", "category": "craft"},
			{"prjid": "npscr1", "category": "scrap"},
			{"prjid": "gbtank", "category": "craft"},
		],
	}
	MapState.objects = {
		"": [
			{"id": "a", "prjid": "avapc", "team": 1, "label": "APC"},
			{"id": "s", "prjid": "npscr1", "team": 0, "label": "scrap"},
		],
		"S": [
			{"id": "other", "prjid": "avapc", "team": 1, "label": "other variant"},
		],
	}
	MapState.selected_ids.clear()
	Settings.view_scrap = true
	Settings.view_geysers = true
	Settings.view_units = true
	var logs: Array = []
	var log := func(msg): logs.append(str(msg))

	EditActions.select_by_query("av*", false, log)
	t.eq(MapState.selected_ids, ["a"] as Array[String], "active variant only")
	t.eq(logs[logs.size() - 1], "query selected 1 object")

	logs.clear()
	EditActions.select_by_query("npscr1", true, log)
	t.eq(MapState.selected_ids, ["a", "s"] as Array[String], "Add unions")
	t.eq(logs[logs.size() - 1], "query added 1 to selection")

	logs.clear()
	EditActions.select_by_query("npscr1", true, log)
	t.eq(MapState.selected_ids, ["a", "s"] as Array[String], "Add already-selected is 0")
	t.eq(logs[logs.size() - 1], "query added 0 to selection")

	Settings.view_scrap = false
	logs.clear()
	EditActions.select_by_query("*", false, log)
	t.eq(MapState.selected_ids, ["a"] as Array[String], "query skips hidden view-filter categories")
	t.eq(logs[logs.size() - 1], "query selected 1 object")

	var hidden_ids := EditActions.query_matching_ids(
		MapState.objects[""],
		EditActions.parse_object_query("*").get("terms", []),
		MapState.asset_index,
		true,
	)
	t.eq(hidden_ids, ["a"] as Array[String], "matcher skip_hidden")

	logs.clear()
	MapState.has_session = false
	EditActions.select_by_query("av*", false, log)
	t.eq(logs[logs.size() - 1], "open a map first")

	MapState.has_session = true
	logs.clear()
	EditActions.select_by_query("foo:bar", false, log)
	t.eq(logs[logs.size() - 1], "unknown term 'foo:'")

	Settings.view_scrap = saved_scrap
	Settings.view_geysers = saved_geysers
	Settings.view_units = saved_units
	MapState.has_session = saved_session
	MapState.objects = saved_objects
	MapState.selected_ids = saved_sel
	MapState.active_variant = saved_variant
	MapState.asset_index = saved_index


func _ui_row(t) -> void:
	var saved_session := MapState.has_session
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_sel: Array[String] = MapState.selected_ids.duplicate()
	var saved_variant := MapState.active_variant
	var saved_tool := ToolState.tool
	var saved_index: Dictionary = MapState.asset_index.duplicate(true)
	MapState.has_session = false
	MapState.selected_ids.clear()
	MapState.active_variant = ""
	Settings.view_units = true
	Settings.view_scrap = true
	MapState.objects = {
		"": [
			{"id": "u1", "prjid": "avapc", "team": 1, "label": "APC"},
			{"id": "u2", "prjid": "gbtank", "team": 2, "label": "Tank"},
		],
	}
	ToolState.set_tool("select")

	var pal: Node = load("res://project/ui/palette/PalettePanel.tscn").instantiate()
	t.tree.root.add_child(pal)
	await t.tree.process_frame
	var qedit: LineEdit = pal.find_child("QueryEdit", true, false)
	var qsel: Button = pal.find_child("QuerySelect", true, false)
	var qadd: Button = pal.find_child("QueryAdd", true, false)
	var team_btn: Button = pal.find_child("BatchTeamApply", true, false)
	var team_spin: SpinBox = pal.find_child("BatchTeam", true, false)
	var repl: Button = pal.find_child("ReplaceClass", true, false)
	t.ok(qedit != null and qsel != null and qadd != null, "query row exists")
	t.ok(team_btn != null and team_spin != null and repl != null, "batch row exists")
	t.ok(EditActions.OBJECT_QUERY_HELP in qedit.tooltip_text, "query tooltip documents syntax")
	t.ok(qsel.disabled, "Select disabled with no map")
	t.ok("Open a map first" in qsel.tooltip_text)
	t.ok(team_btn.disabled)
	t.ok("Open a map first" in team_btn.tooltip_text)

	MapState.has_session = true
	pal.refresh_context()
	t.ok(qsel.disabled, "Select disabled on empty query")
	t.ok("Enter a query" in qsel.tooltip_text)
	t.ok(team_btn.disabled)
	t.ok("Nothing selected" in team_btn.tooltip_text)
	t.ok(repl.disabled)
	t.ok("Nothing selected" in repl.tooltip_text)

	qedit.text = "av*"
	qedit.text_changed.emit("av*")
	t.ok(not qsel.disabled, "Select enables with a valid query")
	t.ok(not qadd.disabled)
	qsel.pressed.emit()
	t.eq(MapState.selected_ids, ["u1"] as Array[String], "UI Select replaces")
	t.ok(not team_btn.disabled, "batch enables with a selection")
	t.eq(int(team_spin.value), 1, "team spin follows first selected")

	qedit.text = "gbtank"
	qedit.text_changed.emit("gbtank")
	qadd.pressed.emit()
	t.eq(MapState.selected_ids, ["u1", "u2"] as Array[String], "UI Add unions")

	qedit.text = "foo:bar"
	qedit.text_changed.emit("foo:bar")
	t.ok(qsel.disabled)
	t.ok("Unknown term 'foo:'" in qsel.tooltip_text)

	pal.set_classes({
		"classes": [
			{"prjid": "avapc", "label": "APC", "source": "game", "category": "craft", "placement_mode": "bzn"},
		],
	}, "bzp")
	MapState.selected_ids = ["u1"] as Array[String]
	pal.refresh_context()
	t.ok(not repl.disabled, "Replace enables with classes + selection")

	pal.queue_free()
	await t.tree.process_frame
	MapState.has_session = saved_session
	MapState.objects = saved_objects
	MapState.selected_ids = saved_sel
	MapState.active_variant = saved_variant
	MapState.asset_index = saved_index
	ToolState.set_tool(saved_tool if saved_tool != "" else "fly")


func _help(t) -> void:
	var help: Node = load("res://project/ui/help/HelpWindow.tscn").instantiate()
	t.tree.root.add_child(help)
	await t.tree.process_frame
	var body: RichTextLabel = help.find_child("Body", true, false)
	var text := body.text
	t.ok("class:<glob>" in text, "help documents class glob")
	t.ok("team:<n>" in text)
	t.ok("cat:<category>" in text)
	t.ok("label:<substr>" in text)
	t.ok("Replace class" in text)
	t.ok("Set team" in text)
	help.queue_free()
	await t.tree.process_frame
