extends RefCounted
## Thermal and droplet erosion: determinism, mass conservation, the talus
## angle actually holding, and the slope actually coming down.


func run(t) -> void:
	_test_thermal_noop(t)
	_test_thermal_determinism(t)
	_test_thermal_conserves_mass(t)
	_test_thermal_flattens(t)
	_test_thermal_dilation(t)
	_test_hydraulic_determinism(t)
	_test_hydraulic_effect(t)


## A rough but reproducible test field, in metres. Deliberately not FbmNoise:
## the erosion tests must fail for erosion reasons, not noise reasons.
func _rough(gx: int, gz: int) -> PackedFloat64Array:
	var h := PackedFloat64Array()
	h.resize(gx * gz)
	var state := 0x1234ABCD
	for i in h.size():
		state = (state * 1103515245 + 12345) & 0x7FFFFFFF
		h[i] = 100.0 + float(state % 1000) * 0.06
	return h


func _sum(h: PackedFloat64Array) -> float:
	var s := 0.0
	for v in h:
		s += v
	return s


func _mean_slope(h: PackedFloat64Array, gx: int, gz: int, cell_m: float) -> float:
	var total := 0.0
	var n := 0
	for z in range(1, gz - 1):
		for x in range(1, gx - 1):
			var i := z * gx + x
			var dx := (h[i + 1] - h[i - 1]) / (2.0 * cell_m)
			var dz := (h[i + gx] - h[i - gx]) / (2.0 * cell_m)
			total += sqrt(dx * dx + dz * dz)
			n += 1
	return total / float(maxi(1, n))


func _test_thermal_noop(t) -> void:
	# Ground already inside the talus angle must come back untouched, bit for
	# bit — no drift from a pass that had nothing to do.
	var gx := 24
	var gz := 24
	var flat := PackedFloat64Array()
	flat.resize(gx * gz)
	for z in gz:
		for x in gx:
			flat[z * gx + x] = 100.0 + float(x) * 0.5  # 0.1 m/m over 5 m cells
	var before := flat.duplicate()
	TerrainErosion.thermal(flat, gx, gz, 5.0, 4, 0.4, 0.5, 0.5)
	t.eq(flat, before, "a slope under the talus angle is left alone")

	var too_small := PackedFloat64Array([1.0])
	TerrainErosion.thermal(too_small, 1, 1, 5.0, 4, 0.4, 0.5, 0.5)
	t.eq(too_small.size(), 1, "a degenerate grid is refused without crashing")

	var zero_steps := _rough(16, 16)
	var untouched := zero_steps.duplicate()
	TerrainErosion.thermal(zero_steps, 16, 16, 5.0, 0, 0.4, 0.3, 0.5)
	t.eq(zero_steps, untouched, "0 steps is a no-op")


func _test_thermal_determinism(t) -> void:
	var gx := 40
	var gz := 32
	var a := _rough(gx, gz)
	var b := a.duplicate()
	TerrainErosion.thermal(a, gx, gz, 5.0, 6, 0.4, 0.25, 0.6)
	TerrainErosion.thermal(b, gx, gz, 5.0, 6, 0.4, 0.25, 0.6)
	t.eq(a, b, "thermal erosion is reproducible")
	t.eq(a.to_byte_array(), b.to_byte_array(), "and byte-identical")


func _test_thermal_conserves_mass(t) -> void:
	# Thermal transport only moves material; it never creates or destroys it.
	# Every delta is written as a matched pair, so this holds to rounding.
	var gx := 48
	var gz := 40
	var h := _rough(gx, gz)
	var before := _sum(h)
	TerrainErosion.thermal(h, gx, gz, 5.0, 8, 0.45, 0.2, 0.7)
	var after := _sum(h)
	t.ok(
		absf(after - before) < absf(before) * 0.000000001,
		"mass is conserved (%.6f -> %.6f)" % [before, after],
	)


func _test_thermal_flattens(t) -> void:
	var gx := 64
	var gz := 64
	var h := _rough(gx, gz)
	var lo_before := h[0]
	var hi_before := h[0]
	for v in h:
		lo_before = minf(lo_before, v)
		hi_before = maxf(hi_before, v)
	var slope_before := _mean_slope(h, gx, gz, 5.0)
	TerrainErosion.thermal(h, gx, gz, 5.0, 10, 0.4, 0.2, 0.6)
	var slope_after := _mean_slope(h, gx, gz, 5.0)
	t.ok(
		slope_after < slope_before * 0.75,
		"mean slope falls (%.4f -> %.4f)" % [slope_before, slope_after],
	)
	var lo_after := h[0]
	var hi_after := h[0]
	for v in h:
		lo_after = minf(lo_after, v)
		hi_after = maxf(hi_after, v)
	t.ok(
		hi_after <= hi_before + 0.000001,
		"the global maximum is never pushed up (%.4f -> %.4f)" % [hi_before, hi_after],
	)
	t.ok(
		lo_after >= lo_before - 0.000001,
		"the global minimum is never pushed down (%.4f -> %.4f)" % [lo_before, lo_after],
	)

	# A lone spike is exactly what a talus angle is for.
	var spike := PackedFloat64Array()
	spike.resize(gx * gz)
	spike.fill(100.0)
	spike[32 * gx + 32] = 180.0
	TerrainErosion.thermal(spike, gx, gz, 5.0, 20, 0.5, 0.5, 0.4)
	t.ok(spike[32 * gx + 32] < 150.0, "the spike collapses (%.1f m)" % spike[32 * gx + 32])
	t.ok(spike[32 * gx + 33] > 100.0, "its material lands next to it")


