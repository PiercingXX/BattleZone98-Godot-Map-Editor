extends RefCounted
## Raise/lower/flatten/smooth/noise stay in raw 1..4095; weight falloff.


func run(t) -> void:
	var sculpt := SculptTool.new()
	sculpt.radius_m = 40.0
	sculpt.falloff = 0.65
	sculpt.strength = 1.0
	sculpt.shape = "circle"

	t.eq(sculpt._weight(0.0, 0.0, 41.0, 0.0), 0.0, "zero outside radius")
	t.ok(sculpt._weight(0.0, 0.0, 0.0, 0.0) > 0.9, "near 1 at centre")
	var prev := 2.0
	for i in 21:
		var dist := float(i) * 2.0
		var w: float = sculpt._weight(0.0, 0.0, dist, 0.0)
		t.ok(w <= prev + 0.0001, "circle falloff monotonic at %s" % dist)
		prev = w
	sculpt.shape = "square"
	t.eq(sculpt._weight(0.0, 0.0, 41.0, 0.0), 0.0)
	# (30,30): chebyshev 30 <= r, euclidean 42.4 > r — distinguishes the shapes.
	t.ok(sculpt._weight(0.0, 0.0, 30.0, 30.0) > 0.0, "square reaches the corner (chebyshev)")
	sculpt.shape = "circle"
	t.eq(sculpt._weight(0.0, 0.0, 30.0, 30.0), 0.0, "circle excludes the corner")
	sculpt.shape = "square"
	t.ok(sculpt._weight(0.0, 0.0, 20.0, 0.0) > 0.0)

	var saved = MapState.field
	for mode in ["raise", "lower", "flatten", "smooth", "noise"]:
		var field := _flat(16, 16, 200)
		MapState.field = field
		sculpt.mode = mode
		sculpt.shape = "circle"
		sculpt.begin_stroke(field, 20.0, 20.0, false)
		sculpt.stamp(field, 25.0, 25.0)
		sculpt.end_stroke(field)
		for i in field.heights.size():
			var h: int = field.heights[i]
			t.ok(h >= SculptTool.RAW_MIN and h <= SculptTool.RAW_MAX, "%s in range (%s)" % [mode, h])
			if h < SculptTool.RAW_MIN or h > SculptTool.RAW_MAX:
				break

	var hi := _flat(16, 16, 4080)
	MapState.field = hi
	sculpt.mode = "raise"
	sculpt.strength = 1.0
	sculpt.begin_stroke(hi, 20.0, 20.0, false)
	sculpt.end_stroke(hi)
	for i in hi.heights.size():
		t.ok(hi.heights[i] <= 4095, "raise clamps to 4095")
		if hi.heights[i] > 4095:
			break

	var lo := _flat(16, 16, 8)
	MapState.field = lo
	sculpt.mode = "lower"
	sculpt.begin_stroke(lo, 20.0, 20.0, false)
	sculpt.end_stroke(lo)
	for i in lo.heights.size():
		t.ok(lo.heights[i] >= 1, "lower clamps to 1")
		if lo.heights[i] < 1:
			break

	# Removed "undefined" mode must not punch holes (old branch wrote 0).
	var leftover := _flat(8, 8, 200)
	MapState.field = leftover
	sculpt.mode = "undefined"
	t.eq(sculpt._apply_height(200, 1.0, 1, 1, leftover), 200, "dead undefined mode is a no-op")

	_falloff_hardness(t)
	_noise_scales(t)
	_clone_match_height(t)
	_overlay_api(t)

	MapState.field = saved


func _falloff_hardness(t) -> void:
	var hard: float = SculptTool.brush_weight(0.0, 0.0, 30.0, 0.0, 40.0, 1.0, "circle")
	var soft: float = SculptTool.brush_weight(0.0, 0.0, 30.0, 0.0, 40.0, 0.0, "circle")
	t.near(hard, 1.0, 0.001, "falloff 1 is a hard disc")
	t.ok(soft < hard - 0.05, "falloff 0 is softer at mid-radius")
	t.eq(SculptTool.brush_weight(0.0, 0.0, 41.0, 0.0, 40.0, 1.0, "circle"), 0.0)
	var prev := 2.0
	for i in 21:
		var dist := float(i) * 2.0
		var w: float = SculptTool.brush_weight(0.0, 0.0, dist, 0.0, 40.0, 0.0, "circle")
		t.ok(w <= prev + 0.0001, "soft falloff monotonic at %s" % dist)
		prev = w


