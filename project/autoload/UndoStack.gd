extends Node
## Command stack. Evicts oldest entries when the byte budget is exceeded.
##
## `generation` / `position` identify the current undo point. Each push
## assigns a new id; undo rewinds to the previous id. `bump()` marks a
## non-undoable dirty so a full undo is still unsaved.

signal changed()

var _stack: Array = []
var _gens: Array = []
var _index: int = -1
var _bytes: int = 0
var _assigned: int = 0
var _floor: int = 0
var _sideline: int = 0
var max_bytes: int = 512 * 1024 * 1024

## Current undo-point id. MapState records this at open/save.
var generation: int:
	get:
		return _current_generation()

## Alias of `generation` (same undo-point id).
var position: int:
	get:
		return _current_generation()


func can_undo() -> bool:
	return _index >= 0


func can_redo() -> bool:
	return _index + 1 < _stack.size()


func command_count() -> int:
	return _stack.size()


func current_index() -> int:
	return _index


func command_at(i: int) -> RefCounted:
	if i < 0 or i >= _stack.size():
		return null
	return _stack[i]


func describe_command(command: RefCounted) -> String:
	if command == null:
		return ""
	if command.has_method("describe"):
		var label := str(command.call("describe")).strip_edges()
		if not label.is_empty():
			return label
	return command.get_class()


func jump_to(index: int) -> void:
	var target := clampi(index, -1, _stack.size() - 1)
	if target == _index:
		return
	while _index > target and can_undo():
		undo()
	while _index < target and can_redo():
		redo()


func push(command: RefCounted, already_applied: bool = false) -> void:
	_stamp_height_tool(command)
	if _index + 1 < _stack.size():
		for i in range(_index + 1, _stack.size()):
			_bytes -= _cost(_stack[i])
		_stack = _stack.slice(0, _index + 1)
		_gens = _gens.slice(0, _index + 1)
	_stack.append(command)
	_assigned += 1
	_gens.append(_assigned)
	_index = _stack.size() - 1
	_bytes += _cost(command)
	if not already_applied and command.has_method("do"):
		command.call("do")
	_evict()
	changed.emit()


func undo() -> void:
	if not can_undo():
		return
	var command: RefCounted = _stack[_index]
	if command.has_method("undo"):
		command.call("undo")
	_index -= 1
	changed.emit()


func redo() -> void:
	if not can_redo():
		return
	_index += 1
	var command: RefCounted = _stack[_index]
	if command.has_method("do"):
		command.call("do")
	changed.emit()


func clear() -> void:
	_stack.clear()
	_gens.clear()
	_index = -1
	_bytes = 0
	_assigned = 0
	_floor = 0
	_sideline = 0
	changed.emit()


## Non-undoable session dirty (meta / stem / anything that bypasses the stack).
func bump() -> void:
	_sideline += 1
	changed.emit()


func _current_generation() -> int:
	var cmd_gen: int = _floor
	if _index >= 0:
		cmd_gen = int(_gens[_index])
	# Sideline in the high half so a bump cannot collide with a command id.
	return (_sideline << 32) | (cmd_gen & 0xFFFFFFFF)


func _evict() -> void:
	# Drop the oldest end until we are under budget. Never evict the entry
	# at or after the current index (that would drop the live undo point
	# or the redo tail). The evicted id becomes the full-undo floor so
	# we cannot look "saved" after dropping the path back to open.
	while _bytes > max_bytes and _index > 0:
		_bytes -= _cost(_stack[0])
		_floor = int(_gens[0])
		_stack.remove_at(0)
		_gens.remove_at(0)
		_index -= 1


func _stamp_height_tool(command: RefCounted) -> void:
	if not (command is HeightStrokeCommand):
		return
	var hs := command as HeightStrokeCommand
	if not hs.tool.is_empty():
		return
	var mode := str(ToolState.tool)
	if mode in ["raise", "lower", "flatten", "smooth", "ramp", "noise"]:
		hs.tool = mode


func _cost(command: RefCounted) -> int:
	if command != null and command.has_method("cost_bytes"):
		return int(command.call("cost_bytes"))
	return 1024
