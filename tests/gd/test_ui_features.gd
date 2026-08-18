extends RefCounted
## Features panel: enablement, add/remove, paint-region arming, session reload.


func run(t) -> void:
	await _enablement(t)
	await _add_remove_paint(t)
	await _populate_from_session(t)
	await _help(t)


func _enablement(t) -> void:
	var snap := _snap()
	UndoStack.clear()
	MapState.has_session = false
	MapState.features = {"water": [], "plants": []}
	MapState.masks.clear()
	ToolState.clear_mask_target()

	var panel: Node = load("res://project/ui/features/FeaturesPanel.tscn").instantiate()
	t.tree.root.add_child(panel)
	await t.tree.process_frame

	t.ok(_btn(panel, "AddWater").disabled, "Add water locked with no session")
	t.ok(_btn(panel, "AddPlant").disabled, "Add plant locked with no session")
	t.ok(_btn(panel, "RemoveWater").disabled)
	t.ok(_btn(panel, "RemovePlant").disabled)
	t.ok(_btn(panel, "PaintRegion").disabled, "paint locked with no session")
	t.ok("Open a map" in _btn(panel, "AddWater").tooltip_text)
	t.ok("Open a map" in _btn(panel, "PaintRegion").tooltip_text)

	MapState.has_session = true
	MapState.stem = "testmap"
	MapState.session_changed.emit()
	await t.tree.process_frame
	t.ok(_btn(panel, "AddWater").disabled, "Add locked without heightmap")
	t.ok("heightmap" in _btn(panel, "AddWater").tooltip_text.to_lower())
	t.ok("Select a water" in _btn(panel, "RemoveWater").tooltip_text or "select a water" in _btn(panel, "RemoveWater").tooltip_text.to_lower())

	panel.queue_free()
	await t.tree.process_frame
	_restore(snap)


func _add_remove_paint(t) -> void:
	var snap := _snap()
	var tmp: String = OS.get_temp_dir().path_join("bz_ui_feat_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	UndoStack.clear()
	ToolState.clear_mask_target()
	MapState.has_session = true
	MapState.session_dir = tmp
	MapState.stem = "testmap"
	MapState.features = {"water": [], "plants": []}
	MapState.masks.clear()
	MapState.dirty = {}
	MapState.field = HeightField.new()
	MapState.field.grid_x = 8
	MapState.field.grid_z = 8
	MapState.field.heights.resize(64)
	MapState.field.heights.fill(1000)
	MapState.mark_saved()

	var panel: Node = load("res://project/ui/features/FeaturesPanel.tscn").instantiate()
	t.tree.root.add_child(panel)
	await t.tree.process_frame

	t.ok(not _btn(panel, "AddWater").disabled, "Add water enabled with a heightmap")
	_btn(panel, "AddWater").pressed.emit()
	await t.tree.process_frame
	t.eq((MapState.features.get("water", []) as Array).size(), 1, "Add water writes features")
	t.eq(MapState.features["water"][0].get("stem"), "water1")
	t.eq(ToolState.mask_stem, "water1", "new water is the mask target")
	t.eq(ToolState.mask_kind, "water")
	t.ok(not _btn(panel, "PaintRegion").disabled, "paint enables with a selection")
	t.ok(not _btn(panel, "RemoveWater").disabled)

	_btn(panel, "AddPlant").pressed.emit()
	await t.tree.process_frame
	t.eq((MapState.features.get("plants", []) as Array).size(), 1)
	t.eq(MapState.features["plants"][0].get("density"), 260)
	t.eq(ToolState.mask_kind, "plants")
	t.ok(not _btn(panel, "RemovePlant").disabled)
	t.ok(_btn(panel, "RemoveWater").disabled, "water remove locks when a plant is selected")

	var paint: Button = _btn(panel, "PaintRegion")
	paint.button_pressed = true
	t.ok(ToolState.is_mask_painting(), "Paint region arms mask painting")
	paint.button_pressed = false
	t.ok(not ToolState.is_mask_painting())

	_btn(panel, "RemovePlant").pressed.emit()
	await t.tree.process_frame
	t.eq((MapState.features.get("plants", []) as Array).size(), 0)
	t.eq(ToolState.mask_stem, "", "remove clears the mask target")
	t.ok(_btn(panel, "PaintRegion").disabled, "paint locks with no selection")

	t.ok(UndoStack.can_undo(), "add/remove went through undo")
	UndoStack.undo()
	await t.tree.process_frame
	t.eq((MapState.features.get("plants", []) as Array).size(), 1, "undo restore plant")

	panel.queue_free()
	await t.tree.process_frame
	_rm_rf(tmp)
	_restore(snap)


func _populate_from_session(t) -> void:
	var snap := _snap()
	var tmp: String = OS.get_temp_dir().path_join("bz_ui_feat_load_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	UndoStack.clear()
	ToolState.clear_mask_target()
	MapState.has_session = true
	MapState.session_dir = tmp
	MapState.stem = "testmap"
	MapState.field = HeightField.new()
	MapState.field.grid_x = 4
	MapState.field.grid_z = 4
	MapState.field.heights.resize(16)
	MapState.field.heights.fill(800)
	MapState.features = {
		"water": [{
			"stem": "wtr1", "level_m": 70.0, "mask": "masks/wtr1.u8", "variant_scope": "_S",
		}],
		"plants": [{
			"stem": "plnt1", "mask": "masks/plnt1.u8", "density": 16, "seed": 7,
		}],
	}
	MapState.masks.clear()
	MapState.create_mask("wtr1")
	MapState.paint_mask_rect("wtr1", 0, 0, 2, 2, 255)
	MapState.create_mask("plnt1")
	MapState.persist()
	MapState.masks.clear()
	MapState.features = {"water": [], "plants": []}

	var panel: Node = load("res://project/ui/features/FeaturesPanel.tscn").instantiate()
	t.tree.root.add_child(panel)
	await t.tree.process_frame
	MapState.load_features_and_masks()
	await t.tree.process_frame
	t.eq((MapState.features.get("water", []) as Array).size(), 1)
	t.eq((MapState.features.get("plants", []) as Array).size(), 1)
	t.eq(int(MapState.get_mask("wtr1")[0]), 255)
	var water_list: Node = panel.find_child("WaterList", true, false)
	var plant_list: Node = panel.find_child("PlantList", true, false)
	t.ok(water_list.get_node_or_null("WaterRow_wtr1") != null, "water row rebuilt from session")
	t.ok(plant_list.get_node_or_null("PlantRow_plnt1") != null, "plant row rebuilt from session")
	var level: SpinBox = water_list.find_child("Level", true, false)
	t.ok(level != null)
	t.near(level.value, 70.0, 0.001)
	var density: SpinBox = plant_list.find_child("Density", true, false)
	t.eq(int(density.value), 16)
	var seed: SpinBox = plant_list.find_child("Seed", true, false)
	t.eq(int(seed.value), 7)

	panel.queue_free()
	await t.tree.process_frame
	_rm_rf(tmp)
	_restore(snap)


func _help(t) -> void:
	var help: Node = load("res://project/ui/help/HelpWindow.tscn").instantiate()
	t.tree.root.add_child(help)
	await t.tree.process_frame
	help.refresh()
	var body: RichTextLabel = help.find_child("Body", true, false)
	t.ok("Paint region" in body.text, "help lists Paint region")
	t.ok("Alt+LMB" in body.text, "help lists Alt+LMB erase")
	help.queue_free()
	await t.tree.process_frame


func _btn(root: Node, name: String) -> Button:
	return root.find_child(name, true, false) as Button


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
