extends RefCounted
class_name SculptTool
## Brush kernels over the height / material grids.

const HeightStrokeCommandScript = preload("res://project/commands/HeightStrokeCommand.gd")
const MaterialStrokeCommandScript = preload("res://project/commands/MaterialStrokeCommand.gd")
const MaskStrokeCommandScript = preload("res://project/commands/MaskStrokeCommand.gd")

const RAW_MIN := 1
const RAW_MAX := 4095

## raise / lower / flatten / smooth / ramp / noise / clone / paint, plus the
## brushes added on top of them: erode / dilate / setheight / setangle.
var mode: String = "raise"
var shape: String = "circle"
var radius_m: float = 40.0
var falloff: float = 0.65
var strength: float = 0.45
var flatten_target: int = -1
var paint_material: int = 0
var last_uploaded: int = 0

## Generated tip id from BrushMaskLibrary. Empty = the analytic shape above,
## which is the default so nothing that worked before changes.
var mask_id: String = "":
	set(v):
		mask_id = v
		_mask = BrushMaskLibrary.get_mask(v)
## Tip rotation. Random adds a per-dab turn from the stroke RNG (C6).
var rotation_deg: float = 0.0
var random_rotation: bool = false
## Dab gates. Fraction-of-radius distance and milliseconds; 0 disables either.
var spacing_frac: float = 0.0
var spacing_ms: int = 0
## Pen pressure 0..1 and how much of it reaches size and opacity.
var pressure: float = 1.0
var pressure_size: float = 0.0
var pressure_opacity: float = 0.0
## Slope / height bands. Off = the brush writes wherever its weight reaches.
var limit_slope: bool = false
var slope_min_deg: float = 0.0
var slope_max_deg: float = 90.0
var slope_feather_deg: float = 5.0
var limit_height: bool = false
var height_min_m: float = 0.0
var height_max_m: float = 409.5
var height_feather_m: float = 2.0
## Noise brush. Amplitude is metres; scale is the period of one noise cycle.
var noise_frequency: float = 0.02
var noise_octaves: int = 3
var noise_amplitude_m: float = 6.0
var noise_scale: float = 10.0
var noise_contrast: float = 1.0
## Clone: absolute sampled height vs destination-relative delta.
var clone_match_height: bool = true
## Seeds the noise field and the random-rotation stream. Fixed = reproducible.
var brush_seed: int = 1
## Morphological erode / dilate. Slack is the height cost per cell of
## horizontal excess past the disc — larger flattens the element toward a disc.
var erode_radius_m: float = 10.0
var erode_slack_m: float = 3.0
## Set-height target, and the constant-slope plane for set-angle.
var set_height_m: float = 25.0
var angle_deg: float = 15.0
## Compass bearing of the ascent: 0 = +z (north, C8), 90 = +x.
var angle_dir_deg: float = 0.0
var angle_origin_m: Vector2 = Vector2.INF
## Interactive strokes adopt the live brush at mouse-down. A scripted caller
## that marches its own dabs (the ramp tool, batch edits, tests) clears this
## and keeps whatever it assigned — a user spacing gate would eat its march.
var follow_tool_state: bool = true

var _stroke_x0: int = 0
var _stroke_z0: int = 0
var _stroke_x1: int = 0
var _stroke_z1: int = 0
## Chunked undo capture. A chunk is copied the first time a stamp writes into
## it, so mouse-down allocates nothing and the record costs edited area.
var _heights := RasterChunks.new()
var _mats := RasterChunks.new()
var _masks := RasterChunks.new()
var _active: bool = false
var _is_paint: bool = false
var _is_mask: bool = false
var _is_clone: bool = false
var _clone_mats: bool = false
var _clone_off_x: int = 0
var _clone_off_z: int = 0
var _clone_src_base: int = 0
var _clone_dst_base: int = 0
var _mask_stem: String = ""
var _mask_value: int = 255
var _mask: BrushMask = null
## Per-dab tip rotation in radians, and the radius pressure left us with.
var _dab_rot: float = 0.0
var _dab_radius: float = 0.0
## Effective strength for the dab, resolved once instead of per cell.
var _dab_amt: float = -1.0
var _dabs: int = 0
var _last_dab: Vector2 = Vector2.ZERO
var _last_dab_ms: int = 0
## Re-seeded at begin_stroke so a replayed stroke lands the same bytes (C6).
var _rng := RandomNumberGenerator.new()
var _noise: FastNoiseLite = null
var _noise_key: String = ""
var _plane_origin: Vector2 = Vector2.ZERO
var _plane_h_m: float = 0.0
var _plane_dir: Vector2 = Vector2(0.0, 1.0)
## Flattened pre-stroke window for the morphology kernel; 0 width = unarmed.
var _morph_buf: PackedInt32Array = PackedInt32Array()
var _morph_x0: int = 0
var _morph_z0: int = 0
var _morph_w: int = 0
var _morph_h: int = 0
var _morph_rc: int = 1
## Structuring-element penalty per offset, in raw height units.
var _morph_pen: PackedInt32Array = PackedInt32Array()


