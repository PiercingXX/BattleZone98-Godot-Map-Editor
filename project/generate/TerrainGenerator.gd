extends RefCounted
class_name TerrainGenerator
## Procedural terrain generation: noise, landform, remap, erosion, quantise.
##
## The pipeline, in order, is the whole story:
##   1. fBm over FastNoiseLite, sampled in world metres          (FbmNoise)
##   2. remap through the LUT — plateaus and mesa benches        (RemapCurve)
##   3. add the closed-form landform (crater rim, valley walls)  (shape_value)
##   4. thermal erosion, then optional droplet erosion           (TerrainErosion)
##   5. quantise once to raw 1..4095                             (C1/C2)
##
## Nothing writes into the session. `generate()` hands back a PackedInt32Array
## and the caller wraps it in an undoable whole-field command (C16) — see the
## note on HeightmapImportCommand at the bottom of this file.
##
## Determinism (C6). Same GenParams plus same output grid gives the same bytes:
## every loop is an integer `for`, no Dictionary iteration reaches the output,
## the amplitude ladder is built by multiplication rather than pow(), the shape
## functions use only arithmetic and smoothstep (no exp/pow/trig), and droplet
## spawn points come from an integer xorshift. The one thing outside GDScript's
## control is FastNoiseLite's own float arithmetic; see FbmNoise.
##
## Preview. `generate_preview()` decimates by an INTEGER step, so with erosion
## off the preview is not merely similar to the full-resolution result — it is
## exactly the full-resolution result sampled every k-th cell.

const CELL_M := 5.0
const HEIGHT_SCALE := 0.1
const RAW_MIN := 1
const RAW_MAX := 4095
const PREVIEW_MAX_PX := 512


## Full-resolution generation over the map's own grid.
static func generate(p: GenParams, grid_x: int, grid_z: int) -> Dictionary:
	return _run(p, grid_x, grid_z, 1, true)


## Reduced-resolution generation over the same world rectangle, for the dialog.
static func generate_preview(
	p: GenParams, grid_x: int, grid_z: int, max_px: int = PREVIEW_MAX_PX
) -> Dictionary:
	return _run(p, grid_x, grid_z, preview_step(grid_x, grid_z, max_px), false)


## Decimation factor the preview will use. 1 means the map is already small
## enough to preview at full resolution.
static func preview_step(grid_x: int, grid_z: int, max_px: int = PREVIEW_MAX_PX) -> int:
	var cap := maxi(2, max_px)
	var k := 1
	while (grid_x - 1) / k + 1 > cap or (grid_z - 1) / k + 1 > cap:
		k += 1
	return k


static func preview_dims(grid_x: int, grid_z: int, max_px: int = PREVIEW_MAX_PX) -> Vector2i:
	if grid_x < 2 or grid_z < 2:
		return Vector2i(maxi(1, grid_x), maxi(1, grid_z))
	var k := preview_step(grid_x, grid_z, max_px)
	return Vector2i((grid_x - 1) / k + 1, (grid_z - 1) / k + 1)


## Large-scale landform in -1..1 at a world position. Circular shapes measure
## in metres against the shorter axis, so a 5120x2560 map still gets a circle
## rather than an ellipse. Arithmetic and smoothstep only — no libm call whose
## last bit could differ between platforms.
static func shape_value(
	shape: int, wx: float, wz: float, width_m: float, depth_m: float
) -> float:
	if shape == GenParams.SHAPE_NONE:
		return 0.0
	var half_x := width_m * 0.5
	var half_z := depth_m * 0.5
	if shape == GenParams.SHAPE_VALLEY:
		var u := absf(wx - half_x) / maxf(1.0, half_x)
		return smoothstep(0.45, 0.85, u)
	var radius := maxf(1.0, minf(half_x, half_z))
	var dx := (wx - half_x) / radius
	var dz := (wz - half_z) / radius
	var d := sqrt(dx * dx + dz * dz)
	match shape:
		GenParams.SHAPE_CRATER:
			var rim := smoothstep(0.46, 0.62, d) * smoothstep(0.78, 0.62, d)
			return rim - 0.38 * smoothstep(0.55, 0.18, d)
		GenParams.SHAPE_BASIN:
			return -smoothstep(0.95, 0.25, d)
		GenParams.SHAPE_PLATEAU:
			return smoothstep(0.72, 0.40, d)
		GenParams.SHAPE_BORDER:
			return smoothstep(0.78, 1.0, d)
	return 0.0


## Readable one-liner for the log and the dialog footer.
static func describe_stats(stats: Dictionary) -> String:
	return "%.0f%% buildable, %.0f%% drivable, relief %.0f m, mean slope %.0f%%" % [
		float(stats.get("buildable_frac", 0.0)) * 100.0,
		float(stats.get("traversable_frac", 0.0)) * 100.0,
		float(stats.get("relief_m", 0.0)),
		float(stats.get("mean_slope", 0.0)) * 100.0,
	]


