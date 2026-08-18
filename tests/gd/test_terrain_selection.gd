extends RefCounted
## Terrain selection mask: ops, wand flood, constrained stamps, select-by-material.


func run(t) -> void:
	var snap := _snap()
	_ops(t)
	_wand(t)
	_constrained_stamp(t)
	_select_by_material(t)
	_clone_stamp(t)
	_restore(snap)


func _ops(t) -> void:
	_prep_field(16, 16, 200)
	t.ok(MapState.selection_empty(), "starts empty")
	t.eq(MapState.selection_factor(3, 3), 1.0, "empty = everything editable")
	MapState.rect_terrain_selection(2, 2, 5, 5, MapState.SEL_REPLACE)
	t.ok(not MapState.selection_empty())
	t.eq(MapState.selection_cell_count(), 16, "4×4 replace")
	t.eq(int(MapState.terrain_selection[2 * 16 + 2]), 255)
	t.eq(int(MapState.terrain_selection[1 * 16 + 1]), 0)
	t.eq(MapState.selection_factor(2, 2), 1.0)
	t.eq(MapState.selection_factor(1, 1), 0.0)
	t.near(MapState.selection_area_m2(), 16.0 * 25.0, 0.01)

	MapState.rect_terrain_selection(4, 4, 7, 7, MapState.SEL_ADD)
	t.eq(int(MapState.terrain_selection[4 * 16 + 4]), 255, "overlap stays selected")
	t.eq(int(MapState.terrain_selection[7 * 16 + 7]), 255, "add extends")
	t.eq(int(MapState.terrain_selection[2 * 16 + 2]), 255, "original remains")
	var after_add := MapState.selection_cell_count()
	t.ok(after_add > 16, "union grew")

	MapState.rect_terrain_selection(2, 2, 3, 3, MapState.SEL_SUBTRACT)
	t.eq(int(MapState.terrain_selection[2 * 16 + 2]), 0, "subtract clears")
	t.ok(MapState.selection_cell_count() < after_add, "subtract shrinks count")

	var before_inv := MapState.selection_cell_count()
	MapState.invert_terrain_selection()
	t.eq(MapState.selection_cell_count(), 16 * 16 - before_inv, "invert flips membership")
	MapState.invert_terrain_selection()
	t.eq(MapState.selection_cell_count(), before_inv, "invert is involution")

	MapState.clear_selection()
	t.ok(MapState.selection_empty())
	MapState.select_all_terrain()
	t.eq(MapState.selection_cell_count(), 256)
	t.eq(MapState.selection_factor(0, 0), 1.0)
	MapState.invert_terrain_selection()
	t.ok(MapState.selection_empty(), "invert of all-selected collapses to empty")

	MapState.rect_terrain_selection(4, 4, 11, 11, MapState.SEL_REPLACE)
	var hard := MapState.selection_cell_count()
	MapState.feather_terrain_selection(5.0)  # 1 cell
	t.ok(MapState.selection_cell_count() > hard, "feather bleeds past the hard edge")
	t.ok(int(MapState.terrain_selection[4 * 16 + 4]) < 255, "corner is softened")
	t.eq(int(MapState.terrain_selection[7 * 16 + 7]), 255, "interior stays full")
	t.eq(int(MapState.terrain_selection[0]), 0, "far cells stay unselected")

	MapState.rect_terrain_selection(6, 6, 6, 6, MapState.SEL_REPLACE)
	t.eq(MapState.selection_cell_count(), 1)
	MapState.grow_terrain_selection(1)
	t.eq(MapState.selection_cell_count(), 9, "grow 1 is a 3×3 square")
	MapState.shrink_terrain_selection(1)
	t.eq(MapState.selection_cell_count(), 1, "shrink 1 restores the seed")

	MapState.clear_selection()
	MapState.grow_terrain_selection(2)
	t.ok(MapState.selection_empty(), "grow of empty is a no-op")
	MapState.feather_terrain_selection(10.0)
	t.ok(MapState.selection_empty(), "feather of empty is a no-op")
	MapState.rect_terrain_selection(0, 0, 1, 1, MapState.SEL_SUBTRACT)
	t.ok(MapState.selection_empty(), "subtract from empty is a no-op")

	MapState.stamp_terrain_selection(20.0, 20.0, 8.0, 0.0, "circle", MapState.SEL_ADD)
	t.ok(not MapState.selection_empty(), "brush-select add")
	t.eq(int(MapState.terrain_selection[4 * 16 + 4]), 255, "brush centre is full")
	var mid := int(MapState.terrain_selection[4 * 16 + 5])
	t.ok(mid > 0, "brush covers a neighbour")
	MapState.stamp_terrain_selection(20.0, 20.0, 8.0, 0.0, "circle", MapState.SEL_SUBTRACT)
	t.ok(MapState.selection_empty() or int(MapState.terrain_selection[4 * 16 + 4]) == 0, "brush subtract")


