extends RefCounted
class_name SculptTool
## Brush kernels over the height / material grids.

const HeightStrokeCommandScript = preload("res://project/commands/HeightStrokeCommand.gd")
const MaterialStrokeCommandScript = preload("res://project/commands/MaterialStrokeCommand.gd")
const MaskStrokeCommandScript = preload("res://project/commands/MaskStrokeCommand.gd")

const RAW_MIN := 1
const RAW_MAX := 4095

var mode: String = "raise" # raise, lower, flatten, smooth, ramp, noise, paint
var shape: String = "circle"
var radius_m: float = 40.0
var falloff: float = 0.65
var strength: float = 0.45
var flatten_target: int = -1
var paint_material: int = 0
var last_uploaded: int = 0

var _stroke_x0: int = 0
var _stroke_z0: int = 0
var _stroke_x1: int = 0
var _stroke_z1: int = 0
var _stroke_before: PackedInt32Array = PackedInt32Array()
var _stroke_snapshot: PackedInt32Array = PackedInt32Array()
var _mask_snapshot: PackedByteArray = PackedByteArray()
var _mat_snapshot: PackedInt32Array = PackedInt32Array()
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


func begin_stroke(field: HeightField, cx_m: float, cz_m: float, paint: bool) -> void:
	_active = true
	_is_paint = paint
	_is_mask = false
	_is_clone = mode == "clone"
	_clone_mats = _is_clone and ToolState.clone_materials
	_mask_stem = ""
	_touch_reset()
	if paint:
		_stroke_snapshot = MapState.materials.duplicate()
		_mat_snapshot = PackedInt32Array()
	else:
		_stroke_snapshot = field.heights.duplicate()
		if _clone_mats:
			_mat_snapshot = MapState.materials.duplicate()
		else:
			_mat_snapshot = PackedInt32Array()
	flatten_target = field.height_raw(int(cx_m / HeightField.CELL_M), int(cz_m / HeightField.CELL_M))
	if _is_clone:
		_begin_clone(field, cx_m, cz_m)
	stamp(field, cx_m, cz_m)


func begin_mask_stroke(field: HeightField, cx_m: float, cz_m: float, stem: String, value: int) -> void:
	_active = true
	_is_paint = false
	_is_mask = true
	_mask_stem = stem
	_mask_value = value & 0xFF
	_touch_reset()
	_mask_snapshot = MapState.ensure_mask(stem).duplicate()
	stamp(field, cx_m, cz_m)


func stamp(field: HeightField, cx_m: float, cz_m: float) -> void:
	if not _active or field == null:
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
	var r_cells := int(ceil(radius_m / cell))
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
	if rects.is_empty():
		return
	var seen: Dictionary = {}
	var hit_ceiling := false
	var uploaded := 0
	for r in rects:
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
				w *= MapState.selection_factor(x, z)
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
	var r_cells := int(ceil(radius_m / cell))
	var cx := int(floor(cx_m / cell))
	var cz := int(floor(cz_m / cell))
	var x0 := maxi(0, cx - r_cells)
	var z0 := maxi(0, cz - r_cells)
	var x1 := mini(field.grid_x - 1, cx + r_cells)
	var z1 := mini(field.grid_z - 1, cz + r_cells)
	if x1 < x0 or z1 < z0:
		return
	_expand(x0, z0, x1, z1)
	var hit_ceiling := false
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := (float(x) + 0.5) * cell
			var wz := (float(z) + 0.5) * cell
			var w := _weight(cx_m, cz_m, wx, wz) * MapState.selection_factor(x, z)
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
		_is_clone = false
		return null
	_active = false
	if _stroke_x1 < _stroke_x0:
		_is_clone = false
		return null
	var w := _stroke_x1 - _stroke_x0 + 1
	var d := _stroke_z1 - _stroke_z0 + 1
	var before := PackedInt32Array()
	var after := PackedInt32Array()
	before.resize(w * d)
	after.resize(w * d)
	var i := 0
	for z in range(_stroke_z0, _stroke_z1 + 1):
		for x in range(_stroke_x0, _stroke_x1 + 1):
			var idx := z * field.grid_x + x
			before[i] = _stroke_snapshot[idx]
			after[i] = field.heights[idx]
			i += 1
	var cmd = HeightStrokeCommandScript.new()
	cmd.setup(_stroke_x0, _stroke_z0, w, d, before, after)
	cmd.snaps_before = _capture_ys()
	MapState.resnap_objects(_stroke_x0, _stroke_z0, w, d)
	cmd.snaps_after = _capture_ys()
	if _is_clone and _clone_mats and not _mat_snapshot.is_empty():
		var clone_cmd = load("res://project/commands/CloneStrokeCommand.gd").new()
		var mb := PackedInt32Array()
		var ma := PackedInt32Array()
		var tile := 20.0
		var mx0 := maxi(0, int(floor(float(_stroke_x0) * HeightField.CELL_M / tile)))
		var mz0 := maxi(0, int(floor(float(_stroke_z0) * HeightField.CELL_M / tile)))
		var mx1 := mini(MapState.mat_grid_x - 1, int(floor(float(_stroke_x1) * HeightField.CELL_M / tile)))
		var mz1 := mini(MapState.mat_grid_z - 1, int(floor(float(_stroke_z1) * HeightField.CELL_M / tile)))
		var mw := mx1 - mx0 + 1
		var md := mz1 - mz0 + 1
		if mw > 0 and md > 0 and MapState.mat_grid_x > 0:
			mb.resize(mw * md)
			ma.resize(mw * md)
			var mi := 0
			var gx := MapState.mat_grid_x
			for z in range(mz0, mz1 + 1):
				for x in range(mx0, mx1 + 1):
					var midx := z * gx + x
					mb[mi] = _mat_snapshot[midx]
					ma[mi] = MapState.materials[midx]
					mi += 1
			clone_cmd.setup_height(cmd)
			clone_cmd.setup_materials(mx0, mz0, mw, md, mb, ma)
			_is_clone = false
			return clone_cmd
	_is_clone = false
	return cmd