## Hillshade with the buildable ground tinted, for the preview pane. North-up
## (C8): +z is the top row, and the light comes from the top of the image.
static func preview_image(heights: PackedInt32Array, gx: int, gz: int, cell_m: float = CELL_M) -> Image:
	if gx < 1 or gz < 1 or heights.size() != gx * gz:
		return Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
	var slopes := GenMetrics.slope_field(heights, gx, gz, cell_m)
	var lo := heights[0]
	var hi := heights[0]
	for i in heights.size():
		lo = mini(lo, heights[i])
		hi = maxi(hi, heights[i])
	var span := maxf(1.0, float(hi - lo))
	var buf := PackedByteArray()
	buf.resize(gx * gz * 3)
	for z in gz:
		var row := z * gx
		var up := maxi(0, z - 1) * gx
		for x in gx:
			var i := row + x
			var tone := float(heights[i] - lo) / span
			var shade := clampf(
				0.55 + (float(heights[i] - heights[up + x]) * HEIGHT_SCALE) / (cell_m * 0.6),
				0.15,
				1.0
			)
			var lum := clampf((0.35 + 0.65 * tone) * shade, 0.0, 1.0)
			var r := lum
			var g := lum
			var b := lum
			if slopes[i] <= GenMetrics.BUILDABLE_SLOPE:
				g = clampf(lum * 1.15 + 0.10, 0.0, 1.0)
			elif slopes[i] > GenMetrics.TRAVERSABLE_SLOPE:
				r = clampf(lum * 1.10 + 0.14, 0.0, 1.0)
				b = clampf(b * 0.75, 0.0, 1.0)
			var o := i * 3
			buf[o] = int(r * 255.0)
			buf[o + 1] = int(g * 255.0)
			buf[o + 2] = int(b * 255.0)
	return Image.create_from_data(gx, gz, false, Image.FORMAT_RGB8, buf)


static func _run(p: GenParams, grid_x: int, grid_z: int, step: int, with_pockets: bool) -> Dictionary:
	if p == null:
		return {"ok": false, "message": "no generator parameters"}
	if grid_x < 2 or grid_z < 2:
		return {"ok": false, "message": "map grid is %dx%d; need at least 2x2" % [grid_x, grid_z]}
	var problem := p.validate()
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	var started := Time.get_ticks_msec()
	var k := maxi(1, step)
	var out_gx := (grid_x - 1) / k + 1
	var out_gz := (grid_z - 1) / k + 1
	var cell_m := CELL_M * float(k)
	var width_m := float(grid_x - 1) * CELL_M
	var depth_m := float(grid_z - 1) * CELL_M

	var noise := FbmNoise.new()
	noise.configure(p)
	var field := noise.fill(out_gx, out_gz, cell_m, 0.0, 0.0)

	var base_m := float(p.base_raw) * HEIGHT_SCALE
	for z in out_gz:
		var row := z * out_gx
		var wz := float(z) * cell_m
		for x in out_gx:
			var i := row + x
			var h := base_m + RemapCurve.eval(p.curve, field[i]) * p.relief_m
			if p.shape != GenParams.SHAPE_NONE and p.shape_m != 0.0:
				h += shape_value(p.shape, float(x) * cell_m, wz, width_m, depth_m) * p.shape_m
			field[i] = h

	if p.erosion_steps > 0:
		TerrainErosion.thermal(
			field,
			out_gx,
			out_gz,
			cell_m,
			p.erosion_steps,
			p.erosion_weight,
			p.erosion_slope,
			p.erosion_dilation
		)
	if p.hydro_droplets > 0:
		# Droplets are per unit area, so a decimated preview gets 1/k^2 of them
		# and carves a network of the same density.
		var droplets := p.hydro_droplets / (k * k)
		TerrainErosion.hydraulic(
			field,
			out_gx,
			out_gz,
			cell_m,
			p.seed,
			droplets,
			p.hydro_lifetime,
			p.hydro_inertia,
			p.hydro_capacity,
			p.hydro_erode,
			p.hydro_deposit
		)

	var heights := PackedInt32Array()
	heights.resize(out_gx * out_gz)
	var clipped_low := 0
	var clipped_high := 0
	for i in heights.size():
		# floor(v + 0.5), not roundi(): one fixed rule, no half-away-from-zero
		# corner to argue about, and heights here are never negative.
		var raw := int(floor(field[i] * 10.0 + 0.5))
		if raw < RAW_MIN:
			raw = RAW_MIN
			clipped_low += 1
		elif raw > RAW_MAX:
			raw = RAW_MAX
			clipped_high += 1
		heights[i] = raw

	var stats := GenMetrics.measure(heights, out_gx, out_gz, cell_m, with_pockets)
	stats["clipped_low"] = clipped_low
	stats["clipped_high"] = clipped_high
	return {
		"ok": true,
		"heights": heights,
		"grid_x": out_gx,
		"grid_z": out_gz,
		"cell_m": cell_m,
		"step": k,
		"preset": p.preset,
		"stats": stats,
		"elapsed_ms": Time.get_ticks_msec() - started,
	}
