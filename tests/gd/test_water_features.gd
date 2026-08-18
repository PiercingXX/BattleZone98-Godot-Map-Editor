extends RefCounted
## MapState water writes the docs/02 features.json shape.


func run(t) -> void:
	var saved_feat: Dictionary = MapState.features.duplicate(true)
	var saved_stem: String = MapState.stem
	var saved_session := MapState.has_session
	var saved_dirty: Dictionary = MapState.dirty.duplicate(true)
	MapState.stem = "testmap"
	MapState.features = {"water": [], "plants": []}
	MapState.set_water_level(92.0)
	t.near(MapState.water_level(), 92.0, 0.001)
	var waters: Array = MapState.features.get("water", [])
	t.eq(waters.size(), 1, "one water feature")
	t.eq(waters[0].get("level_m"), 92.0)
	t.eq(waters[0].get("variant_scope"), "all")
	t.ok(str(waters[0].get("stem", "")).length() <= 8, "stem fits engine 8-char cap")
	t.eq(MapState.dirty.get("features"), true)
	# unsaved is generation-derived; a live write is committed via WaterCommand.
	MapState.has_session = true
	UndoStack.clear()
	MapState.mark_saved()
	var cmd := WaterCommand.new()
	cmd.before = -1.0
	cmd.after = 92.0
	UndoStack.push(cmd, true)
	t.ok(MapState.unsaved, "water command dirties")
	UndoStack.undo()
	t.ok(not MapState.unsaved, "undo water returns to saved generation")
	MapState.set_water_level(-1.0)
	t.eq(MapState.features.get("water"), [])
	t.near(MapState.water_level(), -1.0, 0.001)
	UndoStack.clear()
	MapState.features = saved_feat
	MapState.stem = saved_stem
	MapState.has_session = saved_session
	MapState.dirty = saved_dirty
	if saved_session:
		MapState.mark_saved()
