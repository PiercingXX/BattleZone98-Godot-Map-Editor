extends RefCounted
## Chunked raster undo (RasterChunks) and CompositeCommand.
##
## The other stroke tests use grids smaller than one 64x64 undo chunk, so they
## never exercise the stitching. These grids are deliberately multi-chunk, and
## the end-to-end pass saves the shipped .hg2 four ways to prove undo/redo is
## byte-clean on real template data.


func run(t) -> void:
	var snap := _snap()
	_multichunk_height(t)
	_payload_scale(t)
	_clone_overlap(t)
	_multichunk_paint(t)
	_composite(t)
	_save_bytes(t)
	_restore(snap)


func _multichunk_height(t) -> void:
	_prep()
	var g := 200
	var field := _flat(g, g, 200)
	# Inherited oddities the editor must never rewrite: a raw over the 4095
	# write ceiling (stock ulltst96 measures 7630) and a word carrying flag
	# bits. One pair sits inside the brush footprint, one well outside.
	field.heights[5 * g + 5] = 7630
	field.heights[6 * g + 5] = (7 << 13) | 1234
	field.heights[150 * g + 150] = 7630
	field.heights[151 * g + 150] = (5 << 13) | 4095
	MapState.field = field
	var before := field.heights.duplicate()

	var sculpt := SculptTool.new()
	sculpt.mode = "raise"
	sculpt.radius_m = 40.0
	sculpt.strength = 1.0
	sculpt.falloff = 0.5
	# A chunk is 64 cells = 320 m; this drag crosses several.
	sculpt.begin_stroke(field, 100.0, 100.0, false)
	for i in 40:
		sculpt.stamp(field, 100.0 + float(i) * 20.0, 100.0 + float(i) * 20.0)
	var cmd = sculpt.end_stroke(field)
	t.ok(cmd != null, "drag produced a command")
	if cmd == null:
		return
	var after := field.heights.duplicate()
	t.ne(after, before, "drag changed heights")
	t.ok(cmd.regions.size() > 1, "drag spans several chunks (%d regions)" % cmd.regions.size())

	UndoStack.clear()
	UndoStack.push(cmd, true)
	UndoStack.undo()
	t.eq(field.heights, before, "undo restores the grid exactly")
	t.eq(field.heights[5 * g + 5], 7630, "out-of-range cell inside the brush survives")
	t.eq(field.heights[6 * g + 5], (7 << 13) | 1234, "flag bits inside the brush survive")
	t.eq(field.heights[150 * g + 150], 7630, "out-of-range cell outside survives")
	UndoStack.redo()
	t.eq(field.heights, after, "redo restores the stroke exactly")
	UndoStack.undo()
	UndoStack.redo()
	t.eq(field.heights, after, "a second undo/redo cycle is stable")
	UndoStack.clear()


func _payload_scale(t) -> void:
	_prep()
	var g := 512
	var field := _flat(g, g, 200)
	MapState.field = field
	var sculpt := SculptTool.new()
	sculpt.mode = "raise"
	sculpt.radius_m = 40.0
	sculpt.strength = 1.0
	sculpt.falloff = 0.5
	sculpt.begin_stroke(field, 1000.0, 1000.0, false)
	var one = sculpt.end_stroke(field)
	t.ok(one != null, "single stamp produced a command")
	if one == null:
		return
	# A 40 m stamp is 17x17 cells: kilobytes, not the 1 MB the grid weighs.
	t.ok(one.cost_bytes() < 64 * 1024, "single stamp costs %d bytes" % one.cost_bytes())

	sculpt.begin_stroke(field, 100.0, 100.0, false)
	for i in 100:
		sculpt.stamp(field, 100.0 + float(i) * 25.0, 100.0 + float(i) * 25.0)
	var drag = sculpt.end_stroke(field)
	t.ok(drag != null, "corner-to-corner drag produced a command")
	if drag == null:
		return
	# The bounding rect of that drag is nearly the whole map; chunks are not.
	t.ok(
		drag.cost_bytes() < g * g * 2 * 4 / 2,
		"drag costs %d bytes, well under a bounding-rect diff" % drag.cost_bytes()
	)
	UndoStack.clear()


