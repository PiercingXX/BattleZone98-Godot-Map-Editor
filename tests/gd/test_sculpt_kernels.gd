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

	MapState.field = saved


func _flat(gx: int, gz: int, raw: int) -> HeightField:
	var field := HeightField.new()
	field.grid_x = gx
	field.grid_z = gz
	field.heights.resize(gx * gz)
	field.heights.fill(raw)
	return field
