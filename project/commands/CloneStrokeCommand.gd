extends RefCounted
class_name CloneStrokeCommand
## One clone-stamp stroke: height deltas plus optional material words.

var height_cmd: HeightStrokeCommand
var has_materials: bool = false
var mx0: int = 0
var mz0: int = 0
var mw: int = 0
var md: int = 0
var m_before: PackedInt32Array = PackedInt32Array()
var m_after: PackedInt32Array = PackedInt32Array()


func describe() -> String:
	return "clone stroke"


func setup_height(cmd: HeightStrokeCommand) -> void:
	height_cmd = cmd


func setup_materials(
	p_x0: int,
	p_z0: int,
	p_w: int,
	p_d: int,
	p_before: PackedInt32Array,
	p_after: PackedInt32Array
) -> void:
	has_materials = true
	mx0 = p_x0
	mz0 = p_z0
	mw = p_w
	md = p_d
	m_before = p_before
	m_after = p_after


func cost_bytes() -> int:
	var n := 0
	if height_cmd != null and height_cmd.has_method("cost_bytes"):
		n += int(height_cmd.cost_bytes())
	n += (m_before.size() + m_after.size()) * 4
	return maxi(n, 1024)


func do() -> void:
	if height_cmd != null and height_cmd.has_method("do"):
		height_cmd.do()
	if has_materials:
		MapState.write_materials_rect(mx0, mz0, mw, md, m_after)
		MapState.mark_materials_dirty()


func undo() -> void:
	if has_materials:
		MapState.write_materials_rect(mx0, mz0, mw, md, m_before)
		MapState.mark_materials_dirty()
	if height_cmd != null and height_cmd.has_method("undo"):
		height_cmd.undo()
