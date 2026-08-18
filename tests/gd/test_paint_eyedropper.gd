extends RefCounted
## Paint eyedropper: sample material, swatch highlight, log line, help.


func run(t) -> void:
	await _sample(t)
	await _dispatch(t)
	await _help(t)


func _sample(t) -> void:
	var saved_session := MapState.has_session
	var saved_tool := ToolState.tool
	var saved_mat := ToolState.paint_material
	var saved_world := MapState.world
	var saved_worlds: Array = MapState.worlds.duplicate(true)
	var saved_x: int = MapState.mat_grid_x
	var saved_z: int = MapState.mat_grid_z
	var saved_mats: PackedInt32Array = MapState.materials.duplicate()

	MapState.has_session = true
	MapState.world = "mars"
	MapState.worlds = [{
		"id": "mars",
		"texture_types": [{"index": 5, "name": "Rocky Sand"}],
	}]
	MapState.mat_grid_x = 8
	MapState.mat_grid_z = 8
	MapState.materials = PackedInt32Array()
	MapState.materials.resize(64)
	MapState.materials.fill(0)
	MapState.set_material(2, 3, 5)
	ToolState.set_paint_material(0)
	ToolState.set_tool("paint")

	var pal: Node = load("res://project/ui/palette/PalettePanel.tscn").instantiate()
	t.tree.root.add_child(pal)
	await t.tree.process_frame
	pal.refresh_swatches()

	t.eq(MapState.material_at(40.0, 60.0), 5, "cell under the cursor")
	t.eq(MaterialPalette.type_name(5), "Rocky Sand")

	var swatches: GridContainer = pal.find_child("Swatches", true, false)
	t.eq(swatches.get_child_count(), 16)
	var inactive := Color(1, 1, 1, 0.15)
	var active := Color(0.95, 0.85, 0.25)
	t.ok(_swatch_border(swatches, 0).is_equal_approx(active), "mat 0 starts selected")

	var msg: String = pal.sample_material(MapState.material_at(40.0, 60.0))
	t.eq(msg, "sampled mat 5 (Rocky Sand)")
	t.eq(ToolState.paint_material, 5, "sampled index is the active paint material")
	t.eq(ToolState.tool, "paint", "eyedropper does not leave paint")
	t.ok(_swatch_border(swatches, 5).is_equal_approx(active), "sampled swatch is selected")
	t.ok(_swatch_border(swatches, 0).is_equal_approx(inactive), "previous swatch is cleared")

	# Same-cell resample still logs and keeps the highlight.
	t.eq(pal.sample_material(5), "sampled mat 5 (Rocky Sand)")
	t.eq(ToolState.paint_material, 5)
	t.ok(_swatch_border(swatches, 5).is_equal_approx(active))

	pal.queue_free()
	await t.tree.process_frame
	MapState.has_session = saved_session
	MapState.world = saved_world
	MapState.worlds = saved_worlds
	MapState.mat_grid_x = saved_x
	MapState.mat_grid_z = saved_z
	MapState.materials = saved_mats
	if saved_x > 0 and saved_z > 0:
		MapState.upload_materials()
	ToolState.set_tool(saved_tool if saved_tool != "" else "fly")
	ToolState.set_paint_material(saved_mat)


func _dispatch(t) -> void:
	var saved_session := MapState.has_session
	var saved_worker: Callable = Backend.test_worker
	var saved_tool := ToolState.tool
	var saved_root := Settings.game_root
	UndoStack.clear()
	MapState.has_session = false
	Backend.test_worker = _stub

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	t.tree.root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 8000
	while Backend.busy or not Backend._queue.is_empty():
		await t.tree.process_frame
		if Time.get_ticks_msec() > deadline:
			t.fail("backend did not drain after main.tscn boot")
			break
	await t.tree.process_frame

	ToolState.set_tool("paint")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.alt_pressed = true
	scene._on_view_gui_input(ev)
	t.ok(not bool(scene.get("_stroking")), "Alt+LMB does not start a paint stroke")
	var console: Node = scene.find_child("Console", true, false)
	t.ok(console != null and "nothing to sample" in str(console.get("text")), "miss logs instead of painting")

	scene.queue_free()
	await t.tree.process_frame
	deadline = Time.get_ticks_msec() + 4000
	while Backend.busy or not Backend._queue.is_empty():
		await t.tree.process_frame
		if Time.get_ticks_msec() > deadline:
			break
	Backend.test_worker = saved_worker
	MapState.has_session = saved_session
	Settings.game_root = saved_root
	UndoStack.clear()
	ToolState.set_tool(saved_tool if saved_tool != "" else "fly")


func _stub(_verb: String, _args: PackedStringArray) -> Dictionary:
	return {"ok": true, "installs": [], "warnings": [], "worlds": [], "classes": []}


func _help(t) -> void:
	var help: Node = load("res://project/ui/help/HelpWindow.tscn").instantiate()
	t.tree.root.add_child(help)
	await t.tree.process_frame
	var body: RichTextLabel = help.find_child("Body", true, false)
	t.ok("eyedropper" in body.text.to_lower(), "help lists the eyedropper")
	t.ok("Alt+LMB" in body.text, "help lists Alt+LMB")
	help.queue_free()
	await t.tree.process_frame


func _swatch_border(swatches: GridContainer, idx: int) -> Color:
	var sb := (swatches.get_child(idx) as Button).get_theme_stylebox("normal") as StyleBoxFlat
	if sb == null:
		return Color(0, 0, 0, 0)
	return sb.border_color