func begin_stroke(field: HeightField, cx_m: float, cz_m: float, paint: bool) -> void:
	pull_brush_params()
	_active = true
	_is_paint = paint
	_is_mask = false
	_is_clone = mode == "clone"
	_clone_mats = _is_clone and ToolState.clone_materials
	_mask_stem = ""
	_touch_reset()
	if paint:
		_heights.begin(0, 0)
		_mats.begin(MapState.mat_grid_x, MapState.mat_grid_z)
	else:
		_heights.begin(field.grid_x, field.grid_z)
		if _clone_mats:
			_mats.begin(MapState.mat_grid_x, MapState.mat_grid_z)
		else:
			_mats.begin(0, 0)
	flatten_target = field.height_raw(int(cx_m / HeightField.CELL_M), int(cz_m / HeightField.CELL_M))
	if _is_clone:
		_begin_clone(field, cx_m, cz_m)
	if mode == "setangle":
		_begin_plane(field, cx_m, cz_m)
	stamp(field, cx_m, cz_m)


func begin_mask_stroke(field: HeightField, cx_m: float, cz_m: float, stem: String, value: int) -> void:
	pull_brush_params()
	_active = true
	_is_paint = false
	_is_mask = true
	_mask_stem = stem
	_mask_value = value & 0xFF
	_touch_reset()
	_masks.begin(field.grid_x, field.grid_z)
	stamp(field, cx_m, cz_m)


func stamp(field: HeightField, cx_m: float, cz_m: float) -> void:
	if not _active or field == null:
		return
	if not _accept_dab(cx_m, cz_m):
		return
	var pts: Array[Vector2] = ToolState.world_image_points(cx_m, cz_m)
	if pts.is_empty():
		pts = [Vector2(cx_m, cz_m)]
	if _is_mask:
		for p in pts:
			_stamp_mask(p.x, p.y)
		return
	if field.grid_x < 2:
		return
	if _is_paint:
		for p in pts:
			_stamp_paint(p.x, p.y)
		return
	_stamp_height_points(field, pts)
	if _is_clone and _clone_mats:
		for p in pts:
			_stamp_clone_materials(p.x, p.y)


func _stamp_height_points(field: HeightField, pts: Array[Vector2]) -> void:
	if pts.size() <= 1:
		var p: Vector2 = pts[0] if not pts.is_empty() else Vector2.ZERO
		_stamp_height_one(field, p.x, p.y)
		return
	var cell := HeightField.CELL_M
	var r_cells := int(ceil(_scan_radius() / cell))
	var rects: Array[Rect2i] = []
	for p in pts:
		var cx := int(floor(p.x / cell))
		var cz := int(floor(p.y / cell))
		var x0 := maxi(0, cx - r_cells)
		var z0 := maxi(0, cz - r_cells)
		var x1 := mini(field.grid_x - 1, cx + r_cells)
		var z1 := mini(field.grid_z - 1, cz + r_cells)
		if x1 < x0 or z1 < z0:
			continue
		rects.append(Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1))
		_expand(x0, z0, x1, z1)
		# Capture every rect before any of them is written, so a clone kernel
		# sampling a sibling symmetry copy still reads the pre-stroke grid.
		_heights.touch(field.heights, x0, z0, x1, z1)
	if rects.is_empty():
		return
	var seen: Dictionary = {}
	var hit_ceiling := false
	var uploaded := 0
	for r in rects:
		_prepare_morph(field, r.position.x, r.position.y, r.end.x - 1, r.end.y - 1)
		for z in range(r.position.y, r.position.y + r.size.y):
			for x in range(r.position.x, r.position.x + r.size.x):
				var idx := z * field.grid_x + x
				if seen.has(idx):
					continue
				seen[idx] = true
				var wx := (float(x) + 0.5) * cell
				var wz := (float(z) + 0.5) * cell
				var w := 0.0
				for p in pts:
					w = maxf(w, _weight(p.x, p.y, wx, wz))
				w *= MapState.selection_factor(x, z) * _limit_factor_cell(field, x, z)
				if w <= 0.0:
					continue
				var cur := field.heights[idx]
				var nxt := _apply_height(cur, w, x, z, field)
				if nxt >= RAW_MAX and cur < RAW_MAX:
					hit_ceiling = true
				field.heights[idx] = nxt
		field.upload_rect(r.position.x, r.position.y, r.size.x, r.size.y)
		uploaded += r.size.x * r.size.y * 4
	last_uploaded = uploaded
	if hit_ceiling:
		MapState.ceiling_hit = true


