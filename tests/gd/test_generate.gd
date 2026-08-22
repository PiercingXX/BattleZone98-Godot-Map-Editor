extends RefCounted
## Procedural generator core: parameter validation, remap curves, fBm, the
## byte-identical determinism guarantee (C6), the raw 1..4095 range (C1/C2)
## and the reduced-resolution preview.


func run(t) -> void:
	_test_params(t)
	_test_curves(t)
	_test_noise(t)
	_test_determinism_bytes(t)
	_test_seeds_differ(t)
	_test_range(t)
	_test_shapes(t)
	_test_metrics(t)
	_test_preview_exact(t)
	_test_preview_representative(t)


func _test_params(t) -> void:
	var p := GenParams.new()
	t.eq(p.validate(), "", "defaults validate")
	t.eq(p.curve.size(), RemapCurve.SAMPLES, "default curve is a linear LUT")
	p.octaves = 0
	t.ok(not p.validate().is_empty(), "0 octaves refused")
	p.octaves = 5
	p.gain = 1.5
	t.ok(not p.validate().is_empty(), "gain above 0.95 refused")
	p.gain = 0.5
	p.base_raw = 5000
	t.ok(not p.validate().is_empty(), "base above raw 4095 refused")
	p.base_raw = 1000
	p.erosion_weight = 0.9
	t.ok(not p.validate().is_empty(), "erosion weight above 0.5 refused")
	p.erosion_weight = 0.4
	t.eq(p.validate(), "", "back to valid")

	var round_trip := GenParams.new()
	round_trip.from_dict(p.to_dict())
	t.eq(round_trip.signature(), p.signature(), "to_dict/from_dict preserves everything")
	round_trip.seed += 1
	t.ne(round_trip.signature(), p.signature(), "signature tracks the seed")

	var copy: GenParams = p.copy()
	copy.relief_m += 1.0
	t.near(p.relief_m, 60.0, 0.0001, "copy() does not alias")


func _test_curves(t) -> void:
	var lin := RemapCurve.linear()
	t.near(RemapCurve.eval(lin, 0.0), 0.0, 0.0001, "linear at 0")
	t.near(RemapCurve.eval(lin, 1.0), 1.0, 0.0001, "linear at 1")
	t.near(RemapCurve.eval(lin, 0.25), 0.25, 0.0001, "linear midpoint")
	t.near(RemapCurve.eval(lin, -5.0), 0.0, 0.0001, "eval clamps below")
	t.near(RemapCurve.eval(lin, 5.0), 1.0, 0.0001, "eval clamps above")

	var pl := RemapCurve.plateau(0.4, 0.6)
	t.near(RemapCurve.eval(pl, 0.1), 0.0, 0.0001, "plateau floor is flat")
	t.near(RemapCurve.eval(pl, 0.3), 0.0, 0.0001, "plateau floor is flat at 0.3")
	t.near(RemapCurve.eval(pl, 0.9), 1.0, 0.0001, "plateau ceiling is flat")
	t.ok(
		RemapCurve.eval(pl, 0.55) > RemapCurve.eval(pl, 0.45),
		"plateau ramps upward through the band",
	)

	var terr := RemapCurve.terrace(4, 0.9)
	var mono := true
	for i in 64:
		var a := RemapCurve.eval(terr, float(i) / 64.0)
		var b := RemapCurve.eval(terr, float(i + 1) / 64.0)
		if b < a - 0.0001:
			mono = false
	t.ok(mono, "terrace is monotonic")
	# A sharp 4-step terrace must spend most of its range on flat benches.
	var flat := 0
	for i in 200:
		var x := float(i) / 200.0
		var d: float = absf(RemapCurve.eval(terr, x + 0.004) - RemapCurve.eval(terr, x))
		if d < 0.002:
			flat += 1
	t.ok(flat > 100, "terrace benches are flat over most of the range (got %d/200)" % flat)

	var pts := RemapCurve.from_points(
		PackedFloat64Array([0.0, 0.5, 1.0]), PackedFloat64Array([0.0, 0.9, 1.0])
	)
	t.near(RemapCurve.eval(pts, 0.0), 0.0, 0.001, "from_points hits the first key")
	t.near(RemapCurve.eval(pts, 0.5), 0.9, 0.01, "from_points hits the middle key")
	t.near(RemapCurve.eval(pts, 1.0), 1.0, 0.001, "from_points hits the last key")
	t.near(RemapCurve.eval(pts, 0.25), 0.45, 0.02, "from_points interpolates linearly")

	var one := RemapCurve.from_points(PackedFloat64Array([0.5]), PackedFloat64Array([0.5]))
	t.eq(one.size(), RemapCurve.SAMPLES, "too few points falls back to linear")


