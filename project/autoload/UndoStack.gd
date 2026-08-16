extends Node
## Command stack. Sculpt/object commands land in Phase 3; the API is here now.

signal changed()

var _stack: Array = []
var _index: int = -1
var max_bytes: int = 512 * 1024 * 1024


func can_undo() -> bool:
	return _index >= 0


func can_redo() -> bool:
	return _index + 1 < _stack.size()


func push(command: RefCounted) -> void:
	if _index + 1 < _stack.size():
		_stack = _stack.slice(0, _index + 1)
	_stack.append(command)
	_index = _stack.size() - 1
	if command.has_method("do"):
		command.call("do")
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
	_index = -1
	changed.emit()
