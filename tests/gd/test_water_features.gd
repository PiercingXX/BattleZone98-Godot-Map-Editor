extends RefCounted
## MapState water writes the docs/02 features.json shape.
## Masks: create / paint-rect / persist / reload; add/remove; stroke undo.


func run(t) -> void:
	_test_water_line(t)
	_test_mask_persist_reload(t)
	_test_features_add_remove(t)
	_test_mask_stroke_undo(t)


func _test_water_line(t) -> void:
	var saved_feat: Dictionary = MapState.features.duplicate(true)
	var saved_stem: String = MapState.stem
	var saved_session := MapState.has_session
	var saved_dirty: Dictionary = MapState.dirty.duplicate(true)
	var saved_masks: Dictionary = MapState.masks.duplicate(true)
	MapState.stem = "testmap"
	MapState.features = {"water": [], "plants": []}
	MapState.set_water_level(92.0)
	t.near(MapState.water_level(), 92.0, 0.001)
	var waters: Array = MapState.features.get("water", [])
	t.eq(waters.size(), 1, "one water feature")
	t.eq(waters[0].get("level_m"), 92.0)
	t.eq(waters[0].get("variant_scope"), "all")
	t.ok(str(waters[0].get("stem", "")).length() <= 8, "stem fits engine 8-char cap")
	t.ok(not waters[0].has("mask") or str(waters[0].get("mask", "")).is_empty(), "inspector water is whole-map")
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
	MapState.masks = saved_masks
	if saved_session:
		MapState.mark_saved()


func _test_mask_persist_reload(t) -> void:
	var snap := _snap()
	var tmp: String = OS.get_temp_dir().path_join("bz_feat_mask_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_prep_session(tmp, 8, 8)
	var rec := MapState.add_water_feature()
	t.eq(str(rec.get("stem", "")), "water1")
	t.eq(str(rec.get("mask", "")), "masks/water1.u8")
	t.eq(MapState.get_mask("water1").size(), 64, "mask is heightmap-sized")
	MapState.paint_mask_rect("water1", 1, 1, 2, 2, 255)
	var live := MapState.get_mask("water1")
	t.eq(int(live[1 * 8 + 1]), 255)
	t.eq(int(live[1 * 8 + 2]), 255)
	t.eq(int(live[2 * 8 + 1]), 255)
	t.eq(int(live[2 * 8 + 2]), 255)
	t.eq(int(live[0]), 0, "outside the rect stays 0")
	t.eq(MapState.dirty.get("features"), true)
	MapState.persist()
	var feat_path := tmp.path_join("features.json")
	t.ok(FileAccess.file_exists(feat_path), "features.json written")
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(feat_path))
	t.ok(typeof(disk) == TYPE_DICTIONARY)
	t.eq((disk.get("water", []) as Array).size(), 1)
	t.eq(disk["water"][0].get("stem"), "water1")
	t.eq(disk["water"][0].get("mask"), "masks/water1.u8")
	var mask_path := tmp.path_join("masks").path_join("water1.u8")
	t.ok(FileAccess.file_exists(mask_path), "mask u8 written")
	var raw := FileAccess.get_file_as_bytes(mask_path)
	t.eq(raw.size(), 64)
	t.eq(int(raw[1 * 8 + 1]), 255)
	t.eq(int(raw[0]), 0)
	var dirty_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(tmp.path_join("dirty.json")))
	t.eq(dirty_disk.get("features"), true, "persist notes features dirty")
	MapState.masks.clear()
	MapState.features = {}
	MapState.load_features_and_masks()
	t.eq((MapState.features.get("water", []) as Array).size(), 1, "reload restores water")
	t.eq(MapState.features["water"][0].get("stem"), "water1")
	var reloaded := MapState.get_mask("water1")
	t.eq(reloaded.size(), 64)
	t.eq(int(reloaded[1 * 8 + 1]), 255)
	t.eq(int(reloaded[2 * 8 + 2]), 255)
	t.eq(int(reloaded[0]), 0)
	_rm_rf(tmp)
	_restore(snap)


func _test_features_add_remove(t) -> void:
	var snap := _snap()
	var tmp: String = OS.get_temp_dir().path_join("bz_feat_ar_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_prep_session(tmp, 4, 4)
	var w1 := MapState.add_water_feature()
	var w2 := MapState.add_water_feature()
	t.eq(w1.get("stem"), "water1")
	t.eq(w2.get("stem"), "water2")
	t.eq(w1.get("variant_scope"), "all")
	t.ok(w1.get("level_m") >= 0.0)
	var p1 := MapState.add_plant_feature()
	t.eq(p1.get("stem"), "plant1")
	t.eq(p1.get("density"), 260)
	t.eq(p1.get("seed"), 0)
	t.eq(p1.get("mask"), "masks/plant1.u8")
	t.eq((MapState.features.get("water", []) as Array).size(), 2)
	t.eq((MapState.features.get("plants", []) as Array).size(), 1)
	MapState.set_feature_field("plants", "plant1", "density", 80)
	MapState.set_feature_field("plants", "plant1", "seed", 7)
	t.eq(MapState.find_feature("plants", "plant1").get("density"), 80)
	t.eq(MapState.find_feature("plants", "plant1").get("seed"), 7)
	var err := MapState.validate_feature_stem("water1", "plant1")
	t.ok(not err.is_empty(), "duplicate stem rejected")
	t.ok(MapState.validate_feature_stem("okstem", "").is_empty(), "valid stem")
	t.ok(not MapState.validate_feature_stem("too_long!", "").is_empty(), "bad stem rejected")
	MapState.remove_feature("water", "water1")
	t.eq((MapState.features.get("water", []) as Array).size(), 1)
	t.eq(MapState.features["water"][0].get("stem"), "water2")
	t.eq(MapState.get_mask("water1").size(), 0, "removed mask dropped")
	MapState.persist()
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(tmp.path_join("features.json")))
	t.eq((disk.get("water", []) as Array).size(), 1)
	t.eq(disk["water"][0].get("stem"), "water2")
	t.eq((disk.get("plants", []) as Array).size(), 1)
	t.eq(disk["plants"][0].get("density"), 80)
	t.eq(disk["plants"][0].get("seed"), 7)
	MapState.remove_feature("plants", "plant1")
	t.eq((MapState.features.get("plants", []) as Array).size(), 0)
	_rm_rf(tmp)
	_restore(snap)


