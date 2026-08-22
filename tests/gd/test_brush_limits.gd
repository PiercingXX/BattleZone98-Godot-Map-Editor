extends RefCounted
## Slope and height bands: the maths, and the gate on every kind of write.


func run(t) -> void:
	var snap := _snap()
	_band(t)
	_slope_maths(t)
	_gates_height(t)
	_gates_material(t)
	_gates_mask(t)
	_restore(snap)


func _band(t) -> void:
	t.eq(BrushLimits.band(30.0, 20.0, 40.0, 5.0), 1.0, "inside the band is full weight")
	t.eq(BrushLimits.band(20.0, 20.0, 40.0, 5.0), 1.0, "the low edge is inside")
	t.eq(BrushLimits.band(40.0, 20.0, 40.0, 5.0), 1.0, "the high edge is inside")
	t.eq(BrushLimits.band(10.0, 20.0, 40.0, 5.0), 0.0, "past the low feather is zero")
	t.eq(BrushLimits.band(50.0, 20.0, 40.0, 5.0), 0.0, "past the high feather is zero")
	var lo: float = BrushLimits.band(17.5, 20.0, 40.0, 5.0)
	t.ok(lo > 0.0 and lo < 1.0, "the low feather ramps")
	var hi: float = BrushLimits.band(42.5, 20.0, 40.0, 5.0)
	t.ok(hi > 0.0 and hi < 1.0, "the high feather ramps")
	t.near(lo, hi, 0.0001, "the feathers are symmetric")
	t.eq(BrushLimits.band(19.9, 20.0, 40.0, 0.0), 0.0, "no feather is a hard edge")
	t.eq(BrushLimits.band(30.0, 40.0, 20.0, 5.0), 0.0, "an inverted band selects nothing")


func _slope_maths(t) -> void:
	t.near(BrushLimits.slope_deg(_flat(16, 16, 200), 40.0, 40.0), 0.0, 0.001, "flat is 0 degrees")
	# raw per cell for 45 degrees: one cell of run is CELL_M metres, so the
	# rise has to be CELL_M metres too.
	var per_cell := HeightField.CELL_M / HeightField.HEIGHT_SCALE
	var ramp := _ramp_x(16, 16, 200, int(round(per_cell)))
	t.near(BrushLimits.slope_deg(ramp, 40.0, 40.0), 45.0, 0.5, "one cell rise per cell run is 45")
	var half := _ramp_x(16, 16, 200, int(round(per_cell * 0.5)))
	t.near(BrushLimits.slope_deg(half, 40.0, 40.0), 26.565, 0.5, "half that is 26.6")
	t.eq(BrushLimits.slope_deg(null, 0.0, 0.0), 0.0, "no field reads flat")

	# The cell-grid form is the one that gates real writes; it has to agree
	# with the bilinear form wherever the ground is a plane.
	t.near(BrushLimits.slope_deg_cell(_flat(16, 16, 200), 8, 8), 0.0, 0.001, "flat cell is 0")
	t.near(BrushLimits.slope_deg_cell(ramp, 8, 8), 45.0, 0.001, "cell form reads 45 too")
	t.near(BrushLimits.slope_deg_cell(half, 8, 8), 26.565, 0.001, "and 26.6 too")
	t.near(
		BrushLimits.slope_deg_cell(ramp, 8, 8),
		BrushLimits.slope_deg(ramp, 42.5, 42.5),
		0.5,
		"the two forms agree on a plane",
	)
	# The +1 probe is clamped at the far edge, so the last column reads flat
	# rather than walking off the grid.
	t.near(BrushLimits.slope_deg_cell(ramp, 15, 15), 0.0, 0.001, "the far corner clamps")
	t.eq(BrushLimits.slope_deg_cell(null, 0, 0), 0.0, "no field reads flat here too")