func _clone_overlap(t) -> void:
	_prep()
	var g := 200
	var field := _flat(g, g, 200)
	for z in range(20, 40):
		for x in range(20, 40):
			field.heights[z * g + x] = 400
	MapState.field = field
	var before := field.heights.duplicate()
	var saved_src := ToolState.clone_source_m
	var saved_mats := ToolState.clone_materials
	ToolState.set_clone_source(150.0, 150.0)
	ToolState.set_clone_materials(false)
	var sculpt := SculptTool.new()
	sculpt.mode = "clone"
	sculpt.radius_m = 60.0
	sculpt.strength = 1.0
	sculpt.falloff = 0.0
	# Destination overlaps the source, so the kernel must read pre-stroke cells.
	sculpt.begin_stroke(field, 190.0, 190.0, false)
	sculpt.stamp(field, 210.0, 210.0)
	var cmd = sculpt.end_stroke(field)
	t.ok(cmd != null, "clone stroke produced a command")
	if cmd != null:
		var after := field.heights.duplicate()
		t.ne(after, before, "clone changed heights")
		UndoStack.clear()
		UndoStack.push(cmd, true)
		UndoStack.undo()
		t.eq(field.heights, before, "clone undo restores exactly")
		UndoStack.redo()
		t.eq(field.heights, after, "clone redo restores exactly")
	UndoStack.clear()
	ToolState.set_clone_materials(saved_mats)
	if saved_src.is_finite():
		ToolState.set_clone_source(saved_src.x, saved_src.y)


func _multichunk_paint(t) -> void:
	_prep()
	var g := 200
	MapState.field = _flat(g * 4, g * 4, 200)
	MapState.mat_grid_x = g
	MapState.mat_grid_z = g
	MapState.materials = PackedInt32Array()
	MapState.materials.resize(g * g)
	for i in g * g:
		MapState.materials[i] = (i % 7) << 8
	var before := MapState.materials.duplicate()
	var sculpt := SculptTool.new()
	sculpt.mode = "paint"
	sculpt.paint_material = 5
	sculpt.radius_m = 60.0
	sculpt.falloff = 0.0
	sculpt.begin_stroke(MapState.field, 200.0, 200.0, true)
	for i in 60:
		sculpt.stamp(MapState.field, 200.0 + float(i) * 40.0, 200.0 + float(i) * 40.0)
	var cmd = sculpt.end_paint()
	t.ok(cmd != null, "paint drag produced a command")
	if cmd == null:
		return
	t.ok(cmd.regions.size() > 1, "paint spans several chunks (%d regions)" % cmd.regions.size())
	var after := MapState.materials.duplicate()
	t.ne(after, before, "paint changed materials")
	UndoStack.clear()
	UndoStack.push(cmd, true)
	UndoStack.undo()
	t.eq(MapState.materials, before, "paint undo restores exactly")
	UndoStack.redo()
	t.eq(MapState.materials, after, "paint redo restores exactly")
	UndoStack.clear()


func _composite(t) -> void:
	UndoStack.clear()
	var log: Array = []
	var a := _Spy.new()
	a.tag = "a"
	a.log = log
	var b := _Spy.new()
	b.tag = "b"
	b.log = log
	var pair := CompositeCommand.of([a, b])
	pair.do()
	t.eq(log, ["do a", "do b"], "do runs forward")
	log.clear()
	pair.undo()
	t.eq(log, ["undo b", "undo a"], "undo runs in reverse")
	t.eq(pair.cost_bytes(), 2222, "cost sums children")
	t.eq(pair.size(), 2)
	t.ok(not pair.is_empty())
	t.eq(CompositeCommand.of([_Bare.new()]).cost_bytes(), 1024, "unpriced child charged 1024")

	var h1 := HeightStrokeCommand.new()
	h1.tool = "raise"
	var h2 := HeightStrokeCommand.new()
	h2.tool = "raise"
	var mat := MaterialStrokeCommand.new()
	t.eq(CompositeCommand.of([h1]).describe(), "raise stroke", "one child lends its label")
	t.eq(CompositeCommand.of([h1, h2]).describe(), "2 × raise stroke", "uniform children fold")
	t.eq(CompositeCommand.of([h1, mat]).describe(), "raise stroke +1 more", "mixed children")
	t.eq(CompositeCommand.of([h1, mat], "auto-fix").describe(), "auto-fix", "explicit label wins")
	t.eq(CompositeCommand.new().describe(), "batch", "empty composite still names itself")

	# Two strokes, one history entry, one undo.
	_prep()
	var saved_tool := ToolState.tool
	ToolState.set_tool("raise")
	var g := 100
	var field := _flat(g, g, 200)
	MapState.field = field
	var before := field.heights.duplicate()
	var sculpt := SculptTool.new()
	sculpt.mode = "raise"
	sculpt.radius_m = 30.0
	sculpt.strength = 1.0
	sculpt.begin_stroke(field, 100.0, 100.0, false)
	var first = sculpt.end_stroke(field)
	sculpt.begin_stroke(field, 300.0, 300.0, false)
	var second = sculpt.end_stroke(field)
	var after := field.heights.duplicate()
	var batch := CompositeCommand.of([first, second])
	UndoStack.push(batch, true)
	t.eq(UndoStack.command_count(), 1, "batch is one history entry")
	t.eq(UndoStack.describe_command(batch), "2 × raise stroke", "tool name reaches batched strokes")
	UndoStack.undo()
	t.eq(field.heights, before, "batch undo restores both strokes")
	t.ok(not UndoStack.can_undo(), "one undo covers the batch")
	UndoStack.redo()
	t.eq(field.heights, after, "batch redo reapplies both strokes")
	UndoStack.clear()
	ToolState.set_tool(saved_tool)