func _wand(t) -> void:
	var field := _prep_field(8, 8, 200)
	# Island A at (0..2, 0..2) = raw 300 (30 m). Island B at (5..7, 5..7) = 300.
	# Rest stays 200 (20 m). Delta is 10 m.
	for z in range(0, 3):
		for x in range(0, 3):
			field.heights[z * 8 + x] = 300
	for z in range(5, 8):
		for x in range(5, 8):
			field.heights[z * 8 + x] = 300
	var island := MapState.flood_fill_height(field, 1, 1, 1.0)
	t.eq(island.size(), 64)
	var n := 0
	for i in island.size():
		if island[i] > 0:
			n += 1
	t.eq(n, 9, "tight tolerance stays on the plateau")
	t.eq(int(island[1 * 8 + 1]), 255)
	t.eq(int(island[0]), 255)
	t.eq(int(island[2 * 8 + 2]), 255)
	t.eq(int(island[3 * 8 + 1]), 0, "orthogonal neighbour at 20 m is outside 1 m")
	t.eq(int(island[6 * 8 + 6]), 0, "disconnected island is not contiguous")

	var wide := MapState.flood_fill_height(field, 1, 1, 15.0)
	var wn := 0
	for i in wide.size():
		if wide[i] > 0:
			wn += 1
	t.eq(wn, 64, "wide tolerance floods the whole field")

	MapState.clear_selection()
	MapState.wand_terrain_selection(1, 1, 1.0, MapState.SEL_REPLACE)
	t.eq(MapState.selection_cell_count(), 9)
	MapState.wand_terrain_selection(6, 6, 1.0, MapState.SEL_ADD)
	t.eq(MapState.selection_cell_count(), 18, "add unions the other island")
	MapState.wand_terrain_selection(1, 1, 1.0, MapState.SEL_SUBTRACT)
	t.eq(MapState.selection_cell_count(), 9, "subtract drops the first island")


func _constrained_stamp(t) -> void:
	var field := _prep_field(16, 16, 200)
	MapState.rect_terrain_selection(0, 0, 7, 15, MapState.SEL_REPLACE)
	# Half-weight strip on the right of the selected half.
	for z in 16:
		MapState.terrain_selection[z * 16 + 7] = 128
	MapState._recount_and_commit()
	var sculpt := SculptTool.new()
	sculpt.mode = "raise"
	sculpt.radius_m = 80.0
	sculpt.strength = 1.0
	sculpt.falloff = 0.0
	sculpt.shape = "circle"
	# Cell (4,8) and (7,8) share the same chebyshev/euclidean offset from (8,8)
	# only if we stamp at a point equally far... stamp at (20, 40) = cell (4, 8)
	# so (4,8) is the centre (w=1, sel=1 → +80) and (11,8) is outside the mask.
	sculpt.begin_stroke(field, 20.0, 40.0, false)
	sculpt.end_stroke(field)
	var full := field.heights[8 * 16 + 4]
	t.eq(full, 280, "full-selected centre raises by 80")
	t.eq(field.heights[8 * 16 + 11], 200, "unselected cell is untouched")
	# Equal weight, half mask: cell (7,8) is 15 m east of (4,8); radius 80 so w=1.
	var half := field.heights[8 * 16 + 7]
	t.eq(half, 200 + int(round(80.0 * 128.0 / 255.0)), "half-selected scales the delta")

	# Paint is also gated.
	MapState.mat_grid_x = 8
	MapState.mat_grid_z = 8
	MapState.materials = PackedInt32Array()
	MapState.materials.resize(64)
	MapState.materials.fill(0)
	sculpt.mode = "paint"
	sculpt.paint_material = 5
	sculpt.begin_stroke(field, 20.0, 40.0, true)
	sculpt.end_paint()
	t.eq(MapState.material_at(22.0, 42.0), 5, "selected tile paints")
	# World (60, 40) is cell x=12 — unselected.
	t.eq(MapState.material_at(62.0, 42.0), 0, "unselected tile stays 0")

	MapState.clear_selection()
	var before := field.heights.duplicate()
	sculpt.mode = "raise"
	sculpt.begin_stroke(field, 20.0, 40.0, false)
	sculpt.end_stroke(field)
	t.ok(field.heights[8 * 16 + 11] != before[8 * 16 + 11], "empty mask edits everything")