func _gates_height(t) -> void:
	var field := _prep(16, 16, 200)
	var sculpt := _tool("raise")
	sculpt.limit_slope = true
	sculpt.slope_min_deg = 30.0
	sculpt.slope_max_deg = 90.0
	sculpt.slope_feather_deg = 0.0
	var before := field.heights.duplicate()
	sculpt.begin_stroke(field, 40.0, 40.0, false)
	var cmd = sculpt.end_stroke(field)
	t.eq(field.heights, before, "a flat field is outside a 30-90 slope band")
	t.eq(cmd, null, "a fully gated stroke records no undo step")

	# The same brush with the band opened writes.
	field = _prep(16, 16, 200)
	sculpt.slope_min_deg = 0.0
	sculpt.begin_stroke(field, 40.0, 40.0, false)
	sculpt.end_stroke(field)
	t.ok(field.heights[8 * 16 + 8] > 200, "the open band writes")

	# Height band: raw 200 is 20 m, so a 0-10 m band excludes the whole field.
	field = _prep(16, 16, 200)
	sculpt.limit_slope = false
	sculpt.limit_height = true
	sculpt.height_min_m = 0.0
	sculpt.height_max_m = 10.0
	sculpt.height_feather_m = 0.0
	before = field.heights.duplicate()
	sculpt.begin_stroke(field, 40.0, 40.0, false)
	sculpt.end_stroke(field)
	t.eq(field.heights, before, "a 0-10 m band excludes 20 m ground")

	field = _prep(16, 16, 200)
	sculpt.height_max_m = 30.0
	sculpt.begin_stroke(field, 40.0, 40.0, false)
	sculpt.end_stroke(field)
	t.ok(field.heights[8 * 16 + 8] > 200, "a 0-30 m band includes 20 m ground")

	# Untouched cells keep their inherited word, however far out of range (C2).
	field = _prep(16, 16, 200)
	field.heights[0] = 7630
	sculpt.height_max_m = 10.0
	sculpt.begin_stroke(field, 40.0, 40.0, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[0], 7630, "a gated cell is not clamped, only skipped")


func _gates_material(t) -> void:
	var field := _prep(16, 16, 200)
	MapState.mat_grid_x = 8
	MapState.mat_grid_z = 8
	MapState.materials = PackedInt32Array()
	MapState.materials.resize(64)
	MapState.materials.fill(0)
	var sculpt := _tool("paint")
	sculpt.paint_material = 5
	sculpt.limit_height = true
	sculpt.height_min_m = 100.0
	sculpt.height_max_m = 200.0
	sculpt.height_feather_m = 0.0
	sculpt.begin_stroke(field, 40.0, 40.0, true)
	t.eq(sculpt.end_paint(), null, "a gated paint stroke records nothing")
	t.eq(MapState.material_at(42.0, 42.0), 0, "ground below the band stays unpainted")

	sculpt.height_min_m = 0.0
	sculpt.begin_stroke(field, 40.0, 40.0, true)
	sculpt.end_paint()
	t.eq(MapState.material_at(42.0, 42.0), 5, "ground inside the band paints")


func _gates_mask(t) -> void:
	var field := _prep(16, 16, 200)
	var stem := "water_limit_probe"
	var mask := MapState.ensure_mask(stem)
	if mask.size() != 16 * 16:
		return
	var sculpt := _tool("raise")
	sculpt.limit_slope = true
	sculpt.slope_min_deg = 45.0
	sculpt.slope_max_deg = 90.0
	sculpt.slope_feather_deg = 0.0
	sculpt.begin_mask_stroke(field, 40.0, 40.0, stem, 255)
	t.eq(sculpt.end_mask_paint(), null, "a gated mask stroke records nothing")
	t.eq(int(MapState.get_mask(stem)[8 * 16 + 8]), 0, "flat ground fails a 45-90 band")

	sculpt.slope_min_deg = 0.0
	sculpt.begin_mask_stroke(field, 40.0, 40.0, stem, 255)
	sculpt.end_mask_paint()
	t.eq(int(MapState.get_mask(stem)[8 * 16 + 8]), 255, "the open band paints the mask")
	MapState.masks.erase(stem)


func _tool(mode: String) -> SculptTool:
	var sculpt := SculptTool.new()
	sculpt.follow_tool_state = false
	sculpt.mode = mode
	sculpt.radius_m = 30.0
	sculpt.strength = 1.0
	sculpt.falloff = 0.0
	sculpt.shape = "circle"
	return sculpt


func _flat(gx: int, gz: int, raw: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	field.heights.fill(raw)
	return field


func _ramp_x(gx: int, gz: int, base: int, per_cell: int) -> HeightField:
	var field := _flat(gx, gz, base)
	for z in gz:
		for x in gx:
			field.heights[z * gx + x] = base + per_cell * x
	return field


func _prep(gx: int, gz: int, raw: int) -> HeightField:
	var field := _flat(gx, gz, raw)
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
		"mats": MapState.materials.duplicate(),
		"mgx": MapState.mat_grid_x,
		"mgz": MapState.mat_grid_z,
	}


func _restore(s: Dictionary) -> void:
	MapState.field = s["field"]
	MapState.has_session = s["session"]
	MapState.width_m = s["w"]
	MapState.depth_m = s["d"]
	MapState.materials = s["mats"]
	MapState.mat_grid_x = s["mgx"]
	MapState.mat_grid_z = s["mgz"]
	MapState.clear_selection()