## Open the shipped template four ways and compare the saved .hg2 bytes.
func _save_bytes(t) -> void:
	var root := OS.get_temp_dir().path_join("bz-undo-chunks")
	_rm_rf(root)
	DirAccess.make_dir_recursive_absolute(root)
	var trn := ProjectSettings.globalize_path("res://templates/highlands-4team/xthiland.trn")
	var clean := _save_variant(t, root, "clean", trn, 0)
	var kept := _save_variant(t, root, "kept", trn, 1)
	var cycled := _save_variant(t, root, "cycled", trn, 2)
	var undone := _save_variant(t, root, "undone", trn, 3)
	if clean.is_empty() or kept.is_empty() or cycled.is_empty() or undone.is_empty():
		_rm_rf(root)
		return
	t.ne(kept, clean, "the stroke reaches the shipped .hg2")
	t.eq(cycled, kept, "undo -> redo -> save is byte-identical to save-without-undo")
	t.eq(undone, clean, "stroke -> undo -> save is byte-identical to the untouched save")
	_rm_rf(root)


## mode 0 = no edit, 1 = stroke, 2 = stroke + undo + redo, 3 = stroke + undo.
func _save_variant(t, root: String, name: String, trn: String, mode: int) -> PackedByteArray:
	var session := root.path_join("session-%s" % name)
	var out_dir := root.path_join("out-%s" % name)
	var opened: Dictionary = BzOpen.open_map(trn, session)
	if opened.get("ok") != true:
		t.fail("open template for %s: %s" % [name, str(opened)])
		return PackedByteArray()
	var manifest: Dictionary = BzSession.read_json(session.path_join("manifest.json"))
	var gx := int(manifest.get("grid_x", 0))
	var gz := int(manifest.get("grid_z", 0))
	if mode > 0:
		_prep()
		var field := HeightField.new()
		if field.load_r16(session.path_join("terrain.r16"), gx, gz) != OK:
			t.fail("load_r16 for %s" % name)
			return PackedByteArray()
		MapState.field = field
		var sculpt := SculptTool.new()
		sculpt.mode = "raise"
		sculpt.radius_m = 120.0
		sculpt.strength = 1.0
		sculpt.falloff = 0.4
		# Straddles the 256-sample zone boundary and several undo chunks.
		sculpt.begin_stroke(field, 1200.0, 1200.0, false)
		for i in 30:
			sculpt.stamp(field, 1200.0 + float(i) * 30.0, 1200.0 + float(i) * 30.0)
		var cmd = sculpt.end_stroke(field)
		if cmd == null:
			t.fail("stroke for %s produced no command" % name)
			return PackedByteArray()
		UndoStack.push(cmd, true)
		if mode >= 2:
			UndoStack.undo()
		if mode == 2:
			UndoStack.redo()
		field.write_r16(session.path_join("terrain.r16"))
		var dirty: Dictionary = BzSession.read_json(session.path_join("dirty.json"))
		dirty["terrain"] = true
		BzSession.write_json(session.path_join("dirty.json"), dirty)
		UndoStack.clear()
	var saved: Dictionary = BzSave.save_session(session, out_dir, "xthiland")
	if saved.get("ok") != true:
		t.fail("save %s: %s" % [name, str(saved)])
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(out_dir.path_join("xthiland.hg2"))


func _flat(gx: int, gz: int, raw: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	field.heights.fill(raw)
	return field


func _prep() -> void:
	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)
	MapState.clear_selection()
	MapState.objects = {}
	UndoStack.clear()


func _snap() -> Dictionary:
	return {
		"field": MapState.field,
		"objects": MapState.objects.duplicate(true),
		"materials": MapState.materials.duplicate(),
		"mgx": MapState.mat_grid_x,
		"mgz": MapState.mat_grid_z,
		"tool": ToolState.tool,
	}


func _restore(snap: Dictionary) -> void:
	UndoStack.clear()
	ToolState.set_symmetry(ToolState.SYMMETRY_OFF)
	ToolState.set_tool(str(snap["tool"]))
	MapState.clear_selection()
	MapState.field = snap["field"]
	MapState.objects = snap["objects"]
	MapState.materials = snap["materials"]
	MapState.mat_grid_x = snap["mgx"]
	MapState.mat_grid_z = snap["mgz"]


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


class _Spy:
	extends RefCounted
	var tag: String = ""
	var log: Array = []

	func do() -> void:
		log.append("do %s" % tag)

	func undo() -> void:
		log.append("undo %s" % tag)

	func cost_bytes() -> int:
		return 1111


class _Bare:
	extends RefCounted

	func do() -> void:
		pass

	func undo() -> void:
		pass