func _noise_scales(t) -> void:
	var a := _noise_run(7, 10.0, 1.0, 3, 6.0)
	var b := _noise_run(7, 10.0, 1.0, 3, 6.0)
	t.eq(a, b, "the same noise scale replays the same bytes")
	t.ne(a, _noise_run(7, 4.0, 1.0, 3, 6.0), "scale changes the field")
	t.ne(a, _noise_run(7, 10.0, 4.0, 3, 6.0), "contrast changes the field")


func _noise_run(seed_v: int, scale: float, contrast: float, octaves: int, amp: float) -> PackedInt32Array:
	var field := _flat(24, 24, 200)
	MapState.field = field
	var sculpt := SculptTool.new()
	sculpt.follow_tool_state = false
	sculpt.mode = "noise"
	sculpt.radius_m = 60.0
	sculpt.strength = 1.0
	sculpt.falloff = 1.0
	sculpt.shape = "circle"
	sculpt.brush_seed = seed_v
	sculpt.noise_scale = scale
	sculpt.noise_contrast = contrast
	sculpt.noise_octaves = octaves
	sculpt.noise_amplitude_m = amp
	sculpt.begin_stroke(field, 60.0, 60.0, false)
	sculpt.end_stroke(field)
	return field.heights.duplicate()


func _clone_match_height(t) -> void:
	var saved_src := ToolState.clone_source_m
	var saved_mats := ToolState.clone_materials
	var saved_match := ToolState.clone_match_height
	ToolState.set_clone_source(22.5, 22.5)
	ToolState.set_clone_materials(false)

	var field := _flat(16, 16, 200)
	MapState.field = field
	field.heights[4 * 16 + 4] = 400
	field.heights[4 * 16 + 5] = 300
	var sculpt := SculptTool.new()
	sculpt.follow_tool_state = false
	sculpt.mode = "clone"
	sculpt.radius_m = 12.0
	sculpt.strength = 1.0
	sculpt.falloff = 1.0
	sculpt.shape = "circle"
	sculpt.clone_match_height = false
	sculpt.begin_stroke(field, 62.5, 22.5, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[4 * 16 + 12], 200, "relative clone keeps dest base")
	t.eq(field.heights[4 * 16 + 13], 100, "relative clone copies source delta")

	field = _flat(16, 16, 200)
	MapState.field = field
	field.heights[4 * 16 + 4] = 400
	field.heights[4 * 16 + 5] = 300
	sculpt = SculptTool.new()
	sculpt.follow_tool_state = false
	sculpt.mode = "clone"
	sculpt.radius_m = 12.0
	sculpt.strength = 1.0
	sculpt.falloff = 1.0
	sculpt.shape = "circle"
	sculpt.clone_match_height = true
	sculpt.begin_stroke(field, 62.5, 22.5, false)
	sculpt.end_stroke(field)
	t.eq(field.heights[4 * 16 + 12], 400, "match-height clone stamps absolute source")
	t.eq(field.heights[4 * 16 + 13], 300, "match-height clone copies sampled height")

	ToolState.set_clone_materials(saved_mats)
	ToolState.clone_match_height = saved_match
	if saved_src.is_finite():
		ToolState.set_clone_source(saved_src.x, saved_src.y)
	else:
		ToolState.clear_clone_source()


func _overlay_api(t) -> void:
	var sh := load("res://project/shaders/terrain.gdshader") as Shader
	t.ok(sh != null, "terrain shader loads")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("show_buildable", true)
	mat.set_shader_parameter("show_ai_traversable", true)
	mat.set_shader_parameter("show_brush_noise", true)
	mat.set_shader_parameter("brush_noise_scale", Vector2(10.0, 10.0))
	mat.set_shader_parameter("brush_noise_contrast", 2.0)
	mat.set_shader_parameter("brush_noise_seed", 7.0)
	t.near(float(mat.get_shader_parameter("brush_noise_contrast")), 2.0, 0.001)
	t.eq(mat.get_shader_parameter("show_buildable"), true)
	t.eq(mat.get_shader_parameter("show_brush_noise"), true)
	var tr := TerrainRenderer.new()
	t.eq(tr._show_buildable, false, "buildable overlay off by default")
	t.eq(tr._show_ai_traversable, false, "ai overlay off by default")
	tr.set_buildable_overlay(true)
	t.eq(tr._show_buildable, true, "set_buildable_overlay latches")
	tr.set_ai_traversable_overlay(true)
	t.eq(tr._show_ai_traversable, true, "set_ai_traversable_overlay latches")
	tr.set_buildable_overlay(false)
	tr.set_ai_traversable_overlay(false)
	t.eq(tr._show_buildable, false)
	t.eq(tr._show_ai_traversable, false)
	tr.free()


func _flat(gx: int, gz: int, raw: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	field.heights.fill(raw)
	return field
