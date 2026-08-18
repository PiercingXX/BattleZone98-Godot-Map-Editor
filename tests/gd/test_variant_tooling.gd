extends RefCounted
## Variant tooling: copy-to-variant (undo + player refusal) and ghost pick-filter.


func run(t) -> void:
	var snap := _snapshot()
	UndoStack.clear()
	MapState.has_session = true
	MapState.active_variant = ""
	MapState.dirty = {}
	MapState.asset_index = {}
	MapState.next_new_id = 1
	MapState.manifest = {"variants": ["", "_S", "_ST", "_SW"]}
	ObjectMarkers.ghost_other_variants = false

	_copy_round_trip(t)
	_copy_player_refusal(t)
	_copy_guards(t)
	_ghost_pick_filter(t)
	await _view_and_counts(t)
	await _help_mentions(t)

	_restore(snap)


func _copy_round_trip(t) -> void:
	var a := _rec("c-a", "avapc", 1, 10.0, 20.0, 45.0)
	var b := _rec("c-b", "gbtank", 2, 30.0, 40.0, -15.0)
	MapState.objects = {"": [a, b], "_S": []}
	MapState.selected_ids = ["c-a", "c-b"] as Array[String]
	MapState.next_new_id = 1
	UndoStack.clear()
	var logs: Array = []
	var log := func(msg): logs.append(str(msg))

	var result := EditActions.copy_selection_to_variant("_S", log)
	t.ok(bool(result.get("ok", false)), "copy succeeds")
	t.eq(int(result.get("count", 0)), 2)
	t.eq(logs[logs.size() - 1], "copied 2 objects to _S")
	t.eq(EditActions.variant_object_count(""), 2, "source variant untouched")
	t.eq(EditActions.variant_object_count("_S"), 2)
	var ids: Array = result.get("ids", [])
	t.eq(ids.size(), 2)
	t.eq(str(ids[0]), "new-0001")
	t.eq(str(ids[1]), "new-0002")
	var ca := MapState.find_object("new-0001")
	var cb := MapState.find_object("new-0002")
	t.eq(str(ca.get("prjid", "")), "avapc")
	t.eq(int(ca.get("team", 0)), 1)
	t.eq(float(ca.get("x", 0.0)), 10.0)
	t.eq(float(ca.get("z", 0.0)), 20.0)
	t.eq(float(ca.get("yaw_deg", 0.0)), 45.0)
	t.eq(str(cb.get("prjid", "")), "gbtank")
	t.eq(int(cb.get("team", 0)), 2)
	t.eq(MapState.find_object_variant("new-0001"), "_S")
	t.eq(MapState.find_object_variant("new-0002"), "_S")
	t.eq(MapState.find_object_variant("c-a"), "", "originals stay on DM")
	t.ok(UndoStack.can_undo(), "copy pushed one undo")
	UndoStack.undo()
	t.eq(EditActions.variant_object_count("_S"), 0, "undo removes both copies")
	t.ok(MapState.find_object("new-0001").is_empty())
	t.ok(MapState.find_object("c-a").is_empty() == false)
	t.ok(not UndoStack.can_undo(), "whole copy is one undo step")
	UndoStack.redo()
	t.eq(EditActions.variant_object_count("_S"), 2, "redo restores both")
	t.eq(str(MapState.find_object("new-0001").get("prjid", "")), "avapc")
	UndoStack.undo()


func _copy_player_refusal(t) -> void:
	var player := _rec("p1", "player", 1, 0.0, 0.0, 0.0)
	player["required"] = true
	var unit := _rec("u1", "avapc", 1, 8.0, 9.0, 0.0)
	MapState.objects = {"": [player, unit], "_S": []}
	UndoStack.clear()
	var logs: Array = []
	var log := func(msg): logs.append(str(msg))

	MapState.selected_ids = ["p1"] as Array[String]
	t.eq(EditActions.copy_to_variant_block_reason(), "player object cannot be copied")
	var refused := EditActions.copy_selection_to_variant("_S", log)
	t.ok(not bool(refused.get("ok", true)))
	t.eq(str(refused.get("error", "")), "player object cannot be copied")
	t.eq(EditActions.variant_object_count("_S"), 0, "player was not copied")
	t.ok(not UndoStack.can_undo(), "refused copy is not an undo step")
	t.eq(logs[logs.size() - 1], "player object cannot be copied")

	logs.clear()
	MapState.selected_ids = ["p1", "u1"] as Array[String]
	MapState.next_new_id = 5
	t.eq(EditActions.copy_to_variant_block_reason(), "")
	var mixed := EditActions.copy_selection_to_variant("_S", log)
	t.ok(bool(mixed.get("ok", false)))
	t.eq(int(mixed.get("count", 0)), 1)
	t.eq(EditActions.variant_object_count("_S"), 1)
	t.eq(str(MapState.find_object("new-0005").get("prjid", "")), "avapc")
	t.eq(MapState.find_object_variant("p1"), "")
	t.ok("skipped player" in logs[logs.size() - 1])
	t.ok(UndoStack.can_undo())
	UndoStack.undo()
	t.eq(EditActions.variant_object_count("_S"), 0)


