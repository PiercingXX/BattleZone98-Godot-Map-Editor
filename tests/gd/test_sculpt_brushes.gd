extends RefCounted
## Noise, morphological erode/dilate, set-height and set-angle, plus the
## tool-name routing and the persisted brush.


func run(t) -> void:
	var snap := _snap()
	_routing(t)
	_in_range(t)
	_noise(t)
	_morphology(t)
	_set_height(t)
	_set_angle(t)
	_undo_path(t)
	_restore(snap)
	_persistence(t)


func _routing(t) -> void:
	for name in ToolState.HEIGHT_BRUSHES:
		t.ok(ToolState.is_height_brush(name), "%s is a height brush" % name)
		t.ok(ToolState.is_stroke_tool(name), "%s opens a stroke" % name)
		t.ok(ToolState.is_brush_tool(name), "%s shows the ring" % name)
	for name in ["raise", "lower", "flatten", "smooth", "noise"]:
		t.ok(ToolState.is_height_brush(name), "%s still routes" % name)
	for name in ["erode", "dilate", "setheight", "setangle"]:
		t.ok(ToolState.is_height_brush(name), "%s is new and routes" % name)
	t.ok(not ToolState.is_height_brush("paint"), "paint is not a height brush")
	t.ok(ToolState.is_stroke_tool("paint"), "paint still opens a stroke")
	t.ok(ToolState.is_stroke_tool("clone"), "clone still opens a stroke")
	t.ok(not ToolState.is_stroke_tool("fly"), "fly opens nothing")
	t.ok(not ToolState.is_stroke_tool("select"), "select opens nothing")
	t.ok(ToolState.is_brush_tool("ramp"), "ramp shows the ring")
	t.ok(ToolState.is_brush_tool("qsel"), "qsel shows the ring")

	t.ok(ToolState.stroke_spacing_m() >= HeightField.CELL_M, "march is at least one cell")


func _in_range(t) -> void:
	for mode in ToolState.HEIGHT_BRUSHES:
		for base in [8, 200, 4080]:
			var field := _prep(16, 16, base)
			var sculpt := _tool(mode)
			sculpt.set_height_m = 500.0
			sculpt.angle_deg = 80.0
			sculpt.begin_stroke(field, 40.0, 40.0, false)
			sculpt.end_stroke(field)
			var bad := 0
			for h in field.heights:
				if h < SculptTool.RAW_MIN or h > SculptTool.RAW_MAX:
					bad += 1
			t.eq(bad, 0, "%s from %d stays in raw 1..4095" % [mode, base])


func _noise(t) -> void:
	var a := _noise_run(7, 0.02, 3, 6.0)
	var b := _noise_run(7, 0.02, 3, 6.0)
	t.eq(a, b, "the same seed replays the same bytes")
	t.ne(a, _noise_run(8, 0.02, 3, 6.0), "a different seed is a different field")
	t.ne(a, _noise_run(7, 0.2, 3, 6.0), "frequency changes the field")
	t.ne(a, _noise_run(7, 0.02, 1, 6.0), "octaves change the field")

	var flat := _noise_run(7, 0.02, 3, 0.0)
	var unchanged := true
	for h in flat:
		if h != 200:
			unchanged = false
			break
	t.ok(unchanged, "zero amplitude writes nothing")

	# Amplitude is metres, so it has to bound the excursion in raw units.
	var small := _noise_run(7, 0.05, 3, 2.0)
	var peak := 0
	for h in small:
		peak = maxi(peak, absi(h - 200))
	t.ok(peak > 0, "a 2 m amplitude does move the ground")
	t.ok(peak <= int(round(2.0 / HeightField.HEIGHT_SCALE)) + 1, "and stays inside 2 m")


func _noise_run(seed_v: int, freq: float, octaves: int, amp: float) -> PackedInt32Array:
	var field := _prep(24, 24, 200)
	var sculpt := _tool("noise")
	sculpt.brush_seed = seed_v
	sculpt.noise_frequency = freq
	sculpt.noise_octaves = octaves
	sculpt.noise_amplitude_m = amp
	sculpt.radius_m = 60.0
	sculpt.begin_stroke(field, 60.0, 60.0, false)
	sculpt.end_stroke(field)
	return field.heights.duplicate()


