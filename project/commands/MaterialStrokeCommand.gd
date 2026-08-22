extends RefCounted
class_name MaterialStrokeCommand
## One paint stroke: chunk before/after regions of material words.

var regions: Array = []
var tool: String = ""


func describe() -> String:
	if tool == "match":
		return "match corners"
	if tool.is_empty():
		return "paint stroke"
	return "%s stroke" % tool


## Single-rect form, for callers that already hold one dirty rect.
func setup(
	p_x0: int, p_z0: int, p_w: int, p_d: int, p_before: PackedInt32Array, p_after: PackedInt32Array
) -> void:
	setup_regions([RasterChunks.region(p_x0, p_z0, p_w, p_d, p_before, p_after)])


func setup_regions(p_regions: Array) -> void:
	regions = p_regions


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


func undo() -> void:
	_write("before")


func _write(key: String) -> void:
	# Straight into the live grid, then one upload: write_materials_rect()
	# rebuilds the whole tile texture per call and a stroke is many regions.
	if MapState.mat_grid_x < 1 or MapState.mat_grid_z < 1:
		return
	var gx := MapState.mat_grid_x
	var gz := MapState.mat_grid_z
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
					MapState.materials[z * gx + x] = values[i]
				i += 1
	MapState.upload_materials()
	MapState.flush_materials()
	MapState.mark_materials_dirty()