func end_paint():
	if not _active or not _is_paint:
		_active = false
		return null
	_active = false
	if _stroke_x1 < _stroke_x0:
		return null
	var w := _stroke_x1 - _stroke_x0 + 1
	var d := _stroke_z1 - _stroke_z0 + 1
	var before := PackedInt32Array()
	var after := PackedInt32Array()
	before.resize(w * d)
	after.resize(w * d)
	var gx := MapState.mat_grid_x
	var i := 0
	for z in range(_stroke_z0, _stroke_z1 + 1):
		for x in range(_stroke_x0, _stroke_x1 + 1):
			var idx := z * gx + x
			before[i] = _stroke_snapshot[idx]
			after[i] = MapState.materials[idx]
			i += 1
	var cmd = MaterialStrokeCommandScript.new()
	cmd.setup(_stroke_x0, _stroke_z0, w, d, before, after)
	return cmd


func end_mask_paint():
	if not _active or not _is_mask:
		_active = false
		_is_mask = false
		return null
	_active = false
	_is_mask = false
	if _stroke_x1 < _stroke_x0 or _mask_stem.is_empty():
		return null
	var w := _stroke_x1 - _stroke_x0 + 1
	var d := _stroke_z1 - _stroke_z0 + 1
	var before := PackedByteArray()
	var after := PackedByteArray()
	before.resize(w * d)
	after.resize(w * d)
	var gx := MapState.field.grid_x if MapState.field != null else 0
	var live := MapState.get_mask(_mask_stem)
	if gx < 1 or live.is_empty() or _mask_snapshot.size() != live.size():
		return null
	var i := 0
	for z in range(_stroke_z0, _stroke_z1 + 1):
		for x in range(_stroke_x0, _stroke_x1 + 1):
			var idx := z * gx + x
			before[i] = _mask_snapshot[idx]
			after[i] = live[idx]
			i += 1
	var cmd = MaskStrokeCommandScript.new()
	cmd.setup(_mask_stem, _stroke_x0, _stroke_z0, w, d, before, after)
	return cmd


func _stamp_mask(cx_m: float, cz_m: float) -> void:
	var field: HeightField = MapState.field
	if field == null or field.grid_x < 1 or _mask_stem.is_empty():
		return
	var mask := MapState.ensure_mask(_mask_stem)
	var cell := HeightField.CELL_M
	var r_cells := int(ceil(radius_m / cell))
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
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := (float(x) + 0.5) * cell
			var wz := (float(z) + 0.5) * cell
			if _weight(cx_m, cz_m, wx, wz) <= 0.0:
				continue
			mask[z * gx + x] = _mask_value
	MapState.upload_mask(_mask_stem)
	last_uploaded = (x1 - x0 + 1) * (z1 - z0 + 1)