func _morphology(t) -> void:
	# A one-cell pillar. Erosion is a min over the disc, so the pillar loses.
	var field := _prep(16, 16, 200)
	field.heights[8 * 16 + 8] = 400
	var sculpt := _tool("erode")
	sculpt.erode_radius_m = HeightField.CELL_M
	sculpt.erode_slack_m = 0.0
	sculpt.begin_stroke(field, 42.5, 42.5, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[8 * 16 + 8], 200, "erosion levels a lone pillar")

	# Dilation is the same with max: the pillar spreads into its neighbours.
	field = _prep(16, 16, 200)
	field.heights[8 * 16 + 8] = 400
	sculpt = _tool("dilate")
	sculpt.erode_radius_m = HeightField.CELL_M
	sculpt.erode_slack_m = 0.0
	sculpt.begin_stroke(field, 42.5, 42.5, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[8 * 16 + 8], 400, "dilation keeps the pillar")
	t.eq(field.heights[8 * 16 + 9], 400, "dilation spreads it east")
	t.eq(field.heights[9 * 16 + 8], 400, "dilation spreads it north")

	# Slack is what turns the square element into a disc: a diagonal neighbour
	# sits 1.41 cells out, so it pays for the 0.41 it is over the radius.
	field = _prep(16, 16, 200)
	field.heights[7 * 16 + 7] = 100
	sculpt = _tool("erode")
	sculpt.erode_radius_m = HeightField.CELL_M
	sculpt.erode_slack_m = 0.0
	sculpt.begin_stroke(field, 42.5, 42.5, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[8 * 16 + 8], 100, "no slack reaches the corner")

	field = _prep(16, 16, 200)
	field.heights[7 * 16 + 7] = 100
	sculpt = _tool("erode")
	sculpt.erode_radius_m = HeightField.CELL_M
	sculpt.erode_slack_m = 30.0
	sculpt.begin_stroke(field, 42.5, 42.5, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[8 * 16 + 8], 200, "slack prices the corner out")

	# Every dab of a stroke erodes the terrain the stroke started on, not the
	# terrain the previous dab left. Otherwise holding the mouse still would
	# quietly grow the structuring element one ring per frame.
	field = _prep(16, 16, 200)
	for pz in range(6, 11):
		for px in range(6, 11):
			field.heights[pz * 16 + px] = 400
	sculpt = _tool("erode")
	sculpt.erode_radius_m = HeightField.CELL_M
	sculpt.erode_slack_m = 0.0
	sculpt.begin_stroke(field, 42.5, 42.5, false)
	sculpt.stamp(field, 42.5, 42.5)
	sculpt.stamp(field, 42.5, 42.5)
	sculpt.end_stroke(field)
	t.eq(field.heights[7 * 16 + 7], 400, "a 5x5 plateau loses exactly one ring")
	t.eq(field.heights[9 * 16 + 9], 400, "on both corners")
	t.eq(field.heights[6 * 16 + 6], 200, "the outer ring is gone")

	# The kernel reads the pre-stroke grid. Reading the live one instead would
	# let the raster order carry the pillar east one cell per column, so a
	# single dab would smear it across the whole stamp rect.
	field = _prep(16, 16, 200)
	field.heights[8 * 16 + 8] = 400
	sculpt = _tool("dilate")
	sculpt.erode_radius_m = HeightField.CELL_M
	sculpt.erode_slack_m = 0.0
	sculpt.begin_stroke(field, 42.5, 42.5, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[8 * 16 + 9], 400, "dilation reaches one cell east")
	t.eq(field.heights[8 * 16 + 10], 200, "and stops there instead of cascading")
	t.eq(field.heights[8 * 16 + 11], 200, "no runaway two cells out")


func _set_height(t) -> void:
	var field := _prep(16, 16, 200)
	var sculpt := _tool("setheight")
	sculpt.set_height_m = 30.0
	sculpt.begin_stroke(field, 42.5, 42.5, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[8 * 16 + 8], 300, "set-height paints an absolute 30 m")

	# It is not flatten: flatten targets the ground under the cursor.
	field = _prep(16, 16, 200)
	var flat := _tool("flatten")
	flat.begin_stroke(field, 42.5, 42.5, false)
	flat.end_stroke(field)
	t.eq(field.heights[8 * 16 + 8], 200, "flatten holds the height it started on")

	# Half strength lands halfway, so the slider still means something.
	field = _prep(16, 16, 200)
	sculpt = _tool("setheight")
	sculpt.set_height_m = 30.0
	sculpt.strength = 0.5
	sculpt.begin_stroke(field, 42.5, 42.5, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[8 * 16 + 8], 250, "half strength lands halfway to the target")


