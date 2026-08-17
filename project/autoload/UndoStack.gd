extends Node
## Command stack. Evicts oldest entries when the byte budget is exceeded.

signal changed()

var _stack: Array = []
var _index: int = -1
var _bytes: int = 0
var max_bytes: int = 512 * 1024 * 1024


func can_undo() -> bool:
	return _index >= 0


func can_redo() -> bool:
	return _index + 1 < _stack.size()


func push(command: RefCounted, already_applied: bool = false) -> void:
	if _index + 1 < _stack.size():
		for i in range(_index + 1, _stack.size()):
			_bytes -= _cost(_stack[i])
		_stack = _stack.slice(0, _index + 1)
	_stack.append(command)
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
	_index = -1
	_bytes = 0
	changed.emit()


func _evict() -> void:
	# Drop the oldest end until we are under budget. Never evict the entry
	# at or after the current index (that would drop the live undo point
	# or the redo tail).
	while _bytes > max_bytes and _index > 0:
		_bytes -= _cost(_stack[0])
		_stack.remove_at(0)
		_index -= 1


func _cost(command: RefCounted) -> int:
	if command != null and command.has_method("cost_bytes"):
		return int(command.call("cost_bytes"))
	return 1024