func _test_noise(t) -> void:
	var p := GenParams.new()
	p.seed = 4242
	p.scale_m = 200.0
	p.octaves = 4
	var a := FbmNoise.new()
	a.configure(p)
	var b := FbmNoise.new()
	b.configure(p)
	var fa := a.fill(48, 32, 5.0, 0.0, 0.0)
	var fb := b.fill(48, 32, 5.0, 0.0, 0.0)
	t.eq(fa, fb, "two identically configured FbmNoise agree exactly")
	t.eq(fa.size(), 48 * 32, "row-major fill covers the grid")
	var in_range := true
	var spread := 0.0
	var lo := 2.0
	var hi := -1.0
	for v in fa:
		if v < 0.0 or v > 1.0:
			in_range = false
		lo = minf(lo, v)
		hi = maxf(hi, v)
	spread = hi - lo
	t.ok(in_range, "fBm output stays in 0..1")
	t.ok(spread > 0.2, "fBm actually varies (spread %.3f)" % spread)

	# fill() and sample() are the same function; generation uses fill().
	t.near(a.sample(7.0 * 5.0, 3.0 * 5.0), fa[3 * 48 + 7], 0.0000001, "sample matches fill")

	p.seed = 4243
	var c := FbmNoise.new()
	c.configure(p)
	t.ne(c.fill(48, 32, 5.0, 0.0, 0.0), fa, "a different seed gives a different field")

	# The octave seed ladder is pure integer maths, so it is the one part of
	# the noise stack that is bit-identical everywhere by construction.
	t.eq(FbmNoise.octave_seed(1, 0), FbmNoise.octave_seed(1, 0), "octave seed is a function")
	t.ne(FbmNoise.octave_seed(1, 0), FbmNoise.octave_seed(1, 1), "octaves get distinct seeds")
	t.ok(FbmNoise.octave_seed(-9, 3) >= 0, "octave seed stays inside int32")


func _test_determinism_bytes(t) -> void:
	# The headline guarantee: same seed, same parameters, same bytes. Not
	# "close enough" — the same buffer, compared as bytes.
	var p := GenPresets.make("mesa", 20250822)
	var first := TerrainGenerator.generate(p, 96, 128)
	var second := TerrainGenerator.generate(GenPresets.make("mesa", 20250822), 96, 128)
	t.ok(bool(first.get("ok", false)), "generate ok")
	t.ok(bool(second.get("ok", false)), "regenerate ok")
	var ba: PackedByteArray = (first["heights"] as PackedInt32Array).to_byte_array()
	var bb: PackedByteArray = (second["heights"] as PackedInt32Array).to_byte_array()
	t.eq(ba.size(), 96 * 128 * 4, "byte buffer covers the grid")
	t.eq(ba, bb, "two runs of the same parameters are byte-identical")

	# Same again through the serialised parameter form, which is how a preset
	# saved to disk comes back.
	var revived := GenParams.new()
	revived.from_dict(p.to_dict())
	var third := TerrainGenerator.generate(revived, 96, 128)
	t.eq((third["heights"] as PackedInt32Array).to_byte_array(), ba, "survives to_dict round trip")

	# Erosion is the sequential stage; prove it too.
	var eroded := GenPresets.make("highlands", 11)
	eroded.hydro_droplets = 400
	var e1 := TerrainGenerator.generate(eroded, 64, 64)
	var e2 := TerrainGenerator.generate(eroded, 64, 64)
	t.eq(
		(e1["heights"] as PackedInt32Array).to_byte_array(),
		(e2["heights"] as PackedInt32Array).to_byte_array(),
		"thermal plus droplet erosion is byte-identical across runs",
	)
	t.eq(int(e1["grid_x"]), 64, "full-resolution grid width")
	t.eq(int(e1["grid_z"]), 64, "full-resolution grid height")


func _test_seeds_differ(t) -> void:
	var a := TerrainGenerator.generate(GenPresets.make("highlands", 1), 64, 64)
	var b := TerrainGenerator.generate(GenPresets.make("highlands", 2), 64, 64)
	t.ne(a["heights"], b["heights"], "different seeds give different terrain")
	var same := 0
	var ha: PackedInt32Array = a["heights"]
	var hb: PackedInt32Array = b["heights"]
	for i in ha.size():
		if ha[i] == hb[i]:
			same += 1
	t.ok(same < ha.size() / 2, "seeds differ over most of the map (%d/%d equal)" % [same, ha.size()])


