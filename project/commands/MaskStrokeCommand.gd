extends RefCounted
class_name MaskStrokeCommand
## One mask-paint stroke: dirty-rect before/after on a feature's u8 grid.

var stem: String = ""
var x0: int
var z0: int
var width: int
var depth: int
var before: PackedByteArray
var after: PackedByteArray


func describe() -> String:
	if stem.is_empty():
		return "mask stroke"
	return "mask %s" % stem


func setup(
	p_stem: String,
	p_x0: int,
	p_z0: int,
	p_w: int,
	p_d: int,
	p_before: PackedByteArray,
	p_after: PackedByteArray
) -> void:
	stem = p_stem
	x0 = p_x0
	z0 = p_z0
	width = p_w
	depth = p_d
	before = p_before
	after = p_after


func cost_bytes() -> int:
	return before.size() + after.size()


func do() -> void:
	MapState.write_mask_rect(stem, x0, z0, width, depth, after)


func undo() -> void:
	MapState.write_mask_rect(stem, x0, z0, width, depth, before)