func _test_mask_stroke_undo(t) -> void:
	var snap := _snap()
	var tmp: String = OS.get_temp_dir().path_join("bz_feat_stroke_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_prep_session(tmp, 16, 16)
	var rec := MapState.add_water_feature()
	var stem := str(rec.get("stem", "water1"))
	var field: HeightField = MapState.field
	var sculpt := SculptTool.new()
	sculpt.radius_m = 20.0
	sculpt.falloff = 0.5
	sculpt.shape = "circle"
	sculpt.begin_mask_stroke(field, 20.0, 20.0, stem, 255)
	sculpt.stamp(field, 20.0, 20.0)
	var cmd = sculpt.end_mask_paint()
	t.ok(cmd != null, "mask stroke produced a command")
	var cx := int(floor(20.0 / HeightField.CELL_M))
	var cz := int(floor(20.0 / HeightField.CELL_M))
	var idx := cz * 16 + cx
	t.eq(int(MapState.get_mask(stem)[idx]), 255, "center cell painted")
	UndoStack.clear()
	MapState.has_session = true
	MapState.mark_saved()
	UndoStack.push(cmd, true)
	t.ok(MapState.unsaved, "mask stroke dirties")
	UndoStack.undo()
	t.eq(int(MapState.get_mask(stem)[idx]), 0, "undo clears painted cell")
	t.ok(not MapState.unsaved, "undo mask stroke returns to saved generation")
	UndoStack.redo()
	t.eq(int(MapState.get_mask(stem)[idx]), 255, "redo restores paint")
	# Erase stroke is a second undo step.
	sculpt.begin_mask_stroke(field, 20.0, 20.0, stem, 0)
	sculpt.stamp(field, 20.0, 20.0)
	var erase_cmd = sculpt.end_mask_paint()
	t.ok(erase_cmd != null, "erase stroke produced a command")
	UndoStack.push(erase_cmd, true)
	t.eq(int(MapState.get_mask(stem)[idx]), 0, "erase cleared the cell")
	UndoStack.undo()
	t.eq(int(MapState.get_mask(stem)[idx]), 255, "undo erase restores paint")
	UndoStack.clear()
	_rm_rf(tmp)
	_restore(snap)


func _prep_session(tmp: String, gx: int, gz: int) -> void:
	UndoStack.clear()
	ToolState.clear_mask_target()
	MapState.has_session = true
	MapState.session_dir = tmp
	MapState.stem = "testmap"
	MapState.features = {"water": [], "plants": []}
	MapState.masks.clear()
	MapState.dirty = {}
	MapState.field = HeightField.new()
	MapState.field.grid_x = gx
	MapState.field.grid_z = gz
	MapState.field.heights.resize(gx * gz)
	MapState.field.heights.fill(1000)
	MapState.mark_saved()


func _snap() -> Dictionary:
	return {
		"feat": MapState.features.duplicate(true),
		"stem": MapState.stem,
		"session": MapState.has_session,
		"dirty": MapState.dirty.duplicate(true),
		"masks": MapState.masks.duplicate(true),
		"dir": MapState.session_dir,
		"field": MapState.field,
		"kind": ToolState.mask_kind,
		"mstem": ToolState.mask_stem,
		"paint": ToolState.mask_paint,
	}


func _restore(snap: Dictionary) -> void:
	UndoStack.clear()
	ToolState.clear_mask_target()
	if not str(snap.get("mstem", "")).is_empty():
		ToolState.set_mask_target(str(snap.get("kind", "")), str(snap.get("mstem", "")))
		ToolState.set_mask_paint(bool(snap.get("paint", false)))
	MapState.features = snap["feat"]
	MapState.stem = snap["stem"]
	MapState.has_session = snap["session"]
	MapState.dirty = snap["dirty"]
	MapState.masks = snap["masks"]
	MapState.session_dir = snap["dir"]
	MapState.field = snap["field"]
	if snap["session"]:
		MapState.mark_saved()


func _rm_rf(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var child := path.path_join(name)
		if dir.current_is_dir():
			_rm_rf(child)
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	DirAccess.remove_absolute(path)
