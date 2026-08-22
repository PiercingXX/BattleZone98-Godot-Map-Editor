extends RefCounted
## MapState's scatter wiring: load / sync / reset, plus the two guards it is
## only worth having if they hold — a map with no scatter block must persist
## exactly as it did before painted scatter existed (C6), and a legacy
## count-and-seed plants entry must not be adopted as one.


func run(t) -> void:
	_test_no_scatter_is_untouched(t)
	_test_legacy_entry_not_adopted(t)
	_test_round_trip(t)
	_test_clear_resets(t)


## The whole of C6 for this feature: adding sync_scatter() to persist() must
## be invisible to a session that never painted any.
func _test_no_scatter_is_untouched(t) -> void:
	var snap := _snap()
	var tmp: String = OS.get_temp_dir().path_join("bz_scat_none_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_prep_session(tmp, 8, 8)
	MapState.add_water_feature()
	MapState.add_plant_feature()
	MapState.paint_mask_rect("plant1", 2, 2, 3, 3, 255)
	MapState.persist()
	var feat_a := FileAccess.get_file_as_bytes(tmp.path_join("features.json"))
	var mask_a := FileAccess.get_file_as_bytes(tmp.path_join("masks").path_join("plant1.u8"))
	t.eq(MapState.scatter_stem, "", "no scatter feature, no stem")
	var disk: Variant = JSON.parse_string(feat_a.get_string_from_utf8())
	t.ok(not (disk["plants"][0] as Dictionary).has("scatter"), "no scatter block written")

	MapState.persist()
	t.eq(FileAccess.get_file_as_bytes(tmp.path_join("features.json")), feat_a,
		"features.json byte-identical without scatter")
	t.eq(FileAccess.get_file_as_bytes(tmp.path_join("masks").path_join("plant1.u8")), mask_a,
		"plant mask byte-identical without scatter")

	# ...and a reload must not turn a legacy entry into a painted one, which
	# would put its mesh on the instance path and change what the map ships.
	MapState.load_features_and_masks()
	t.eq(MapState.scatter_stem, "", "reload of a legacy map adopts nothing")
	MapState.persist()
	var again: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(tmp.path_join("features.json"))
	)
	t.ok(not (again["plants"][0] as Dictionary).has("scatter"),
		"still no scatter block after a reload")
	t.eq(FileAccess.get_file_as_bytes(tmp.path_join("masks").path_join("plant1.u8")), mask_a,
		"plant mask byte-identical across the reload")
	_rm_rf(tmp)
	_restore(snap)


func _test_legacy_entry_not_adopted(t) -> void:
	var snap := _snap()
	var tmp: String = OS.get_temp_dir().path_join("bz_scat_leg_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_prep_session(tmp, 8, 8)
	MapState.features = {"water": [], "plants": [
		{"stem": "plant1", "mask": "masks/plant1.u8", "density": 260, "seed": 9},
	]}
	MapState.load_scatter()
	t.eq(MapState.scatter_stem, "", "count-and-seed entry stays on the old path")
	t.eq(MapState.scatter.seed, 0, "and does not lend its seed to the field")
	_rm_rf(tmp)
	_restore(snap)


func _test_round_trip(t) -> void:
	var snap := _snap()
	var tmp: String = OS.get_temp_dir().path_join("bz_scat_rt_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_prep_session(tmp, 8, 8)
	# Annotated, not inferred: an autoload's member types resolve in an order
	# the class registry decides, so `:=` here compiles or does not depending
	# on what else in the project declares a class_name.
	var rec: Dictionary = MapState.add_scatter_feature()
	t.eq(str(rec.get("stem", "")), "plant1")
	t.ok(rec.has("scatter"), "record carries a scatter block")
	t.eq(MapState.scatter_stem, "plant1")
	t.eq(MapState.scatter.mask.grid_x, 8, "field sized to the heightmap")
	t.eq(MapState.scatter.mask.values.size(), 64)
	t.eq(MapState.scatter.species.size(), 1, "a paintable slot exists")

	MapState.scatter.set_seed(1234)
	MapState.scatter.mask.set_slot(3, 4, 0)
	MapState.persist()
	var disk: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(tmp.path_join("features.json"))
	)
	var saved: Dictionary = disk["plants"][0]
	t.eq(saved.get("seed"), 1234, "seed written beside the block")
	t.eq((saved["scatter"] as Dictionary).get("seed"), 1234)
	t.eq(((saved["scatter"] as Dictionary)["species"] as Array).size(), 1)
	var raw := FileAccess.get_file_as_bytes(tmp.path_join("masks").path_join("plant1.u8"))
	t.eq(raw.size(), 64, "scatter mask is the feature mask")
	t.eq(int(raw[4 * 8 + 3]), ScatterMask.encode(0), "painted cell reached the file")

	MapState.masks.clear()
	MapState.features = {}
	MapState.scatter = ScatterField.new()
	MapState.scatter_stem = ""
	MapState.load_features_and_masks()
	t.eq(MapState.scatter_stem, "plant1", "reload adopts the painted entry")
	t.eq(MapState.scatter.seed, 1234)
	t.eq(MapState.scatter.species.size(), 1)
	t.eq(MapState.scatter.mask.slot_at(3, 4), 0, "painted cell survived the round trip")
	t.eq(MapState.scatter.mask.slot_at(0, 0), -1, "and nothing else was painted")
	t.eq(MapState.scatter.mask.occupied_chunks(), 1, "chunk bookkeeping recounted")
	_rm_rf(tmp)
	_restore(snap)


func _test_clear_resets(t) -> void:
	var snap := _snap()
	var tmp: String = OS.get_temp_dir().path_join("bz_scat_clr_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_prep_session(tmp, 8, 8)
	MapState.add_scatter_feature()
	MapState.scatter.mask.set_slot(1, 1, 0)
	MapState.clear()
	t.eq(MapState.scatter_stem, "", "close clears the stem")
	t.ok(MapState.scatter != null, "and leaves an empty field, not a null")
	t.eq(MapState.scatter.mask.values.size(), 0)
	t.eq(MapState.scatter.species.size(), 0)
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
	MapState.scatter = ScatterField.new()
	MapState.scatter_stem = ""
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
		"scatter": MapState.scatter,
		"sstem": MapState.scatter_stem,
	}


func _restore(snap: Dictionary) -> void:
	UndoStack.clear()
	ToolState.clear_mask_target()
	MapState.features = snap["feat"]
	MapState.stem = snap["stem"]
	MapState.has_session = snap["session"]
	MapState.dirty = snap["dirty"]
	MapState.masks = snap["masks"]
	MapState.session_dir = snap["dir"]
	MapState.field = snap["field"]
	MapState.scatter = snap["scatter"]
	MapState.scatter_stem = snap["sstem"]
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
