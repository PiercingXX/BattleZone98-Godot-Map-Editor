extends RefCounted
class_name HeightmapImportCommand
## One full-field heightmap import. Heights before/after plus object re-snaps.

var before: PackedInt32Array = PackedInt32Array()
var after: PackedInt32Array = PackedInt32Array()
var snaps_before: Array = []
var snaps_after: Array = []
## Overrides the history entry. A generated field runs through this same
## command, and "import heightmap" is the wrong story for it.
var label: String = ""


func describe() -> String:
	return label if not label.is_empty() else "import heightmap"


func setup(p_before: PackedInt32Array, p_after: PackedInt32Array) -> void:
	before = p_before
	after = p_after


func cost_bytes() -> int:
	return (before.size() + after.size()) * 4


func do() -> void:
	_write(after)
	if snaps_after.is_empty():
		var field: HeightField = MapState.field
		if field != null and field.grid_x > 0 and field.grid_z > 0:
			MapState.resnap_objects(0, 0, field.grid_x, field.grid_z)
		snaps_after = capture_ys()
	else:
		_apply_snaps(snaps_after)
	MapState.mark_terrain_dirty()


func undo() -> void:
	_write(before)
	_apply_snaps(snaps_before)
	MapState.mark_terrain_dirty()


static func capture_ys() -> Array:
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


func _write(values: PackedInt32Array) -> void:
	var field: HeightField = MapState.field
	if field == null or field.grid_x < 1 or field.grid_z < 1:
		return
	field.write_rect(0, 0, field.grid_x, field.grid_z, values)


func _apply_snaps(snaps: Array) -> void:
	for snap in snaps:
		if typeof(snap) != TYPE_DICTIONARY:
			continue
		var rec := MapState.find_object(str(snap.get("id", "")))
		if rec.is_empty():
			continue
		rec["y"] = float(snap.get("y", rec.get("y", 0.0)))
		MapState.touch_object(str(snap.get("variant", "")), str(snap.get("id", "")))
	MapState.objects_changed()
