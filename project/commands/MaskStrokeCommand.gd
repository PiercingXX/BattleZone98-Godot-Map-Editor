extends RefCounted
class_name MaskStrokeCommand
## One mask-paint stroke: chunk before/after regions on a feature's u8 grid.

var stem: String = ""
var regions: Array = []


func describe() -> String:
	if stem.is_empty():
		return "mask stroke"
	return "mask %s" % stem


## Single-rect form, for callers that already hold one dirty rect.
func setup(
	p_stem: String,
	p_x0: int,
	p_z0: int,
	p_w: int,
	p_d: int,
	p_before: PackedByteArray,
	p_after: PackedByteArray
) -> void:
	setup_regions(p_stem, [RasterChunks.region(p_x0, p_z0, p_w, p_d, p_before, p_after)])


func setup_regions(p_stem: String, p_regions: Array) -> void:
	stem = p_stem
	regions = p_regions


func cost_bytes() -> int:
	var n := 0
	for r_v in regions:
		var r: Dictionary = r_v
		var before: PackedByteArray = r["before"]
		var after: PackedByteArray = r["after"]
		n += before.size() + after.size()
	return n


func do() -> void:
	_write("after")


func undo() -> void:
	_write("before")


func _write(key: String) -> void:
	# Unlike heights and materials, mask writes go through MapState: the writer
	# also adopts a legacy feature's mask and marks features dirty, and its
	# flush is one byte per cell.
	for r_v in regions:
		var r: Dictionary = r_v
		var values: PackedByteArray = r[key]
		MapState.write_mask_rect(stem, int(r["x"]), int(r["z"]), int(r["w"]), int(r["d"]), values)
