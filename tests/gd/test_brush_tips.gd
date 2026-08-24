extends RefCounted
## Generated brush tips, the mask weight path, and the stroke dynamics gates.


func run(t) -> void:
	_tips(t)
	_library(t)
	_mask_weight(t)
	_rotation(t)
	_dynamics(t)
	_pressure(t)


func _tips(t) -> void:
	for id in BrushMask.IDS:
		var m := BrushMask.generate(id, 32, 7)
		t.eq(m.size, 32, "%s is square" % id)
		t.eq(m.data.size(), 32 * 32, "%s is dense" % id)
		var peak := 0
		for v in m.data:
			t.ok(v >= 0 and v <= 255, "%s stays in a byte" % id)
			peak = maxi(peak, v)
		t.ok(peak > 0, "%s covers something" % id)

	# Generation is a pure function of (id, size, seed): C6 wants the same
	# bytes from the same inputs, on every run and every machine.
	for id in BrushMask.IDS:
		t.eq(
			BrushMask.generate(id, 24, 3).data,
			BrushMask.generate(id, 24, 3).data,
			"%s regenerates byte-identical" % id,
		)

	var disc := BrushMask.generate("disc", 33)
	t.eq(disc.sample(0.5, 0.5), 1.0, "disc is solid at the centre")
	t.eq(disc.sample(0.02, 0.02), 0.0, "disc misses its own corner")
	var square := BrushMask.generate("square", 33)
	t.ok(square.sample(0.02, 0.02) > 0.5, "square fills its corner")
	var ring := BrushMask.generate("ring", 65)
	t.ok(ring.sample(0.5, 0.5) < 0.1, "ring is hollow")
	t.ok(ring.sample(0.5, 0.25) > 0.8, "ring peaks on the rim")
	var soft := BrushMask.generate("soft", 65)
	t.ok(soft.sample(0.5, 0.5) > soft.sample(0.5, 0.3), "soft falls off outward")

	t.eq(disc.sample(-0.1, 0.5), 0.0, "outside u reads zero")
	t.eq(disc.sample(0.5, 1.4), 0.0, "outside v reads zero")


func _library(t) -> void:
	BrushMaskLibrary.clear_cache()
	var a := BrushMaskLibrary.get_mask("ring")
	var b := BrushMaskLibrary.get_mask("ring")
	t.ok(a == b, "library hands out one shared tip")
	t.eq(BrushMaskLibrary.get_mask(""), null, "empty id means the analytic shape")
	t.eq(BrushMaskLibrary.get_mask("nope"), null, "unknown id means the analytic shape")
	t.ok(BrushMaskLibrary.has("disc"), "disc is a known tip")
	t.ok(not BrushMaskLibrary.has("nope"), "nope is not")
	BrushMaskLibrary.clear_cache()
	var c := BrushMaskLibrary.get_mask("ring")
	t.eq(c.data, a.data, "a rebuilt tip matches the first one")
	BrushMaskLibrary.prewarm()


func _mask_weight(t) -> void:
	var sculpt := SculptTool.new()
	sculpt.follow_tool_state = false
	sculpt.radius_m = 40.0
	sculpt.falloff = 1.0
	sculpt.shape = "circle"
	var analytic: float = sculpt._weight(0.0, 0.0, 10.0, 0.0)

	sculpt.mask_id = "square"
	t.ok(sculpt._weight(0.0, 0.0, 30.0, 30.0) > 0.0, "square tip reaches the corner")
	t.eq(sculpt._weight(0.0, 0.0, 45.0, 0.0), 0.0, "square tip stops at the edge")

	sculpt.mask_id = "disc"
	t.eq(sculpt._weight(0.0, 0.0, 30.0, 30.0), 0.0, "disc tip excludes the corner")
	t.ok(sculpt._weight(0.0, 0.0, 0.0, 0.0) > 0.9, "disc tip is solid at the centre")

	sculpt.mask_id = "ring"
	t.ok(
		sculpt._weight(0.0, 0.0, 20.0, 0.0) > sculpt._weight(0.0, 0.0, 0.0, 0.0),
		"ring tip weighs the rim over the centre",
	)

	sculpt.mask_id = ""
	t.eq(sculpt._weight(0.0, 0.0, 10.0, 0.0), analytic, "clearing the tip restores the kernel")


