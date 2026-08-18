extends RefCounted
## Batch replace-class: one undo step, runtime confirm gate, MapState round-trip.


func run(t) -> void:
	var saved_session := MapState.has_session
	var saved_objects: Dictionary = MapState.objects.duplicate(true)
	var saved_dirty: Dictionary = MapState.dirty.duplicate(true)
	var saved_sel: Array[String] = MapState.selected_ids.duplicate()
	var saved_variant := MapState.active_variant
	var saved_index: Dictionary = MapState.asset_index.duplicate(true)
	UndoStack.clear()
	MapState.has_session = true
	MapState.active_variant = ""
	MapState.dirty = {}
	MapState.asset_index = {}

	_undo_round_trip(t)
	_runtime_gate(t)
	_guards(t)

	UndoStack.clear()
	MapState.has_session = saved_session
	MapState.objects = saved_objects
	MapState.dirty = saved_dirty
	MapState.selected_ids = saved_sel
	MapState.active_variant = saved_variant
	MapState.asset_index = saved_index
	if saved_session:
		MapState.mark_saved()


func _undo_round_trip(t) -> void:
	var a := _rec("r-a", "avapc", 1)
	var b := _rec("r-b", "avapc", 2)
	MapState.objects = {"": [a, b]}
	MapState.selected_ids = ["r-a", "r-b"] as Array[String]
	UndoStack.clear()
	var logs: Array = []
	var log := func(msg): logs.append(str(msg))
	var info := {"prjid": "gbtank", "placement_mode": "bzn", "template_verified": true}

	var result := EditActions.replace_selection_class("gbtank", log, info)
	t.ok(bool(result.get("ok", false)))
	t.eq(int(result.get("count", 0)), 2)
	t.eq(str(MapState.find_object("r-a").get("prjid", "")), "gbtank")
	t.eq(str(MapState.find_object("r-b").get("prjid", "")), "gbtank")
	t.eq(str(MapState.find_object("r-a").get("placement_mode", "")), "bzn")
	t.eq(int(MapState.find_object("r-a").get("team", 0)), 1, "team left alone")
	t.eq(int(MapState.find_object("r-b").get("team", 0)), 2)
	t.eq(logs[logs.size() - 1], "replaced class → gbtank on 2 objects")
	t.ok(UndoStack.can_undo(), "replace pushed undo")
	UndoStack.undo()
	t.eq(str(MapState.find_object("r-a").get("prjid", "")), "avapc")
	t.eq(str(MapState.find_object("r-b").get("prjid", "")), "avapc")
	t.eq(str(MapState.find_object("r-a").get("placement_mode", "")), "clone")
	t.ok(not UndoStack.can_undo(), "whole replace is one undo step")
	UndoStack.redo()
	t.eq(str(MapState.find_object("r-a").get("prjid", "")), "gbtank")
	t.eq(str(MapState.find_object("r-b").get("prjid", "")), "gbtank")

	logs.clear()
	var again := EditActions.replace_selection_class("gbtank", log, info)
	t.ok(not bool(again.get("ok", true)))
	t.eq(logs[logs.size() - 1], "already gbtank")
	UndoStack.undo()
	t.eq(str(MapState.find_object("r-a").get("prjid", "")), "avapc", "already-same is not an extra undo")


func _runtime_gate(t) -> void:
	var rec := _rec("rt-1", "avapc", 1)
	MapState.objects = {"": [rec]}
	MapState.selected_ids = ["rt-1"] as Array[String]
	UndoStack.clear()
	var logs: Array = []
	var log := func(msg): logs.append(str(msg))
	var runtime := {"prjid": "svtank", "placement_mode": "runtime", "template_verified": false}

	t.ok(EditActions.class_needs_runtime_confirm(runtime))
	t.ok(not EditActions.class_needs_runtime_confirm({"placement_mode": "bzn"}))

	var refused := EditActions.replace_selection_class("svtank", log, runtime, false)
	t.ok(not bool(refused.get("ok", true)))
	t.ok(bool(refused.get("needs_confirm", false)))
	t.eq(str(MapState.find_object("rt-1").get("prjid", "")), "avapc", "runtime refused without confirm")
	t.ok(not UndoStack.can_undo(), "refused replace is not an undo step")
	t.ok("not clone-safe" in logs[logs.size() - 1])

	logs.clear()
	var allowed := EditActions.replace_selection_class("svtank", log, runtime, true)
	t.ok(bool(allowed.get("ok", false)))
	t.eq(str(MapState.find_object("rt-1").get("prjid", "")), "svtank")
	t.eq(str(MapState.find_object("rt-1").get("placement_mode", "")), "runtime")
	t.eq(logs[logs.size() - 1], "replaced class → svtank on 1 object")
	UndoStack.undo()
	t.eq(str(MapState.find_object("rt-1").get("prjid", "")), "avapc")
	t.eq(str(MapState.find_object("rt-1").get("placement_mode", "")), "clone")


func _guards(t) -> void:
	var player := _rec("p1", "player", 1)
	player["required"] = true
	var unit := _rec("u1", "avapc", 1)
	MapState.objects = {"": [player, unit]}
	UndoStack.clear()
	var logs: Array = []
	var log := func(msg): logs.append(str(msg))
	var info := {"prjid": "gbtank", "placement_mode": "bzn", "template_verified": true}

	MapState.selected_ids.clear()
	var none := EditActions.replace_selection_class("gbtank", log, info)
	t.eq(str(none.get("error", "")), "nothing selected")
	t.ok(not UndoStack.can_undo())

	MapState.has_session = false
	logs.clear()
	MapState.selected_ids = ["u1"] as Array[String]
	var nosess := EditActions.replace_selection_class("gbtank", log, info)
	t.eq(str(nosess.get("error", "")), "open a map first")
	MapState.has_session = true

	logs.clear()
	var to_player := EditActions.replace_selection_class("player", log, {"prjid": "player", "placement_mode": "bzn"})
	t.eq(str(to_player.get("error", "")), "cannot replace selection with player")
	t.eq(str(MapState.find_object("u1").get("prjid", "")), "avapc")

	logs.clear()
	MapState.selected_ids = ["p1"] as Array[String]
	var only_player := EditActions.replace_selection_class("gbtank", log, info)
	t.eq(str(only_player.get("error", "")), "player object class cannot be replaced")
	t.eq(str(MapState.find_object("p1").get("prjid", "")), "player")

	logs.clear()
	MapState.selected_ids = ["p1", "u1"] as Array[String]
	var mixed := EditActions.replace_selection_class("gbtank", log, info)
	t.ok(bool(mixed.get("ok", false)))
	t.eq(int(mixed.get("count", 0)), 1)
	t.eq(str(MapState.find_object("p1").get("prjid", "")), "player")
	t.eq(str(MapState.find_object("u1").get("prjid", "")), "gbtank")
	t.ok("skipped 1 required" in logs[logs.size() - 1])
	UndoStack.undo()
	t.eq(str(MapState.find_object("u1").get("prjid", "")), "avapc")


func _rec(id: String, prjid: String, team: int) -> Dictionary:
	return {
		"id": id, "prjid": prjid, "label": id,
		"x": 0.0, "y": 0.0, "z": 0.0, "yaw_deg": 0.0,
		"team": team, "pinned_y": false, "required": false,
		"placement_mode": "clone",
	}
