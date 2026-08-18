extends RefCounted
## Push/undo/redo ordering, already_applied (P1.5), byte-budget eviction (P1.7).


func run(t) -> void:
	var saved_max: int = UndoStack.max_bytes
	UndoStack.clear()

	var log: Array = []
	UndoStack.push(_Cmd.new(log, "a"))
	UndoStack.push(_Cmd.new(log, "b"))
	t.eq(log, ["do:a", "do:b"], "push calls do")
	t.ok(UndoStack.can_undo())
	t.ok(not UndoStack.can_redo())
	UndoStack.undo()
	t.eq(log, ["do:a", "do:b", "undo:b"])
	t.ok(UndoStack.can_redo())
	UndoStack.redo()
	t.eq(log, ["do:a", "do:b", "undo:b", "do:b"])
	UndoStack.undo()
	UndoStack.push(_Cmd.new(log, "c"))
	t.ok(not UndoStack.can_redo(), "push after undo drops redo")
	t.eq(log, ["do:a", "do:b", "undo:b", "do:b", "undo:b", "do:c"])

	# already_applied: do() must not run on push (P1.5). Re-introducing
	# `cmd.do = Callable()` / always-call-do would fail this.
	log.clear()
	UndoStack.clear()
	var stroke := _Cmd.new(log, "stroke")
	UndoStack.push(stroke, true)
	t.eq(log, [], "already_applied skips do")
	UndoStack.undo()
	t.eq(log, ["undo:stroke"])
	UndoStack.redo()
	t.eq(log, ["undo:stroke", "do:stroke"])
	UndoStack.undo()
	t.eq(log, ["undo:stroke", "do:stroke", "undo:stroke"])

	# Budget: evict oldest; never drop the live undo point.
	UndoStack.clear()
	UndoStack.max_bytes = 3000
	log.clear()
	for i in 5:
		UndoStack.push(_Cmd.new(log, str(i), 1024))
	# Each push evicts down to two 1024-byte entries (2048 <= 3000).
	var undos := 0
	while UndoStack.can_undo():
		UndoStack.undo()
		undos += 1
	t.eq(undos, 2, "oldest evicted; two newest remain")
	t.ok(not UndoStack.can_undo())
	t.ok(UndoStack.can_redo())

	UndoStack.clear()
	UndoStack.max_bytes = 100
	UndoStack.push(_Cmd.new(log, "huge", 5000))
	t.ok(UndoStack.can_undo(), "current entry is never evicted")
	UndoStack.undo()
	t.ok(not UndoStack.can_undo())

	UndoStack.clear()
	UndoStack.max_bytes = saved_max

	# Generation / position: push assigns, undo rewinds, bump survives undo.
	UndoStack.clear()
	var g0: int = UndoStack.generation
	t.eq(UndoStack.position, g0, "position aliases generation")
	UndoStack.push(_Cmd.new(log, "gen-a"))
	var g1: int = UndoStack.generation
	t.ok(g1 != g0, "push advances generation")
	UndoStack.push(_Cmd.new(log, "gen-b"))
	var g2: int = UndoStack.generation
	t.ok(g2 != g1, "second push advances again")
	UndoStack.undo()
	t.eq(UndoStack.generation, g1, "undo rewinds to previous generation")
	UndoStack.undo()
	t.eq(UndoStack.generation, g0, "full undo returns to the clear generation")
	UndoStack.redo()
	t.eq(UndoStack.generation, g1, "redo restores the command generation")
	UndoStack.bump()
	var bumped: int = UndoStack.generation
	t.ok(bumped != g1, "bump advances generation")
	UndoStack.undo()
	t.ok(UndoStack.generation != g0, "bump survives undo back through the stack")
	UndoStack.clear()
	t.eq(UndoStack.generation, 0, "clear resets generation")


class _Cmd:
	extends RefCounted
	var log: Array
	var tag: String
	var bytes: int

	func _init(p_log: Array, p_tag: String, p_bytes: int = 1024) -> void:
		log = p_log
		tag = p_tag
		bytes = p_bytes

	func do() -> void:
		log.append("do:%s" % tag)

	func undo() -> void:
		log.append("undo:%s" % tag)

	func cost_bytes() -> int:
		return bytes