func _rotation(t) -> void:
	var sculpt := SculptTool.new()
	sculpt.follow_tool_state = false
	sculpt.radius_m = 40.0
	sculpt.falloff = 1.0
	sculpt.mask_id = "chisel"
	# The chisel is a 2:1 ellipse: at rest it is wide in x, and a quarter turn
	# has to swap which axis reaches furthest.
	var flat_x: float = sculpt._weight(0.0, 0.0, 26.0, 0.0)
	var flat_z: float = sculpt._weight(0.0, 0.0, 0.0, 26.0)
	t.ok(flat_x > 0.0, "chisel is long across x")
	t.eq(flat_z, 0.0, "chisel is short across z")
	sculpt._dab_rot = deg_to_rad(90.0)
	t.eq(sculpt._weight(0.0, 0.0, 26.0, 0.0), 0.0, "turned chisel is short across x")
	t.ok(sculpt._weight(0.0, 0.0, 0.0, 26.0) > 0.0, "turned chisel is long across z")

	# Random rotation is drawn from the stroke RNG, so two identical strokes
	# see the same turns (C6).
	var field := _flat(48, 48, 200)
	var saved = MapState.field
	MapState.field = field
	var a := _random_rot_stroke()
	var b := _random_rot_stroke()
	t.eq(a, b, "random tip rotation replays identically")
	t.ok(a.size() > 1, "the stroke rolled more than one rotation")
	MapState.field = saved


func _random_rot_stroke() -> Array:
	var field := _flat(48, 48, 200)
	var sculpt := SculptTool.new()
	sculpt.follow_tool_state = false
	sculpt.mode = "raise"
	sculpt.radius_m = 20.0
	sculpt.mask_id = "chisel"
	sculpt.random_rotation = true
	sculpt.begin_stroke(field, 60.0, 60.0, false)
	var out: Array = [sculpt._dab_rot]
	for i in 4:
		sculpt.stamp(field, 60.0 + float(i + 1) * 10.0, 60.0)
		out.append(sculpt._dab_rot)
	sculpt.end_stroke(field)
	return out


func _dynamics(t) -> void:
	var saved = MapState.field
	var field := _flat(64, 64, 200)
	MapState.field = field
	var sculpt := SculptTool.new()
	sculpt.follow_tool_state = false
	sculpt.mode = "raise"
	sculpt.radius_m = 40.0
	sculpt.spacing_frac = 0.5
	sculpt.begin_stroke(field, 100.0, 100.0, false)
	t.eq(sculpt._dabs, 1, "the first dab always lands")
	sculpt.stamp(field, 105.0, 100.0)
	t.eq(sculpt._dabs, 1, "a dab inside the spacing gate is dropped")
	sculpt.stamp(field, 120.1, 100.0)
	t.eq(sculpt._dabs, 2, "a dab on the gate lands")
	sculpt.end_stroke(field)

	# The time gate is independent: a wide move still waits its interval out.
	var timed := SculptTool.new()
	timed.follow_tool_state = false
	timed.mode = "raise"
	timed.radius_m = 40.0
	timed.spacing_ms = 100000
	timed.begin_stroke(field, 100.0, 100.0, false)
	timed.stamp(field, 200.0, 200.0)
	t.eq(timed._dabs, 1, "a dab inside the time gate is dropped")
	timed.end_stroke(field)
	MapState.field = saved


func _pressure(t) -> void:
	var saved = MapState.field
	var field := _flat(64, 64, 200)
	MapState.field = field
	var sculpt := SculptTool.new()
	sculpt.follow_tool_state = false
	sculpt.mode = "raise"
	sculpt.radius_m = 40.0
	sculpt.strength = 1.0

	# Factors at zero: pressure is inert, which is what a mouse must see.
	sculpt.set_pressure(0.25)
	sculpt.begin_stroke(field, 100.0, 100.0, false)
	t.near(sculpt._dab_radius_m(), 40.0, 0.001, "size ignores pressure at factor 0")
	t.near(sculpt._dab_strength(), 1.0, 0.001, "opacity ignores pressure at factor 0")
	sculpt.end_stroke(field)

	sculpt.pressure_size = 1.0
	sculpt.pressure_opacity = 1.0
	sculpt.begin_stroke(field, 100.0, 100.0, false)
	t.near(sculpt._dab_radius_m(), 10.0, 0.001, "size follows pressure at factor 1")
	t.near(sculpt._dab_strength(), 0.25, 0.001, "opacity follows pressure at factor 1")
	sculpt.end_stroke(field)

	# A mouse reports 0.0, which means "no pen", not "no force".
	sculpt.set_pressure(0.0)
	t.near(sculpt.pressure, 1.0, 0.001, "a mouse reads as full pressure")
	MapState.field = saved


func _flat(gx: int, gz: int, raw: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	field.heights.fill(raw)
	return field