func _copy_guards(t) -> void:
	var unit := _rec("g1", "avapc", 1, 1.0, 2.0, 0.0)
	MapState.objects = {"": [unit], "_S": []}
	UndoStack.clear()
	var logs: Array = []
	var log := func(msg): logs.append(str(msg))

	MapState.selected_ids.clear()
	var none := EditActions.copy_selection_to_variant("_S", log)
	t.eq(str(none.get("error", "")), "nothing selected")
	t.ok(not UndoStack.can_undo())

	MapState.has_session = false
	MapState.selected_ids = ["g1"] as Array[String]
	logs.clear()
	var nosess := EditActions.copy_selection_to_variant("_S", log)
	t.eq(str(nosess.get("error", "")), "open a map first")
	MapState.has_session = true

	logs.clear()
	var same := EditActions.copy_selection_to_variant("", log)
	t.eq(str(same.get("error", "")), "pick a different variant")
	t.eq(EditActions.variant_object_count(""), 1)

	logs.clear()
	var bogus := EditActions.copy_selection_to_variant("_NOPE", log)
	t.eq(str(bogus.get("error", "")), "unknown variant")

	t.eq(EditActions.other_variants(), ["_S", "_ST", "_SW"] as Array[String])
	t.eq(EditActions.variant_display_name(""), "DM")
	t.eq(EditActions.variant_display_name("_SW"), "_SW")


func _ghost_pick_filter(t) -> void:
	var saved_scrap := Settings.view_scrap
	var saved_units := Settings.view_units
	Settings.view_scrap = true
	Settings.view_units = true
	MapState.active_variant = ""
	MapState.objects = {
		"": [
			{"id": "dm-u", "prjid": "avapc", "team": 1, "x": 0.0, "y": 0.0, "z": 0.0},
			{"id": "dm-s", "prjid": "npscr1", "team": 0, "x": 40.0, "y": 0.0, "z": 0.0},
		],
		"_S": [
			{"id": "s-u", "prjid": "avapc", "team": 1, "x": 0.0, "y": 0.0, "z": 0.0},
		],
		"_SW": [
			{"id": "sw-u", "prjid": "gbtank", "team": 2, "x": 80.0, "y": 0.0, "z": 0.0},
		],
	}
	var markers := ObjectMarkers.new()
	ObjectMarkers.ghost_other_variants = false
	t.ok(ObjectMarkers.is_id_pickable("dm-u"), "active variant is pickable")
	t.ok(not ObjectMarkers.is_id_pickable("s-u"), "other variant is never pickable")
	t.ok(not ObjectMarkers.is_id_pickable("sw-u"))
	t.ok(not ObjectMarkers.is_variant_ghosted("_S"), "ghosts off → not ghosted")
	t.ok(not markers.is_id_visible("s-u"), "other variant hidden when ghosts off")
	t.ok(markers.is_id_visible("dm-u"))

	ObjectMarkers.ghost_other_variants = true
	t.ok(ObjectMarkers.is_variant_ghosted("_S"))
	t.ok(ObjectMarkers.is_variant_ghosted("_SW"))
	t.ok(not ObjectMarkers.is_variant_ghosted(""))
	t.ok(markers.is_id_visible("s-u"), "ghosts on → other variant shown")
	t.ok(not ObjectMarkers.is_id_pickable("s-u"), "shown ghost is still not pickable")
	t.ok(ObjectMarkers.is_id_pickable("dm-u"))

	Settings.view_scrap = false
	t.ok(not ObjectMarkers.is_id_pickable("dm-s"), "hidden category is not pickable")
	t.eq(EditActions.filter_visible_ids(["dm-u", "s-u", "dm-s"]), ["dm-u"] as Array[String])
	Settings.view_scrap = true

	t.ok(ObjectMarkers.variant_tint("") != ObjectMarkers.variant_tint("_S"), "DM vs _S tints differ")
	t.ok(ObjectMarkers.variant_tint("_S") != ObjectMarkers.variant_tint("_ST"))
	t.ok(ObjectMarkers.variant_tint("_ST") != ObjectMarkers.variant_tint("_SW"))
	t.eq(ObjectMarkers.variant_display_name(""), "DM")

	# Live markers: a ghost stacked on the active unit must not win the pick.
	t.tree.root.add_child(markers)
	markers.rebuild(MapState.objects, null)
	var hit := markers.pick(Vector3(0, 20, 0), Vector3(0, -1, 0))
	t.eq(hit, "dm-u", "pick prefers the active variant, never a ghost")
	ObjectMarkers.ghost_other_variants = false
	markers.apply_visibility()
	t.ok(not markers.is_id_visible("s-u"))
	markers.reset()
	markers.queue_free()
	ObjectMarkers.ghost_other_variants = false
	Settings.view_scrap = saved_scrap
	Settings.view_units = saved_units


