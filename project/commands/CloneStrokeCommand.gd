extends RefCounted
class_name CloneStrokeCommand
## One clone-stamp stroke: height regions plus optional material regions.

var height_cmd: HeightStrokeCommand
var material_cmd: MaterialStrokeCommand


func describe() -> String:
	return "clone stroke"


func setup_height(cmd: HeightStrokeCommand) -> void:
	height_cmd = cmd


## Single-rect form, for callers that already hold one dirty rect.
func setup_materials(
	p_x0: int, p_z0: int, p_w: int, p_d: int, p_before: PackedInt32Array, p_after: PackedInt32Array
) -> void:
	setup_material_regions([RasterChunks.region(p_x0, p_z0, p_w, p_d, p_before, p_after)])


func setup_material_regions(p_regions: Array) -> void:
	material_cmd = MaterialStrokeCommand.new()
	material_cmd.tool = "clone"
	material_cmd.setup_regions(p_regions)


func cost_bytes() -> int:
	var n := 0
	if height_cmd != null:
		n += height_cmd.cost_bytes()
	if material_cmd != null:
		n += material_cmd.cost_bytes()
	return maxi(n, 1024)


func do() -> void:
	if height_cmd != null:
		height_cmd.do()
	if material_cmd != null:
		material_cmd.do()


func undo() -> void:
	if material_cmd != null:
		material_cmd.undo()
	if height_cmd != null:
		height_cmd.undo()