func _stamp_paint(cx_m: float, cz_m: float) -> void:
	var tile := 20.0
	var r_tiles := int(ceil(radius_m / tile))
	var cx := int(floor(cx_m / tile))
	var cz := int(floor(cz_m / tile))
	var x0 := maxi(0, cx - r_tiles)
	var z0 := maxi(0, cz - r_tiles)
	var x1 := mini(MapState.mat_grid_x - 1, cx + r_tiles)
	var z1 := mini(MapState.mat_grid_z - 1, cz + r_tiles)
	_expand(x0, z0, x1, z1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := (float(x) + 0.5) * tile
			var wz := (float(z) + 0.5) * tile
			var w := _weight(cx_m, cz_m, wx, wz) * MapState.selection_factor_world(wx, wz)
			if w <= 0.0:
				continue
			MapState.set_material(x, z, paint_material)
	if ToolState.paint_match_edges:
		var mx0 := maxi(0, x0 - 1)
		var mz0 := maxi(0, z0 - 1)
		var mx1 := mini(MapState.mat_grid_x - 1, x1 + 1)
		var mz1 := mini(MapState.mat_grid_z - 1, z1 + 1)
		_expand(mx0, mz0, mx1, mz1)
		MapState.rematch_materials_rect(mx0, mz0, mx1 - mx0 + 1, mz1 - mz0 + 1)
	MapState.upload_materials()


func _apply_height(cur: int, w: float, x: int, z: int, field: HeightField) -> int:
	match mode:
		"raise":
			return _clamp_write(cur + int(round(80.0 * strength * w)))
		"lower":
			return _clamp_write(cur - int(round(80.0 * strength * w)))
		"flatten":
			var tgt := flatten_target if flatten_target >= 0 else cur
			return _clamp_write(int(round(lerpf(float(cur), float(tgt), strength * w))))
		"smooth":
			var acc := 0
			var n := 0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					acc += field.height_raw(x + dx, z + dz)
					n += 1
			var avg := acc / n
			return _clamp_write(int(round(lerpf(float(cur), float(avg), strength * w))))
		"noise":
			var nse := (sin(float(x) * 0.35 + float(z) * 0.21) + sin(float(x) * 0.11 - float(z) * 0.17)) * 0.5
			return _clamp_write(cur + int(round(nse * 60.0 * strength * w)))
		"clone":
			var sx := x + _clone_off_x
			var sz := z + _clone_off_z
			if sx < 0 or sz < 0 or sx >= field.grid_x or sz >= field.grid_z:
				return cur
			var src := field.height_raw(sx, sz)
			if _stroke_snapshot.size() == field.heights.size():
				src = _stroke_snapshot[sz * field.grid_x + sx]
			var tgt := _clone_dst_base + (src - _clone_src_base)
			return _clamp_write(int(round(lerpf(float(cur), float(tgt), strength * w))))
		_:
			return cur


func _clamp_write(v: int) -> int:
	if v <= 0:
		return RAW_MIN
	if v > RAW_MAX:
		return RAW_MAX
	return v


func _weight(cx: float, cz: float, x: float, z: float) -> float:
	return brush_weight(cx, cz, x, z, radius_m, falloff, shape)


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
	if fall <= 0.001:
		return 1.0
	return 0.5 - 0.5 * cos(PI * pow(t, lerpf(1.0, 0.35, fall)))


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
	var r_tiles := int(ceil(radius_m / tile))
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
	var off_tx := int(round(float(_clone_off_x) * cell / tile))
	var off_tz := int(round(float(_clone_off_z) * cell / tile))
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := (float(x) + 0.5) * tile
			var wz := (float(z) + 0.5) * tile
			var w := _weight(cx_m, cz_m, wx, wz) * MapState.selection_factor_world(wx, wz)
			if w <= 0.0:
				continue
			var sx := x + off_tx
			var sz := z + off_tz
			if sx < 0 or sz < 0 or sx >= MapState.mat_grid_x or sz >= MapState.mat_grid_z:
				continue
			var word: int
			if _mat_snapshot.size() == MapState.materials.size():
				word = _mat_snapshot[sz * MapState.mat_grid_x + sx]
			else:
				word = MapState.materials[sz * MapState.mat_grid_x + sx]
			MapState.materials[z * MapState.mat_grid_x + x] = word
	MapState.upload_materials()
	MapState.mark_materials_dirty()


func _touch_reset() -> void:
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