func _stamp_height_one(field: HeightField, cx_m: float, cz_m: float) -> void:
	var cell := HeightField.CELL_M
	var r_cells := int(ceil(_scan_radius() / cell))
	var cx := int(floor(cx_m / cell))
	var cz := int(floor(cz_m / cell))
	var x0 := maxi(0, cx - r_cells)
	var z0 := maxi(0, cz - r_cells)
	var x1 := mini(field.grid_x - 1, cx + r_cells)
	var z1 := mini(field.grid_z - 1, cz + r_cells)
	if x1 < x0 or z1 < z0:
		return
	_expand(x0, z0, x1, z1)
	_heights.touch(field.heights, x0, z0, x1, z1)
	_prepare_morph(field, x0, z0, x1, z1)
	var hit_ceiling := false
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := (float(x) + 0.5) * cell
			var wz := (float(z) + 0.5) * cell
			var w := _weight(cx_m, cz_m, wx, wz) * MapState.selection_factor(x, z)
			w *= _limit_factor_cell(field, x, z)
			if w <= 0.0:
				continue
			var idx := z * field.grid_x + x
			var cur := field.heights[idx]
			var nxt := _apply_height(cur, w, x, z, field)
			if nxt >= RAW_MAX and cur < RAW_MAX:
				hit_ceiling = true
			field.heights[idx] = nxt
	field.upload_rect(x0, z0, x1 - x0 + 1, z1 - z0 + 1)
	last_uploaded = (x1 - x0 + 1) * (z1 - z0 + 1) * 4
	if hit_ceiling:
		MapState.ceiling_hit = true


func end_stroke(field: HeightField):
	if not _active or _is_paint or _is_mask:
		_active = false
		_dab_radius = 0.0
		_dab_amt = -1.0
		_is_clone = false
		return null
	_active = false
	_dab_radius = 0.0
	_dab_amt = -1.0
	var height_regions := _heights.regions(field.heights)
	var mat_regions: Array = []
	if _is_clone and _clone_mats:
		mat_regions = _mats.regions(MapState.materials)
	# The command owns the payload now; drop the captures.
	_heights.begin(0, 0)
	_mats.begin(0, 0)
	if _stroke_x1 < _stroke_x0 or (height_regions.is_empty() and mat_regions.is_empty()):
		_is_clone = false
		return null
	var w := _stroke_x1 - _stroke_x0 + 1
	var d := _stroke_z1 - _stroke_z0 + 1
	var cmd = HeightStrokeCommandScript.new()
	cmd.tool = mode
	cmd.setup_regions(height_regions)
	# The re-snap is part of the stroke: capture object Ys either side of it so
	# undo puts them back where the pre-stroke terrain had them.
	cmd.snaps_before = _capture_ys()
	MapState.resnap_objects(_stroke_x0, _stroke_z0, w, d)
	cmd.snaps_after = _capture_ys()
	_is_clone = false
	if mat_regions.is_empty():
		return cmd
	var clone_cmd = load("res://project/commands/CloneStrokeCommand.gd").new()
	clone_cmd.setup_height(cmd)
	clone_cmd.setup_material_regions(mat_regions)
	return clone_cmd


func end_paint():
	if not _active or not _is_paint:
		_active = false
		_dab_radius = 0.0
		_dab_amt = -1.0
		return null
	_active = false
	_dab_radius = 0.0
	_dab_amt = -1.0
	_settle_material_edges()
	var regions := _mats.regions(MapState.materials)
	_mats.begin(0, 0)
	if regions.is_empty():
		return null
	var cmd = MaterialStrokeCommandScript.new()
	cmd.setup_regions(regions)
	return cmd


