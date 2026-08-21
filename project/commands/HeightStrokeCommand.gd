extends RefCounted
class_name HeightStrokeCommand
## One sculpt stroke: dirty-rect before/after plus object re-snaps.

var x0: int
var z0: int
var width: int
var depth: int
var before: PackedInt32Array
var after: PackedInt32Array
var snaps_before: Array = []
var snaps_after: Array = []
var uploaded_bytes: int = 0
var tool: String = ""


func describe() -> String:
	if tool.is_empty():
		return "height stroke"
	return "%s stroke" % tool


func setup(p_x0: int, p_z0: int, p_w: int, p_d: int, p_before: PackedInt32Array, p_after: PackedInt32Array) -> void:
	x0 = p_x0
	z0 = p_z0
	width = p_w
	depth = p_d
	before = p_before
	after = p_after
	uploaded_bytes = width * depth * 4


func cost_bytes() -> int:
	return (before.size() + after.size()) * 4


func do() -> void:
	MapState.field.write_rect(x0, z0, width, depth, after)
	_apply_snaps(snaps_after)
	MapState.mark_terrain_dirty()


func undo() -> void:
	MapState.field.write_rect(x0, z0, width, depth, before)
	_apply_snaps(snaps_before)
	MapState.mark_terrain_dirty()


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