func _test_thermal_dilation(t) -> void:
	# dilation 0 sends everything to the steepest neighbour; dilation 1 shares
	# it out. Both move the same amount of material, but not to the same place.
	var gx := 33
	var gz := 33
	var cone := PackedFloat64Array()
	cone.resize(gx * gz)
	for z in gz:
		for x in gx:
			var d := sqrt(float((x - 16) * (x - 16) + (z - 16) * (z - 16)))
			cone[z * gx + x] = 100.0 + maxf(0.0, 60.0 - d * 6.0)
	var steep := cone.duplicate()
	var spread := cone.duplicate()
	TerrainErosion.thermal(steep, gx, gz, 5.0, 6, 0.4, 0.3, 0.0)
	TerrainErosion.thermal(spread, gx, gz, 5.0, 6, 0.4, 0.3, 1.0)
	t.ne(steep, spread, "dilation changes where the material goes")
	t.ok(
		absf(_sum(steep) - _sum(spread)) < 0.0001,
		"both dilation settings conserve the same mass",
	)
	t.ok(
		_mean_slope(spread, gx, gz, 5.0) <= _mean_slope(steep, gx, gz, 5.0) + 0.0001,
		"spreading the transport does not leave the cone rougher",
	)


func _test_hydraulic_determinism(t) -> void:
	var gx := 48
	var gz := 48
	var a := _rough(gx, gz)
	var b := a.duplicate()
	TerrainErosion.hydraulic(a, gx, gz, 5.0, 909, 500, 24, 0.06, 3.0, 0.25, 0.25)
	TerrainErosion.hydraulic(b, gx, gz, 5.0, 909, 500, 24, 0.06, 3.0, 0.25, 0.25)
	t.eq(a.to_byte_array(), b.to_byte_array(), "droplet erosion is byte-identical across runs")

	var c := _rough(gx, gz)
	TerrainErosion.hydraulic(c, gx, gz, 5.0, 910, 500, 24, 0.06, 3.0, 0.25, 0.25)
	t.ne(c, a, "a different droplet seed carves a different field")

	var none := _rough(gx, gz)
	var untouched := none.duplicate()
	TerrainErosion.hydraulic(none, gx, gz, 5.0, 909, 0, 24, 0.06, 3.0, 0.25, 0.25)
	t.eq(none, untouched, "0 droplets is a no-op")


func _test_hydraulic_effect(t) -> void:
	# A broad slope tilted along +z. Droplets must carry material downhill:
	# the head of the slope loses height, the foot gains it, and nothing is
	# created or destroyed on the way.
	var gx := 64
	var gz := 64
	var h := PackedFloat64Array()
	h.resize(gx * gz)
	var state := 0x5A5A11
	for z in gz:
		for x in gx:
			state = (state * 1103515245 + 12345) & 0x7FFFFFFF
			h[z * gx + x] = 200.0 - float(z) * 1.5 + float(state % 100) * 0.05
	var before := h.duplicate()
	var hi_before := -1000.0
	for v in h:
		hi_before = maxf(hi_before, v)
	var sum_before := _sum(h)
	TerrainErosion.hydraulic(h, gx, gz, 5.0, 4242, 4000, 30, 0.06, 3.0, 0.3, 0.3)

	var hi_after := -1000.0
	var finite := true
	var moved := 0
	for i in h.size():
		hi_after = maxf(hi_after, h[i])
		if not is_finite(h[i]):
			finite = false
		if absf(h[i] - before[i]) > 0.01:
			moved += 1
	t.ok(finite, "no droplet produced a NaN or an infinity")
	t.ok(moved > h.size() / 4, "droplets reworked the field (%d/%d cells)" % [moved, h.size()])
	t.ok(
		hi_after <= hi_before + 1.0,
		"droplets do not raise the terrain ceiling (%.2f -> %.2f)" % [hi_before, hi_after],
	)
	t.ok(
		absf(_sum(h) - sum_before) < absf(sum_before) * 0.000000001,
		"droplet transport conserves mass (%.3f -> %.3f)" % [sum_before, _sum(h)],
	)
	# Hydraulic erosion is transport, not smoothing — it cuts channels, so the
	# mean slope may well go UP. What must hold is the direction of travel.
	var head_before := _band_mean(before, gx, 0, 8)
	var head_after := _band_mean(h, gx, 0, 8)
	var foot_before := _band_mean(before, gx, gz - 8, gz)
	var foot_after := _band_mean(h, gx, gz - 8, gz)
	t.ok(
		head_after < head_before - 0.1,
		"the head of the slope is cut back (%.2f -> %.2f)" % [head_before, head_after],
	)
	t.ok(
		foot_after > foot_before + 0.1,
		"the foot of the slope is built up (%.2f -> %.2f)" % [foot_before, foot_after],
	)


func _band_mean(h: PackedFloat64Array, gx: int, z0: int, z1: int) -> float:
	var total := 0.0
	var n := 0
	for z in range(z0, z1):
		for x in gx:
			total += h[z * gx + x]
			n += 1
	return total / float(maxi(1, n))