## Tile the painted area, once, now that it is finished.
##
## This is the ONLY pass that reads neighbours during a paint stroke. While the
## button is down the dabs lay solid fills — a paint-area mask in the target
## material — and choose no caps or corners at all. That is deliberate: every
## other auto-terrain system evaluates its whole region in one go, and a
## boundary can only be tiled from curvature the tiler can actually see. A dab
## sees one brush footprint of a shape that is still moving.
##
## `touch` first: this pass writes cells no dab reached, and the undo chunk has
## to hold their pre-stroke value. Chunks already captured keep their first
## copy, so re-touching is free — the whole stroke stays one undo step.
func _settle_material_edges() -> void:
	if not ToolState.paint_match_edges or ToolState.paint_kind != "solid":
		return
	if _stroke_x1 < _stroke_x0 or _stroke_z1 < _stroke_z0:
		return
	var x0 := maxi(0, _stroke_x0 - 1)
	var z0 := maxi(0, _stroke_z0 - 1)
	var x1 := mini(MapState.mat_grid_x - 1, _stroke_x1 + 1)
	var z1 := mini(MapState.mat_grid_z - 1, _stroke_z1 + 1)
	if x1 < x0 or z1 < z0:
		return
	_mats.touch(MapState.materials, x0, z0, x1, z1)
	MapState.rematch_materials_rect(x0, z0, x1 - x0 + 1, z1 - z0 + 1)


func end_mask_paint():
	if not _active or not _is_mask:
		_active = false
		_dab_radius = 0.0
		_dab_amt = -1.0
		_is_mask = false
		return null
	_active = false
	_dab_radius = 0.0
	_dab_amt = -1.0
	_is_mask = false
	if _mask_stem.is_empty():
		return null
	var regions := _masks.regions(MapState.get_mask(_mask_stem))
	_masks.begin(0, 0)
	if regions.is_empty():
		return null
	var cmd = MaskStrokeCommandScript.new()
	cmd.setup_regions(_mask_stem, regions)
	return cmd