func _view_and_counts(t) -> void:
	ObjectMarkers.ghost_other_variants = false
	MapState.objects = {
		"": [_rec("a", "avapc", 1, 0, 0, 0), _rec("b", "avapc", 1, 0, 0, 0)],
		"_S": [_rec("c", "avapc", 1, 0, 0, 0)],
		"_ST": [],
		"_SW": [
			_rec("d", "avapc", 1, 0, 0, 0),
			_rec("e", "avapc", 1, 0, 0, 0),
			_rec("f", "avapc", 1, 0, 0, 0),
		],
	}
	var bar: Node = load("res://project/ui/top_bar/TopBar.tscn").instantiate()
	t.tree.root.add_child(bar)
	await t.tree.process_frame
	var view: MenuButton = bar.find_child("View", true, false)
	t.ok(view != null)
	var pop: PopupMenu = view.get_popup()
	var gidx := pop.get_item_index(bar.VIEW_GHOST_VARIANTS)
	t.ok(gidx >= 0, "View menu lists Ghost other variants")
	t.eq(pop.get_item_text(gidx), "Ghost other variants")
	t.ok(not pop.is_item_checked(gidx))
	var saw := [0]
	bar.view_changed.connect(func(): saw[0] += 1)
	pop.id_pressed.emit(bar.VIEW_GHOST_VARIANTS)
	t.ok(ObjectMarkers.ghost_other_variants, "View toggle turns ghosts on")
	t.eq(saw[0], 1)
	t.ok(pop.is_item_checked(pop.get_item_index(bar.VIEW_GHOST_VARIANTS)))
	pop.id_pressed.emit(bar.VIEW_GHOST_VARIANTS)
	t.ok(not ObjectMarkers.ghost_other_variants)

	bar.fill_variants(["", "_S", "_ST", "_SW"], "")
	var variant: OptionButton = bar.find_child("Variant", true, false)
	t.eq(variant.get_item_text(0), "DM (2)")
	t.eq(variant.get_item_text(1), "_S (1)")
	t.eq(variant.get_item_text(2), "_ST (0)")
	t.eq(variant.get_item_text(3), "_SW (3)")
	MapState.objects["_S"].append(_rec("c2", "avapc", 1, 0, 0, 0))
	MapState.objects_changed()
	t.eq(variant.get_item_text(1), "_S (2)", "counts refresh on objects_mutated")
	bar.queue_free()
	await t.tree.process_frame
	ObjectMarkers.ghost_other_variants = false


func _help_mentions(t) -> void:
	var help: Node = load("res://project/ui/help/HelpWindow.tscn").instantiate()
	t.tree.root.add_child(help)
	await t.tree.process_frame
	var body: RichTextLabel = help.find_child("Body", true, false)
	var text := body.text.to_lower()
	t.ok("ghost other variants" in text, "help documents onion skin")
	t.ok("copy to variant" in text, "help documents copy-to-variant")
	help.queue_free()
	await t.tree.process_frame


func _rec(id: String, prjid: String, team: int, x: float, z: float, yaw: float) -> Dictionary:
	return {
		"id": id, "prjid": prjid, "label": id,
		"x": x, "y": 0.0, "z": z, "yaw_deg": yaw,
		"team": team, "pinned_y": false, "required": false,
		"placement_mode": "clone",
	}


func _snapshot() -> Dictionary:
	return {
		"session": MapState.has_session,
		"objects": MapState.objects.duplicate(true),
		"dirty": MapState.dirty.duplicate(true),
		"sel": MapState.selected_ids.duplicate(),
		"variant": MapState.active_variant,
		"index": MapState.asset_index.duplicate(true),
		"manifest": MapState.manifest.duplicate(true),
		"next_id": MapState.next_new_id,
		"ghost": ObjectMarkers.ghost_other_variants,
	}


func _restore(snap: Dictionary) -> void:
	UndoStack.clear()
	MapState.has_session = bool(snap["session"])
	MapState.objects = snap["objects"]
	MapState.dirty = snap["dirty"]
	MapState.selected_ids = snap["sel"]
	MapState.active_variant = str(snap["variant"])
	MapState.asset_index = snap["index"]
	MapState.manifest = snap["manifest"]
	MapState.next_new_id = int(snap["next_id"])
	ObjectMarkers.ghost_other_variants = bool(snap["ghost"])
	if MapState.has_session:
		MapState.mark_saved()