func _test_range(t) -> void:
	# Deliberately over-driven, once through the ceiling and once through the
	# floor. Generation writes every cell, so unlike a brush there is no
	# pass-through case — but nothing may leave raw 1..4095 (C2).
	var high := GenParams.new()
	high.seed = 5
	high.scale_m = 300.0
	high.base_raw = 3000
	high.relief_m = 400.0
	var r := TerrainGenerator.generate(high, 64, 64)
	t.ok(bool(r.get("ok", false)), "over-driven parameters still generate")
	_assert_in_range(t, r["heights"], "ceiling case")
	t.ok(int((r["stats"] as Dictionary)["clipped_high"]) > 0, "the ceiling clamp fired")
	t.eq(int((r["stats"] as Dictionary)["clipped_low"]), 0, "nothing hit the floor here")

	var low := GenParams.new()
	low.seed = 6
	low.scale_m = 300.0
	low.base_raw = 100
	low.relief_m = 50.0
	low.shape = GenParams.SHAPE_BASIN
	low.shape_m = 200.0
	var r2 := TerrainGenerator.generate(low, 64, 64)
	t.ok(bool(r2.get("ok", false)), "under-driven parameters still generate")
	_assert_in_range(t, r2["heights"], "floor case")
	t.ok(int((r2["stats"] as Dictionary)["clipped_low"]) > 0, "the floor clamp fired")

	var bad := TerrainGenerator.generate(GenParams.new(), 1, 1)
	t.ok(not bool(bad.get("ok", true)), "a 1x1 grid is refused")
	t.ok("2x2" in str(bad.get("message", "")), "refusal explains the minimum")


func _test_shapes(t) -> void:
	var w := 1280.0
	var d := 1280.0
	t.near(TerrainGenerator.shape_value(GenParams.SHAPE_NONE, 100.0, 100.0, w, d), 0.0, 0.0001)
	# Crater: floor is below the plane, rim is above it, outside is flat.
	var centre := TerrainGenerator.shape_value(GenParams.SHAPE_CRATER, 640.0, 640.0, w, d)
	var rim := TerrainGenerator.shape_value(GenParams.SHAPE_CRATER, 640.0 + 397.0, 640.0, w, d)
	var far := TerrainGenerator.shape_value(GenParams.SHAPE_CRATER, 0.0, 0.0, w, d)
	t.ok(centre < -0.3, "crater floor is dug out (%.3f)" % centre)
	t.ok(rim > 0.8, "crater rim is raised (%.3f)" % rim)
	t.near(far, 0.0, 0.001, "crater apron returns to the base plane")
	t.near(
		TerrainGenerator.shape_value(GenParams.SHAPE_PLATEAU, 640.0, 640.0, w, d),
		1.0,
		0.0001,
		"plateau tops out in the middle",
	)
	# A non-square map still gets a circle, not an ellipse: the same distance
	# in metres from the centre gives the same value on both axes.
	var wide := 2560.0
	var on_x := TerrainGenerator.shape_value(GenParams.SHAPE_PLATEAU, 1280.0 + 300.0, 640.0, wide, d)
	var on_z := TerrainGenerator.shape_value(GenParams.SHAPE_PLATEAU, 1280.0, 640.0 + 300.0, wide, d)
	t.near(on_x, on_z, 0.0001, "circular shapes stay circular on a non-square map")
	var bounded := true
	for i in 40:
		for shape in [
			GenParams.SHAPE_CRATER,
			GenParams.SHAPE_BASIN,
			GenParams.SHAPE_VALLEY,
			GenParams.SHAPE_PLATEAU,
			GenParams.SHAPE_BORDER,
		]:
			var v := TerrainGenerator.shape_value(shape, float(i) * 32.0, float(i) * 17.0, w, d)
			if v < -1.0 or v > 1.0:
				bounded = false
	t.ok(bounded, "every shape stays inside -1..1")