func _select_by_material(t) -> void:
	_prep_field(16, 16, 200)
	MapState.mat_grid_x = 4
	MapState.mat_grid_z = 4
	MapState.materials = PackedInt32Array()
	MapState.materials.resize(16)
	MapState.materials.fill(0)
	MapState.set_material(1, 1, 7)
	MapState.set_material(2, 0, 7)
	MapState.clear_selection()
	MapState.select_terrain_by_material(7, MapState.SEL_REPLACE)
	# Each material tile is 20 m = 4 height cells.
	t.eq(MapState.selection_cell_count(), 32, "two tiles × 16 cells")
	t.eq(int(MapState.terrain_selection[5 * 16 + 5]), 255, "tile (1,1) covers height (4..7,4..7)")
	t.eq(int(MapState.terrain_selection[1 * 16 + 9]), 255, "tile (2,0) covers height (8..11,0..3)")
	t.eq(int(MapState.terrain_selection[0]), 0, "other tiles stay unselected")

	var logs: Array = []
	ToolState.set_paint_material(7)
	EditActions.select_terrain_by_material(func(m): logs.append(str(m)))
	t.eq(MapState.selection_cell_count(), 32)
	t.ok(not logs.is_empty() and "material 7" in logs[0])


func _clone_stamp(t) -> void:
	var field := _prep_field(16, 16, 200)
	# Raise a source peak at (4,4).
	field.heights[4 * 16 + 4] = 400
	field.heights[4 * 16 + 5] = 300
	ToolState.set_clone_source(22.5, 22.5)  # cell (4,4)
	var saved_mats := ToolState.clone_materials
	ToolState.set_clone_materials(false)
	var sculpt := SculptTool.new()
	sculpt.mode = "clone"
	sculpt.radius_m = 12.0
	sculpt.strength = 1.0
	sculpt.falloff = 0.0
	sculpt.shape = "circle"
	# Stamp at (12,4) = 62.5, 22.5
	sculpt.begin_stroke(field, 62.5, 22.5, false)
	var cmd = sculpt.end_stroke(field)
	t.ok(cmd != null, "clone stroke yields a command")
	# Dest centre should pick up the source-relative delta (400-400=0 at origin).
	# Neighbour dest (13,4) copies source (5,4) = 300 vs dest base 200 → 300.
	t.eq(field.heights[4 * 16 + 12], 200, "clone origin keeps dest base (delta 0)")
	t.eq(field.heights[4 * 16 + 13], 100, "clone copies source-relative delta (300-400)")
	UndoStack.clear()
	UndoStack.push(cmd, true)
	UndoStack.undo()
	t.eq(field.heights[4 * 16 + 13], 200, "clone undo restores dest")
	UndoStack.redo()
	t.eq(field.heights[4 * 16 + 13], 100, "clone redo")
	UndoStack.clear()
	ToolState.set_clone_materials(saved_mats)
	ToolState.clear_clone_source()


func _prep_field(gx: int, gz: int, raw: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	field.heights.fill(raw)
	MapState.field = field
	MapState.has_session = true
	MapState.width_m = gx * int(HeightField.CELL_M)
	MapState.depth_m = gz * int(HeightField.CELL_M)
	MapState.clear_selection()
	return field


func _snap() -> Dictionary:
	return {
		"field": MapState.field,
		"session": MapState.has_session,
		"w": MapState.width_m,
		"d": MapState.depth_m,
		"sel": MapState.terrain_selection.duplicate(),
		"count": MapState._selection_count,
		"mats": MapState.materials.duplicate(),
		"mgx": MapState.mat_grid_x,
		"mgz": MapState.mat_grid_z,
		"clone": ToolState.clone_source_m,
		"clone_mats": ToolState.clone_materials,
		"paint": ToolState.paint_material,
	}


func _restore(snap: Dictionary) -> void:
	UndoStack.clear()
	MapState.field = snap["field"]
	MapState.has_session = snap["session"]
	MapState.width_m = snap["w"]
	MapState.depth_m = snap["d"]
	MapState.terrain_selection = snap["sel"]
	MapState._selection_count = snap["count"]
	MapState.materials = snap["mats"]
	MapState.mat_grid_x = snap["mgx"]
	MapState.mat_grid_z = snap["mgz"]
	ToolState.clone_source_m = snap["clone"]
	ToolState.clone_materials = snap["clone_mats"]
	ToolState.set_paint_material(snap["paint"])
	if MapState.selection_empty():
		MapState.selection_texture = null
		MapState.selection_image = null
