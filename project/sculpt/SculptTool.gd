extends RefCounted
class_name SculptTool
## Brush kernels over the height / material grids.

const HeightStrokeCommandScript = preload("res://project/commands/HeightStrokeCommand.gd")
const MaterialStrokeCommandScript = preload("res://project/commands/MaterialStrokeCommand.gd")

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
var _active: bool = false
var _is_paint: bool = false


func begin_stroke(field: HeightField, cx_m: float, cz_m: float, paint: bool) -> void:
	_active = true
	_is_paint = paint
	_touch_reset()
	if paint:
		_stroke_snapshot = MapState.materials.duplicate()
	else:
		_stroke_snapshot = field.heights.duplicate()
	flatten_target = field.height_raw(int(cx_m / HeightField.CELL_M), int(cz_m / HeightField.CELL_M))
	stamp(field, cx_m, cz_m)


func stamp(field: HeightField, cx_m: float, cz_m: float) -> void:
	if not _active or field == null or field.grid_x < 2:
		return
	if _is_paint:
		_stamp_paint(cx_m, cz_m)
		return
	var cell := HeightField.CELL_M
	var r_cells := int(ceil(radius_m / cell))
	var cx := int(floor(cx_m / cell))
	var cz := int(floor(cz_m / cell))
	var x0 := maxi(0, cx - r_cells)
	var z0 := maxi(0, cz - r_cells)
	var x1 := mini(field.grid_x - 1, cx + r_cells)
	var z1 := mini(field.grid_z - 1, cz + r_cells)
	_expand(x0, z0, x1, z1)
	var hit_ceiling := false
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := (float(x) + 0.5) * cell
			var wz := (float(z) + 0.5) * cell
			var w := _weight(cx_m, cz_m, wx, wz)
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
	if not _active or _is_paint:
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
			if _weight(cx_m, cz_m, wx, wz) <= 0.0:
				continue
			MapState.set_material(x, z, paint_material)
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
		_:
			return cur


func _clamp_write(v: int) -> int:
	if v <= 0:
		return RAW_MIN
	if v > RAW_MAX:
		return RAW_MAX
	return v


func _weight(cx: float, cz: float, x: float, z: float) -> float:
	var dx := x - cx
	var dz := z - cz
	var dist: float
	if shape == "square":
		dist = maxf(absf(dx), absf(dz))
	else:
		dist = sqrt(dx * dx + dz * dz)
	if dist > radius_m:
		return 0.0
	var t := 1.0 - dist / maxf(radius_m, 0.001)
	if falloff <= 0.001:
		return 1.0
	return 0.5 - 0.5 * cos(PI * pow(t, lerpf(1.0, 0.35, falloff)))


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