func _test_metrics(t) -> void:
	# A constant 1 m per 5 m cell ramp along +x is a slope of 0.2 m/m.
	var gx := 8
	var gz := 4
	var h := PackedInt32Array()
	h.resize(gx * gz)
	for z in gz:
		for x in gx:
			h[z * gx + x] = 1000 + x * 10
	var s := GenMetrics.slope_field(h, gx, gz)
	t.near(s[2 * gx + 3], 0.2, 0.0001, "interior slope of a 10-raw-per-cell ramp")
	t.near(s[2 * gx + 0], 0.2, 0.0001, "edge slope uses a one-sided difference")
	var flat := PackedInt32Array()
	flat.resize(gx * gz)
	flat.fill(1000)
	var m := GenMetrics.measure(flat, gx, gz, GenMetrics.CELL_M, true)
	t.near(float(m["mean_slope"]), 0.0, 0.0001, "flat ground has no slope")
	t.near(float(m["buildable_frac"]), 1.0, 0.0001, "flat ground is entirely buildable")
	t.eq(int(m["largest_buildable_cells"]), gx * gz, "flat ground is one pocket")
	t.near(float(m["largest_buildable_m2"]), float(gx * gz) * 25.0, 0.01, "pocket area in m2")

	# Two flat shelves split by a wall are two pockets, not one.
	var split := PackedInt32Array()
	split.resize(16 * 16)
	for z in 16:
		for x in 16:
			split[z * 16 + x] = 1000 if x < 8 else 2000
	var s2 := GenMetrics.slope_field(split, 16, 16)
	var pocket := GenMetrics.largest_pocket(s2, 16, 16, GenMetrics.BUILDABLE_SLOPE)
	t.ok(pocket > 0 and pocket < 16 * 16, "the wall splits the buildable area (%d cells)" % pocket)


func _test_preview_exact(t) -> void:
	# The preview decimates by an integer step, so with erosion off it is not
	# an approximation of the full-resolution field — it IS that field, sampled
	# every k-th cell. That is the strongest form of "representative".
	var p := GenPresets.make("highlands", 808)
	p.erosion_steps = 0
	p.hydro_droplets = 0
	var full := TerrainGenerator.generate(p, 257, 257)
	var prev := TerrainGenerator.generate_preview(p, 257, 257, 129)
	t.eq(int(prev["step"]), 2, "129 px cap over a 257 grid decimates by 2")
	t.eq(int(prev["grid_x"]), 129, "preview width")
	t.eq(int(prev["grid_z"]), 129, "preview height")
	t.near(float(prev["cell_m"]), 10.0, 0.0001, "preview cell size doubles")
	var fh: PackedInt32Array = full["heights"]
	var ph: PackedInt32Array = prev["heights"]
	var mismatches := 0
	for z in 129:
		for x in 129:
			if ph[z * 129 + x] != fh[(z * 2) * 257 + (x * 2)]:
				mismatches += 1
	t.eq(mismatches, 0, "every preview cell equals the full-resolution cell beneath it")

	t.eq(TerrainGenerator.preview_step(1024, 1024, 512), 2, "1024 grid previews at step 2")
	t.eq(TerrainGenerator.preview_dims(1024, 1024, 512), Vector2i(512, 512), "1024 preview dims")
	t.eq(TerrainGenerator.preview_step(256, 256, 512), 1, "a small map previews at full res")
	t.eq(TerrainGenerator.preview_dims(1024, 512, 512), Vector2i(512, 256), "non-square preview")

	var img := TerrainGenerator.preview_image(ph, 129, 129, 10.0)
	t.eq(img.get_width(), 129, "preview image width")
	t.eq(img.get_height(), 129, "preview image height")
	t.eq(img.get_format(), Image.FORMAT_RGB8, "preview image is RGB8")


func _test_preview_representative(t) -> void:
	# With erosion on the two resolutions genuinely differ, so the contract is
	# weaker: the preview must still tell the truth about the terrain.
	var p := GenPresets.make("mesa", 31337)
	var full := TerrainGenerator.generate(p, 129, 129)
	var prev := TerrainGenerator.generate_preview(p, 129, 129, 65)
	var fs: Dictionary = full["stats"]
	var ps: Dictionary = prev["stats"]
	t.ok(
		absf(float(fs["buildable_frac"]) - float(ps["buildable_frac"])) < 0.12,
		"preview buildable %.3f tracks full %.3f" % [ps["buildable_frac"], fs["buildable_frac"]],
	)
	t.ok(
		absf(float(fs["relief_m"]) - float(ps["relief_m"])) < 12.0,
		"preview relief %.1f m tracks full %.1f m" % [ps["relief_m"], fs["relief_m"]],
	)
	t.ok(
		absf(float(fs["mean_raw"]) - float(ps["mean_raw"])) < 40.0,
		"preview mean height tracks full mean height",
	)


func _assert_in_range(t, heights: PackedInt32Array, label: String) -> void:
	var lo := 0x7FFFFFFF
	var hi := -1
	for v in heights:
		lo = mini(lo, v)
		hi = maxi(hi, v)
	t.ok(lo >= 1, "%s: no cell below raw 1 (got %d)" % [label, lo])
	t.ok(hi <= 4095, "%s: no cell above raw 4095 (got %d)" % [label, hi])
