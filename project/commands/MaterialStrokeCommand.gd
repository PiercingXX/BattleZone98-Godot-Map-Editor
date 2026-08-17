extends RefCounted
class_name MaterialStrokeCommand

var x0: int
var z0: int
var width: int
var depth: int
var before: PackedInt32Array
var after: PackedInt32Array


func setup(p_x0: int, p_z0: int, p_w: int, p_d: int, p_before: PackedInt32Array, p_after: PackedInt32Array) -> void:
	x0 = p_x0
	z0 = p_z0
	width = p_w
	depth = p_d
	before = p_before
	after = p_after


func cost_bytes() -> int:
	return (before.size() + after.size()) * 4


func do() -> void:
	MapState.write_materials_rect(x0, z0, width, depth, after)
	MapState.mark_materials_dirty()


func undo() -> void:
	MapState.write_materials_rect(x0, z0, width, depth, before)
	MapState.mark_materials_dirty()
