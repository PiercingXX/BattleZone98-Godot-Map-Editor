extends RefCounted
class_name AiPathCommand
## One undo step for an AI-path edit (add/delete path or point, move point).


enum Kind { ADD_PATH, DELETE_PATH, ADD_POINT, DELETE_POINT, MOVE_POINT }

var kind: int = Kind.MOVE_POINT
var variant: String = ""
var before_paths: Array = []
var after_paths: Array = []
var path_index: int = -1
var point_index: int = -1


func describe() -> String:
	match kind:
		Kind.ADD_PATH:
			return "add AI path"
		Kind.DELETE_PATH:
			return "delete AI path"
		Kind.ADD_POINT:
			return "add AI path point"
		Kind.DELETE_POINT:
			return "delete AI path point"
		Kind.MOVE_POINT:
			return "move AI path point"
	return get_class()


func cost_bytes() -> int:
	return 1024 + before_paths.size() * 128 + after_paths.size() * 128


func do() -> void:
	MapState.replace_variant_paths(variant, after_paths)
	_restore_selection(after_paths)


func undo() -> void:
	MapState.replace_variant_paths(variant, before_paths)
	_restore_selection(before_paths)


func _restore_selection(recs: Array) -> void:
	if path_index < 0 or path_index >= recs.size():
		MapState.clear_aipath_selection()
		return
	var pt := point_index
	if typeof(recs[path_index]) == TYPE_DICTIONARY:
		var pts: Variant = (recs[path_index] as Dictionary).get("points", [])
		if typeof(pts) == TYPE_ARRAY and pt >= (pts as Array).size():
			pt = (pts as Array).size() - 1
	MapState.select_aipath(path_index, pt)


static func snapshot_and_apply(
	p_kind: int, variant: String, before: Array, after: Array, path_i: int = -1, point_i: int = -1
) -> AiPathCommand:
	var cmd := AiPathCommand.new()
	cmd.kind = p_kind
	cmd.variant = variant
	cmd.before_paths = _dup(before)
	cmd.after_paths = _dup(after)
	cmd.path_index = path_i
	cmd.point_index = point_i
	return cmd


static func _dup(recs: Array) -> Array:
	var out: Array = []
	for rec_v in recs:
		if typeof(rec_v) == TYPE_DICTIONARY:
			out.append((rec_v as Dictionary).duplicate(true))
		else:
			out.append(rec_v)
	return out