func _set_angle(t) -> void:
	# 45 degrees climbing east from the stroke start: 2.5 m east of the origin
	# is 2.5 m up.
	var field := _prep(24, 24, 200)
	var sculpt := _tool("setangle")
	sculpt.radius_m = 60.0
	sculpt.angle_deg = 45.0
	sculpt.angle_dir_deg = 90.0
	sculpt.begin_stroke(field, 40.0, 40.0, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[8 * 24 + 8], 225, "45 degrees east rises 2.5 m over 2.5 m")
	t.eq(field.heights[8 * 24 + 9], 275, "and another 5 m over the next cell")
	t.eq(field.heights[8 * 24 + 7], 175, "and drops the same going back west")

	# The bearing is a compass bearing: 0 climbs north (+z), so an east-west
	# row is level.
	field = _prep(24, 24, 200)
	sculpt = _tool("setangle")
	sculpt.radius_m = 60.0
	sculpt.angle_deg = 45.0
	sculpt.angle_dir_deg = 0.0
	sculpt.begin_stroke(field, 40.0, 40.0, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[8 * 24 + 9], field.heights[8 * 24 + 7], "bearing 0 levels the x row")
	t.eq(field.heights[9 * 24 + 8], 275, "bearing 0 climbs toward +z")

	# An explicit origin overrides the stroke start.
	field = _prep(24, 24, 200)
	sculpt = _tool("setangle")
	sculpt.radius_m = 60.0
	sculpt.angle_deg = 45.0
	sculpt.angle_dir_deg = 90.0
	sculpt.angle_origin_m = Vector2(60.0, 40.0)
	sculpt.begin_stroke(field, 40.0, 40.0, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[8 * 24 + 12], 225, "the plane pivots on the chosen origin")


func _undo_path(t) -> void:
	for mode in ["erode", "dilate", "setheight", "setangle"]:
		var field := _prep(16, 16, 200)
		field.heights[8 * 16 + 8] = 400
		var before := field.heights.duplicate()
		var sculpt := _tool(mode)
		sculpt.set_height_m = 35.0
		sculpt.begin_stroke(field, 42.5, 42.5, false)
		var cmd = sculpt.end_stroke(field)
		t.ok(cmd != null, "%s produced an undo command" % mode)
		if cmd == null:
			continue
		t.eq(cmd.tool, mode, "%s names itself in the history" % mode)
		t.ok(not cmd.regions.is_empty(), "%s captured chunk regions" % mode)
		var after := field.heights.duplicate()
		cmd.undo()
		t.eq(field.heights, before, "%s undo restores the grid exactly" % mode)
		cmd.do()
		t.eq(field.heights, after, "%s redo repaints it" % mode)


