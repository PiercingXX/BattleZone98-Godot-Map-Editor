extends RefCounted
class_name HeightStrokeCommand
## One sculpt stroke: chunk before/after regions plus object re-snaps.
##
## Regions come from RasterChunks — the 64x64 chunks the stroke actually wrote,
## not its bounding rect — so the record costs edited area, not map area.

var regions: Array = []
var snaps_before: Array = []
var snaps_after: Array = []
var uploaded_bytes: int = 0
var tool: String = ""


func describe() -> String:
	if tool.is_empty():
		return "height stroke"
	return "%s stroke" % tool


## Single-rect form, for callers that already hold one dirty rect.
func setup(
	p_x0: int, p_z0: int, p_w: int, p_d: int, p_before: PackedInt32Array, p_after: PackedInt32Array
) -> void:
	setup_regions([RasterChunks.region(p_x0, p_z0, p_w, p_d, p_before, p_after)])


func setup_regions(p_regions: Array) -> void:
	regions = p_regions
	uploaded_bytes = 0
	for r_v in regions:
		var r: Dictionary = r_v
		uploaded_bytes += int(r["w"]) * int(r["d"]) * 4


func cost_bytes() -> int:
	var n := 0
	for r_v in regions:
		var r: Dictionary = r_v
		var before: PackedInt32Array = r["before"]
		var after: PackedInt32Array = r["after"]
		n += (before.size() + after.size()) * 4
	return n


func do() -> void:
	_write("after")
	_apply_snaps(snaps_after)
	MapState.mark_terrain_dirty()


func undo() -> void:
	_write("before")
	_apply_snaps(snaps_before)
	MapState.mark_terrain_dirty()


func _write(key: String) -> void:
	# Cells go into the live array with one deferred upload per region and a
	# single flush at the end: HeightField.write_rect() flushes the whole
	# texture per call, and a chunked stroke is many small rects. Words are
	# restored verbatim — [flags:3][height:13], no clamp, no re-encode.
	var field: HeightField = MapState.field
	if field == null or field.grid_x < 1 or field.grid_z < 1:
		return
	var gx := field.grid_x
	var gz := field.grid_z
	for r_v in regions:
		var r: Dictionary = r_v
		var x0 := int(r["x"])
		var z0 := int(r["z"])
		var w := int(r["w"])
		var d := int(r["d"])
		var values: PackedInt32Array = r[key]
		var i := 0
		for z in range(z0, z0 + d):
			if z < 0 or z >= gz:
				i += w
				continue
			for x in range(x0, x0 + w):
				if x >= 0 and x < gx and i < values.size():
					field.heights[z * gx + x] = values[i]
				i += 1
		field.upload_rect(x0, z0, w, d)
	field.flush_upload()


func _apply_snaps(snaps: Array) -> void:
	for snap in snaps:
		if typeof(snap) != TYPE_DICTIONARY:
			continue
		var rec := MapState.find_object(str(snap.get("id", "")))
		if rec.is_empty():
			continue
		rec["y"] = float(snap.get("y", rec.get("y", 0.0)))
		MapState.touch_object(str(snap.get("variant", "")), str(snap.get("id", "")))
	MapState.object_poses_changed.emit()