func _stamp_mask(cx_m: float, cz_m: float) -> void:
	var field: HeightField = MapState.field
	if field == null or field.grid_x < 1 or _mask_stem.is_empty():
		return
	var mask := MapState.ensure_mask(_mask_stem)
	var cell := HeightField.CELL_M
	var r_cells := int(ceil(_scan_radius() / cell))
	var cx := int(floor(cx_m / cell))
	var cz := int(floor(cz_m / cell))
	var x0 := maxi(0, cx - r_cells)
	var z0 := maxi(0, cz - r_cells)
	var x1 := mini(field.grid_x - 1, cx + r_cells)
	var z1 := mini(field.grid_z - 1, cz + r_cells)
	if x1 < x0 or z1 < z0:
		return
	_expand(x0, z0, x1, z1)
	var gx := field.grid_x
	if mask.size() != gx * field.grid_z:
		return
	_masks.touch(mask, x0, z0, x1, z1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := (float(x) + 0.5) * cell
			var wz := (float(z) + 0.5) * cell
			if _weight(cx_m, cz_m, wx, wz) * _limit_factor_cell(field, x, z) <= 0.0:
				continue
			mask[z * gx + x] = _mask_value
	MapState.upload_mask(_mask_stem)
	last_uploaded = (x1 - x0 + 1) * (z1 - z0 + 1)


func _stamp_paint(cx_m: float, cz_m: float) -> void:
	var tile := 20.0
	var r_tiles := int(ceil(_scan_radius() / tile))
	var cx := int(floor(cx_m / tile))
	var cz := int(floor(cz_m / tile))
	var x0 := maxi(0, cx - r_tiles)
	var z0 := maxi(0, cz - r_tiles)
	var x1 := mini(MapState.mat_grid_x - 1, cx + r_tiles)
	var z1 := mini(MapState.mat_grid_z - 1, cz + r_tiles)
	_expand(x0, z0, x1, z1)
	_mats.touch(MapState.materials, x0, z0, x1, z1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := (float(x) + 0.5) * tile
			var wz := (float(z) + 0.5) * tile
			var w := _weight(cx_m, cz_m, wx, wz) * MapState.selection_factor_world(wx, wz)
			w *= _limit_factor(MapState.field, wx, wz)
			if w <= 0.0:
				continue
			if ToolState.paint_kind == "solid":
				MapState.set_material(x, z, paint_material)
			else:
				MapState.set_material_word(x, z, ToolState.paint_word())
	# With match-edges on, a dab lays down coverage and nothing else. It cannot
	# see past its own footprint, so any cap or corner it chose would be a
	# guess about a shape still being drawn — and the next dab would read that
	# guess back as context. `end_paint` evaluates the finished area in one
	# pass instead, which is the only way the boundary can be tiled from its
	# actual curvature. The solid fills ARE the paint-area mask until then.
	MapState.upload_materials()


func _apply_height(cur: int, w: float, x: int, z: int, field: HeightField) -> int:
	var amt := (_dab_amt if _dab_amt >= 0.0 else _dab_strength()) * w
	match mode:
		"raise":
			return _clamp_write(cur + int(round(80.0 * amt)))
		"lower":
			return _clamp_write(cur - int(round(80.0 * amt)))
		"flatten":
			var tgt := flatten_target if flatten_target >= 0 else cur
			return _clamp_write(int(round(lerpf(float(cur), float(tgt), amt))))
		"smooth":
			var acc := 0
			var n := 0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					acc += field.height_raw(x + dx, z + dz)
					n += 1
			var avg := acc / n
			return _clamp_write(int(round(lerpf(float(cur), float(avg), amt))))
		"noise":
			# Sampled in world metres / scale, so the field is anchored to the
			# map and a second pass over the same ground reinforces it.
			var cell := HeightField.CELL_M
			var sc := maxf(noise_scale, Settings.NOISE_PARAM_MIN)
			var nse := _noise_field().get_noise_2d(
				float(x) * cell / sc, float(z) * cell / sc
			) * noise_contrast
			var amp := noise_amplitude_m / HeightField.HEIGHT_SCALE
			return _clamp_write(cur + int(round(nse * amp * amt)))
		"erode", "dilate":
			var morphed := _morph(field, x, z, mode == "dilate")
			return _clamp_write(int(round(lerpf(float(cur), float(morphed), amt))))
		"setheight":
			var abs_raw := set_height_m / HeightField.HEIGHT_SCALE
			return _clamp_write(int(round(lerpf(float(cur), abs_raw, amt))))
		"setangle":
			var cell2 := HeightField.CELL_M
			var plane := _plane_raw((float(x) + 0.5) * cell2, (float(z) + 0.5) * cell2)
			return _clamp_write(int(round(lerpf(float(cur), plane, amt))))
		"clone":
			var sx := x + _clone_off_x
			var sz := z + _clone_off_z
			if sx < 0 or sz < 0 or sx >= field.grid_x or sz >= field.grid_z:
				return cur
			# Source the pre-stroke grid, so a stamp overlapping its own source
			# does not feed back into itself.
			var src := _heights.value_at(field.heights, sx, sz)
			var tgt := src if clone_match_height else _clone_dst_base + (src - _clone_src_base)
			return _clamp_write(int(round(lerpf(float(cur), float(tgt), amt))))
		_:
			return cur


## Morphological erode (min) / dilate (max) over a disc of `erode_radius_m`.
## The penalty term is what makes it a disc rather than a square: a neighbour
## `d` cells out pays max(d - r, 0) * slack of height before it can win.
##
## Written flat against the prepared window on purpose. Through helper calls
## this ran ~15k function invocations per dab and cost more than every other
## brush put together.
func _morph(field: HeightField, x: int, z: int, dilate: bool) -> int:
	if _morph_w < 1:
		return _pre_raw(field, x, z)
	var rc := _morph_rc
	var lx := clampi(x - _morph_x0, 0, _morph_w - 1)
	var lz := clampi(z - _morph_z0, 0, _morph_h - 1)
	var best := _morph_buf[lz * _morph_w + lx]
	var k := 0
	for dz in range(-rc, rc + 1):
		var row := clampi(lz + dz, 0, _morph_h - 1) * _morph_w
		for dx in range(-rc, rc + 1):
			var h := _morph_buf[row + clampi(lx + dx, 0, _morph_w - 1)]
			if dilate:
				h -= _morph_pen[k]
				if h > best:
					best = h
			else:
				h += _morph_pen[k]
				if h < best:
					best = h
			k += 1
	return best


## Height as it stood before this stroke touched the cell. An area kernel that
## read the live grid would chase its own output across the stamp rect.
func _pre_raw(field: HeightField, x: int, z: int) -> int:
	x = clampi(x, 0, field.grid_x - 1)
	z = clampi(z, 0, field.grid_z - 1)
	if _heights.grid_x != field.grid_x or _heights.grid_z != field.grid_z:
		return field.heights[z * field.grid_x + x]
	return _heights.value_at(field.heights, x, z)


func _begin_plane(field: HeightField, cx_m: float, cz_m: float) -> void:
	var o := angle_origin_m if angle_origin_m.is_finite() else Vector2(cx_m, cz_m)
	_plane_origin = o
	_plane_h_m = field.height_at(o.x, o.y)
	# A bearing, not a maths angle: 0 climbs toward +z (north), 90 toward +x.
	var b := deg_to_rad(angle_dir_deg)
	_plane_dir = Vector2(sin(b), cos(b))


func _plane_raw(x_m: float, z_m: float) -> float:
	var d := (x_m - _plane_origin.x) * _plane_dir.x \
		+ (z_m - _plane_origin.y) * _plane_dir.y
	var h := _plane_h_m + tan(deg_to_rad(clampf(angle_deg, -89.0, 89.0))) * d
	return h / HeightField.HEIGHT_SCALE


func _noise_field() -> FastNoiseLite:
	var key := "%d/%.6f/%.4f/%d" % [
		brush_seed, noise_frequency, noise_scale, noise_octaves
	]
	if _noise != null and _noise_key == key:
		return _noise
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.seed = brush_seed
	# Sample space is world_m / scale. Default frequency 0.02 maps to 1.0 so
	# one cycle matches the scale period; callers that only change frequency
	# still change the field.
	n.frequency = maxf(noise_frequency, 0.00001) / 0.02
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = clampi(noise_octaves, 1, 8)
	_noise = n
	_noise_key = key
	return n


## Stroke dynamics gate: reject a dab that lands closer than the spacing gate
## or sooner than the time gate. Accepting one rolls its tip rotation.
func _accept_dab(x_m: float, z_m: float) -> bool:
	var now := Time.get_ticks_msec()
	var r := radius_m * lerpf(
		1.0, clampf(pressure, 0.0, 1.0), clampf(pressure_size, 0.0, 1.0)
	)
	if _dabs > 0:
		if spacing_ms > 0 and now - _last_dab_ms < spacing_ms:
			return false
		var gate := maxf(spacing_frac, 0.0) * r
		# Epsilon: the shell marches at exactly one gate per step, and a dab
		# that lands on the gate is the one the mapmaker asked for.
		if gate > 0.0 and Vector2(x_m, z_m).distance_to(_last_dab) < gate - 0.0001:
			return false
	_dabs += 1
	_last_dab = Vector2(x_m, z_m)
	_last_dab_ms = now
	_dab_radius = maxf(r, 0.001)
	_dab_amt = _dab_strength()
	_dab_rot = deg_to_rad(rotation_deg)
	if random_rotation:
		_dab_rot += _rng.randf() * TAU
	return true


func _dab_radius_m() -> float:
	return _dab_radius if _dab_radius > 0.0 else radius_m


func _dab_strength() -> float:
	return strength * lerpf(
		1.0, clampf(pressure, 0.0, 1.0), clampf(pressure_opacity, 0.0, 1.0)
	)


## Cell-grid limit gate. Same bands as _limit_factor, sampled off the raw grid
## instead of through the bilinear reader — this runs per cell per dab.
func _limit_factor_cell(field: HeightField, x: int, z: int) -> float:
	if not limit_slope and not limit_height:
		return 1.0
	if field == null or field.grid_x < 2:
		return 1.0
	var f := 1.0
	if limit_slope:
		f = BrushLimits.band(
			BrushLimits.slope_deg_cell(field, x, z),
			slope_min_deg, slope_max_deg, slope_feather_deg
		)
		if f <= 0.0:
			return 0.0
	if limit_height:
		var h := float(field.heights[z * field.grid_x + x]) * HeightField.HEIGHT_SCALE
		f *= BrushLimits.band(h, height_min_m, height_max_m, height_feather_m)
	return f


## Pre-stroke heights for the erode / dilate rect, flattened once per rect,
## together with the penalty for each structuring-element offset. Reading them
## one call at a time through the chunk store cost more than the kernel itself:
## a radius-60 dab is ~15k neighbour lookups, and the penalty is the same 25
## numbers for every one of them.
func _prepare_morph(field: HeightField, x0: int, z0: int, x1: int, z1: int) -> void:
	_morph_w = 0
	if mode != "erode" and mode != "dilate":
		return
	_morph_rc = clampi(int(round(erode_radius_m / HeightField.CELL_M)), 1, 4)
	var rc := _morph_rc
	_morph_x0 = maxi(x0 - rc, 0)
	_morph_z0 = maxi(z0 - rc, 0)
	var mx1 := mini(x1 + rc, field.grid_x - 1)
	var mz1 := mini(z1 + rc, field.grid_z - 1)
	var w := mx1 - _morph_x0 + 1
	var h := mz1 - _morph_z0 + 1
	if w < 1 or h < 1:
		return
	_morph_h = h
	_morph_buf.resize(w * h)
	var i := 0
	for z in range(_morph_z0, mz1 + 1):
		for x in range(_morph_x0, mx1 + 1):
			_morph_buf[i] = _pre_raw(field, x, z)
			i += 1
	var slack := maxf(erode_slack_m, 0.0) / HeightField.HEIGHT_SCALE
	var n := rc * 2 + 1
	_morph_pen.resize(n * n)
	i = 0
	for dz in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var d := sqrt(float(dx * dx + dz * dz))
			_morph_pen[i] = int(round(maxf(d - float(rc), 0.0) * slack))
			i += 1
	# Set last: a half-built window must not look armed.
	_morph_w = w


## Cell rect a dab has to cover. A rotated tip's corners reach r*sqrt(2), so a
## mask brush scans the circumscribed square, not the inscribed one.
func _scan_radius() -> float:
	var r := _dab_radius_m()
	return r * 1.4143 if _mask != null else r


## Slope / height band as a weight multiplier. 1.0 when neither limit is armed,
## so the common case costs one boolean test per cell.
func _limit_factor(field: HeightField, x_m: float, z_m: float) -> float:
	if not limit_slope and not limit_height:
		return 1.0
	if field == null or field.grid_x < 2:
		return 1.0
	var f := 1.0
	if limit_slope:
		f *= BrushLimits.band(
			BrushLimits.slope_deg(field, x_m, z_m),
			slope_min_deg, slope_max_deg, slope_feather_deg
		)
		if f <= 0.0:
			return 0.0
	if limit_height:
		f *= BrushLimits.band(
			field.height_at(x_m, z_m), height_min_m, height_max_m, height_feather_m
		)
	return f


func _stroke_seed() -> int:
	# Rotation must not walk the same sequence as the noise field, but both
	# have to be a pure function of the brush seed (C6).
	return brush_seed * 2654435761


## Pen pressure for the following dabs. Godot delivers it on
## InputEventMouseMotion.pressure; a plain mouse reports 0, which means "no
## pen" rather than "no force", so it reads as full pressure.
func set_pressure(p: float) -> void:
	pressure = clampf(p, 0.0, 1.0) if p > 0.0 else 1.0


## The parameters the shell's brush sync does not carry. Pulled once per stroke
## so a mid-stroke slider drag cannot change the kernel halfway through.
func pull_brush_params() -> void:
	if not follow_tool_state:
		return
	mask_id = ToolState.brush_mask
	rotation_deg = ToolState.brush_rotation_deg
	random_rotation = ToolState.brush_random_rotation
	spacing_frac = ToolState.brush_spacing
	spacing_ms = ToolState.brush_spacing_ms
	pressure_size = ToolState.brush_pressure_size
	pressure_opacity = ToolState.brush_pressure_opacity
	limit_slope = ToolState.limit_slope
	slope_min_deg = ToolState.slope_min_deg
	slope_max_deg = ToolState.slope_max_deg
	slope_feather_deg = ToolState.slope_feather_deg
	limit_height = ToolState.limit_height
	height_min_m = ToolState.height_min_m
	height_max_m = ToolState.height_max_m
	height_feather_m = ToolState.height_feather_m
	noise_frequency = ToolState.noise_frequency
	noise_octaves = ToolState.noise_octaves
	noise_amplitude_m = ToolState.noise_amplitude_m
	noise_scale = ToolState.noise_scale
	noise_contrast = ToolState.noise_contrast
	clone_match_height = ToolState.clone_match_height
	brush_seed = ToolState.brush_seed
	erode_radius_m = ToolState.erode_radius_m
	erode_slack_m = ToolState.erode_slack_m
	set_height_m = ToolState.set_height_m
	angle_deg = ToolState.angle_deg
	angle_dir_deg = ToolState.angle_dir_deg
	angle_origin_m = ToolState.angle_origin_m


## Full mirror of the live brush, for a shell that wants one call instead of
## field-by-field assignment.
func sync_from_tool_state() -> void:
	if not follow_tool_state:
		return
	radius_m = ToolState.radius_m
	strength = ToolState.strength
	falloff = ToolState.falloff
	shape = ToolState.shape
	paint_material = ToolState.paint_material
	mode = ToolState.tool
	pull_brush_params()


func _clamp_write(v: int) -> int:
	if v <= 0:
		return RAW_MIN
	if v > RAW_MAX:
		return RAW_MAX
	return v


func _weight(cx: float, cz: float, x: float, z: float) -> float:
	var r := _dab_radius_m()
	if _mask == null:
		return brush_weight(cx, cz, x, z, r, falloff, shape)
	var dx := x - cx
	var dz := z - cz
	if not is_zero_approx(_dab_rot):
		var c := cos(-_dab_rot)
		var sn := sin(-_dab_rot)
		var rx := dx * c - dz * sn
		dz = dx * sn + dz * c
		dx = rx
	var span := maxf(r * 2.0, 0.001)
	var m := _mask.sample(dx / span + 0.5, dz / span + 0.5)
	if m <= 0.0:
		return 0.0
	# The tip carries the shape; falloff is hardness (high = hard), matching
	# the analytic kernel.
	return pow(m, lerpf(1.0, 0.35, clampf(1.0 - falloff, 0.0, 1.0)))


static func brush_weight(
	cx: float,
	cz: float,
	x: float,
	z: float,
	radius: float,
	fall: float,
	shp: String
) -> float:
	var dx := x - cx
	var dz := z - cz
	var dist: float
	if shp == "square":
		dist = maxf(absf(dx), absf(dz))
	else:
		dist = sqrt(dx * dx + dz * dz)
	if dist > radius:
		return 0.0
	var t := 1.0 - dist / maxf(radius, 0.001)
	# High Falloff is a hard disc; low Falloff is the cosine feather.
	var inv := 1.0 - clampf(fall, 0.0, 1.0)
	if inv <= 0.001:
		return 1.0
	return 0.5 - 0.5 * cos(PI * pow(t, lerpf(1.0, 0.35, inv)))


func _begin_clone(field: HeightField, cx_m: float, cz_m: float) -> void:
	var cell := HeightField.CELL_M
	var dx := int(floor(cx_m / cell))
	var dz := int(floor(cz_m / cell))
	var src := ToolState.clone_source_m
	if not src.is_finite():
		_clone_off_x = 0
		_clone_off_z = 0
		_clone_src_base = field.height_raw(dx, dz)
		_clone_dst_base = _clone_src_base
		return
	var sx := int(floor(src.x / cell))
	var sz := int(floor(src.y / cell))
	_clone_off_x = sx - dx
	_clone_off_z = sz - dz
	_clone_src_base = field.height_raw(sx, sz)
	_clone_dst_base = field.height_raw(dx, dz)


func _stamp_clone_materials(cx_m: float, cz_m: float) -> void:
	if MapState.mat_grid_x < 1:
		return
	var tile := 20.0
	var r_tiles := int(ceil(_scan_radius() / tile))
	var cx := int(floor(cx_m / tile))
	var cz := int(floor(cz_m / tile))
	var x0 := maxi(0, cx - r_tiles)
	var z0 := maxi(0, cz - r_tiles)
	var x1 := mini(MapState.mat_grid_x - 1, cx + r_tiles)
	var z1 := mini(MapState.mat_grid_z - 1, cz + r_tiles)
	if x1 < x0 or z1 < z0:
		return
	var cell := HeightField.CELL_M
	_expand(
		int(floor(float(x0) * tile / cell)),
		int(floor(float(z0) * tile / cell)),
		int(floor(float(x1) * tile / cell)),
		int(floor(float(z1) * tile / cell)),
	)
	_mats.touch(MapState.materials, x0, z0, x1, z1)
	var off_tx := int(round(float(_clone_off_x) * cell / tile))
	var off_tz := int(round(float(_clone_off_z) * cell / tile))
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := (float(x) + 0.5) * tile
			var wz := (float(z) + 0.5) * tile
			var w := _weight(cx_m, cz_m, wx, wz) * MapState.selection_factor_world(wx, wz)
			w *= _limit_factor(MapState.field, wx, wz)
			if w <= 0.0:
				continue
			var sx := x + off_tx
			var sz := z + off_tz
			if sx < 0 or sz < 0 or sx >= MapState.mat_grid_x or sz >= MapState.mat_grid_z:
				continue
			var word := _mats.value_at(MapState.materials, sx, sz)
			MapState.materials[z * MapState.mat_grid_x + x] = word
	MapState.upload_materials()
	MapState.mark_materials_dirty()


func _touch_reset() -> void:
	# One stroke, one RNG state and one empty dab history: replaying the same
	# gesture must land the same bytes (C6).
	_rng.seed = _stroke_seed()
	_dabs = 0
	_last_dab = Vector2.ZERO
	_last_dab_ms = 0
	_dab_radius = 0.0
	_dab_amt = -1.0
	_dab_rot = 0.0
	_stroke_x0 = 1 << 30
	_stroke_z0 = 1 << 30
	_stroke_x1 = -1
	_stroke_z1 = -1


func _expand(x0: int, z0: int, x1: int, z1: int) -> void:
	_stroke_x0 = mini(_stroke_x0, x0)
	_stroke_z0 = mini(_stroke_z0, z0)
	_stroke_x1 = maxi(_stroke_x1, x1)
	_stroke_z1 = maxi(_stroke_z1, z1)


func _capture_ys() -> Array:
	var out: Array = []
	for variant in MapState.objects.keys():
		var recs: Variant = MapState.objects[variant]
		if typeof(recs) != TYPE_ARRAY:
			continue
		for rec in recs:
			if typeof(rec) != TYPE_DICTIONARY:
				continue
			out.append({
				"id": rec.get("id", ""),
				"variant": variant,
				"y": rec.get("y", 0.0),
			})
	return out
