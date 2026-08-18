extends RefCounted
## MapState.unsaved is derived from UndoStack generation vs last open/save.


func run(t) -> void:
	var saved_session := MapState.has_session
	UndoStack.clear()
	MapState.has_session = true
	MapState.mark_saved()
	t.ok(not MapState.unsaved, "open/saved generation is clean")
	t.eq(UndoStack.position, UndoStack.generation)

	UndoStack.push(_Nop.new())
	t.ok(MapState.unsaved, "edit dirties")
	var dirty_gen: int = UndoStack.generation
	UndoStack.undo()
	t.ok(not MapState.unsaved, "undo back to open is clean")
	t.ok(UndoStack.generation != dirty_gen)
	UndoStack.redo()
	t.ok(MapState.unsaved, "redo dirties again")
	t.eq(UndoStack.generation, dirty_gen)

	MapState.mark_saved()
	t.ok(not MapState.unsaved, "save snapshots generation")
	UndoStack.undo()
	t.ok(MapState.unsaved, "undo past the save point is dirty")
	UndoStack.redo()
	t.ok(not MapState.unsaved, "redo back to the save point is clean")

	UndoStack.bump()
	t.ok(MapState.unsaved, "non-undoable bump dirties")
	UndoStack.undo()
	UndoStack.undo()
	t.ok(MapState.unsaved, "bump survives a full undo")
	MapState.mark_saved()
	t.ok(not MapState.unsaved, "save after a bump is clean")

	MapState.note_unsaved()
	t.ok(MapState.unsaved, "note_unsaved bumps when clean")
	MapState.note_unsaved()
	var after_note: int = UndoStack.generation
	MapState.note_unsaved()
	t.eq(UndoStack.generation, after_note, "note_unsaved is idempotent while already dirty")

	MapState.unsaved = false
	t.ok(not MapState.unsaved, "assigning unsaved=false snapshots")
	MapState.unsaved = true
	t.ok(MapState.unsaved, "assigning unsaved=true bumps")

	MapState.has_session = false
	t.ok(not MapState.unsaved, "no session is not unsaved")

	UndoStack.clear()
	MapState.has_session = saved_session
	if saved_session:
		MapState.mark_saved()


class _Nop:
	extends RefCounted
	func do() -> void:
		pass
	func undo() -> void:
		pass