func _persistence(t) -> void:
	var keep := {
		"radius": Settings.brush_radius_m,
		"strength": Settings.brush_strength,
		"falloff": Settings.brush_falloff,
		"shape": Settings.brush_shape,
		"symmetry": Settings.brush_symmetry,
		"mask": Settings.brush_mask,
		"spacing": Settings.brush_spacing,
		"rot": Settings.brush_rotation_deg,
		"rand": Settings.brush_random_rotation,
		"psize": Settings.brush_pressure_size,
		"limit_slope": Settings.limit_slope,
		"slope_min": Settings.slope_min_deg,
		"noise_freq": Settings.noise_frequency,
		"seed": Settings.brush_seed,
		"erode_r": Settings.erode_radius_m,
		"set_h": Settings.set_height_m,
		"angle": Settings.angle_deg,
	}
	var live := {
		"radius": ToolState.radius_m,
		"strength": ToolState.strength,
		"falloff": ToolState.falloff,
		"shape": ToolState.shape,
		"symmetry": ToolState.symmetry,
		"mask": ToolState.brush_mask,
	}

	ToolState.set_radius(123.0)
	ToolState.set_strength(0.8)
	ToolState.set_falloff(0.2)
	ToolState.set_shape("square")
	ToolState.set_symmetry(ToolState.SYMMETRY_MIRROR_X)
	ToolState.set_brush_mask("ring")
	ToolState.set_brush_spacing(0.4, 25)
	ToolState.set_brush_rotation(30.0)
	ToolState.set_brush_random_rotation(true)
	ToolState.set_brush_pressure(0.75, 0.5)
	ToolState.set_slope_limit(true, 20.0, 55.0)
	ToolState.set_height_limit(true, 5.0, 60.0)
	ToolState.set_noise_params(0.07, 5, 12.0, 4242)
	ToolState.set_erode_params(15.0, 1.5)
	ToolState.set_target_height(77.5)
	ToolState.set_target_angle(22.0, 270.0)
	ToolState.save_brush_settings()

	# Wipe the live copies, reload from disk, and check the brush came back.
	ToolState.radius_m = 1.0
	ToolState.brush_mask = ""
	ToolState.brush_seed = 0
	Settings._load()
	ToolState.load_brush_settings()

	t.near(ToolState.radius_m, 123.0, 0.001, "radius survives a reload")
	t.near(ToolState.strength, 0.8, 0.001, "strength survives a reload")
	t.near(ToolState.falloff, 0.2, 0.001, "falloff survives a reload")
	t.eq(ToolState.shape, "square", "shape survives a reload")
	t.eq(ToolState.symmetry, ToolState.SYMMETRY_MIRROR_X, "symmetry survives a reload")
	t.eq(ToolState.brush_mask, "ring", "the tip survives a reload")
	t.near(ToolState.brush_spacing, 0.4, 0.001, "spacing survives a reload")
	t.eq(ToolState.brush_spacing_ms, 25, "the time gate survives a reload")
	t.near(ToolState.brush_rotation_deg, 30.0, 0.001, "rotation survives a reload")
	t.ok(ToolState.brush_random_rotation, "random rotation survives a reload")
	t.near(ToolState.brush_pressure_size, 0.75, 0.001, "pressure size survives a reload")
	t.near(ToolState.brush_pressure_opacity, 0.5, 0.001, "pressure opacity survives a reload")
	t.ok(ToolState.limit_slope, "the slope limit survives a reload")
	t.near(ToolState.slope_min_deg, 20.0, 0.001, "the slope floor survives a reload")
	t.near(ToolState.slope_max_deg, 55.0, 0.001, "the slope ceiling survives a reload")
	t.ok(ToolState.limit_height, "the height limit survives a reload")
	t.near(ToolState.height_min_m, 5.0, 0.001, "the height floor survives a reload")
	t.near(ToolState.noise_frequency, 0.07, 0.0001, "noise frequency survives a reload")
	t.eq(ToolState.noise_octaves, 5, "noise octaves survive a reload")
	t.near(ToolState.noise_amplitude_m, 12.0, 0.001, "noise amplitude survives a reload")
	t.eq(ToolState.brush_seed, 4242, "the brush seed survives a reload")
	t.near(ToolState.erode_radius_m, 15.0, 0.001, "erode radius survives a reload")
	t.near(ToolState.set_height_m, 77.5, 0.001, "the set-height target survives a reload")
	t.near(ToolState.angle_deg, 22.0, 0.001, "the set-angle slope survives a reload")
	t.near(ToolState.angle_dir_deg, 270.0, 0.001, "the set-angle bearing survives a reload")

	# A settings file with junk in the brush section must not arm a brush that
	# repaints the map.
	Settings.brush_radius_m = 1.0e9
	Settings.brush_strength = 12.0
	Settings.noise_frequency = 0.0
	Settings.brush_mask = "not-a-tip"
	Settings.brush_symmetry = "sideways"
	Settings.save()
	Settings._load()
	t.ok(Settings.brush_radius_m <= Settings.BRUSH_RADIUS_MAX, "a silly radius is clamped")
	t.ok(Settings.brush_strength <= 1.0, "a silly strength is clamped")
	t.ok(Settings.noise_frequency > 0.0, "a zero frequency is refused")
	t.eq(Settings.brush_mask, "", "an unknown tip falls back to the kernel")
	t.eq(Settings.brush_symmetry, "off", "an unknown symmetry falls back to off")

	# Put the user's brush back the way we found it.
	Settings.brush_radius_m = keep["radius"]
	Settings.brush_strength = keep["strength"]
	Settings.brush_falloff = keep["falloff"]
	Settings.brush_shape = keep["shape"]
	Settings.brush_symmetry = keep["symmetry"]
	Settings.brush_mask = keep["mask"]
	Settings.brush_spacing = keep["spacing"]
	Settings.brush_spacing_ms = 0
	Settings.brush_rotation_deg = keep["rot"]
	Settings.brush_random_rotation = keep["rand"]
	Settings.brush_pressure_size = keep["psize"]
	Settings.brush_pressure_opacity = 0.0
	Settings.limit_slope = keep["limit_slope"]
	Settings.slope_min_deg = keep["slope_min"]
	Settings.limit_height = false
	Settings.noise_frequency = keep["noise_freq"]
	Settings.noise_octaves = 3
	Settings.noise_amplitude_m = 6.0
	Settings.brush_seed = keep["seed"]
	Settings.erode_radius_m = keep["erode_r"]
	Settings.erode_slack_m = 3.0
	Settings.set_height_m = keep["set_h"]
	Settings.angle_deg = keep["angle"]
	Settings.angle_dir_deg = 0.0
	Settings.save()
	ToolState.load_brush_settings()
	ToolState.radius_m = live["radius"]
	ToolState.strength = live["strength"]
	ToolState.falloff = live["falloff"]
	ToolState.shape = live["shape"]
	ToolState.symmetry = live["symmetry"]
	ToolState.brush_mask = live["mask"]


func _tool(mode: String) -> SculptTool:
	var sculpt := SculptTool.new()
	sculpt.follow_tool_state = false
	sculpt.mode = mode
	sculpt.radius_m = 30.0
	sculpt.strength = 1.0
	sculpt.falloff = 0.0
	sculpt.shape = "circle"
	return sculpt


func _prep(gx: int, gz: int, raw: int) -> HeightField:
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
	}


func _restore(s: Dictionary) -> void:
	MapState.field = s["field"]
	MapState.has_session = s["session"]
	MapState.width_m = s["w"]
	MapState.depth_m = s["d"]
	MapState.clear_selection()
