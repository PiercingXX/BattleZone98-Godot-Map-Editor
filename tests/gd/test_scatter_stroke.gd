extends RefCounted
## ScatterStrokeCommand: chunked capture, exact undo, no empty history entries.


func run(t) -> void:
	_round_trip(t)
	_overpaint(t)
	_empty_stroke(t)
	_labels(t)


func _make(gx: int, gz: int) -> ScatterField:
	var sf := ScatterField.new()
	sf.resize(gx, gz)
	sf.set_species([ScatterSpecies.make("grass", 10.0), ScatterSpecies.make("rock", 20.0)])
	return sf


func _round_trip(t) -> void:
	var sf := _make(96, 96)
	var before: PackedByteArray = sf.mask.values.duplicate()
	var cmd := ScatterStrokeCommand.begin(sf, 0)
	var cell: float = HeightField.CELL_M
	cmd.stamp(20.0 * cell, 20.0 * cell, 6.0 * cell)
	cmd.stamp(24.0 * cell, 20.0 * cell, 6.0 * cell)
	t.eq(cmd.commit(), true, "a stroke that painted something commits")
	t.ok(cmd.regions.size() > 0, "regions captured")
	t.ok(cmd.cost_bytes() > 0, "the stroke prices itself")
	var painted: PackedByteArray = sf.mask.values.duplicate()
	t.ne(painted, before, "the mask changed")
	t.ok(sf.mask.occupied_chunks() > 0, "occupancy followed the paint")

	cmd.undo()
	t.eq(sf.mask.values, before, "undo restores the mask byte for byte")
	t.eq(sf.mask.occupied_chunks(), 0, "and the occupancy bits with it")
	cmd.do()
	t.eq(sf.mask.values, painted, "redo re-applies exactly")
	t.ok(sf.mask.occupied_chunks() > 0)


func _overpaint(t) -> void:
	## Painting one species over another is destructive; undo must give back
	## the slot that was there, not merely clear the cells.
	var sf := _make(64, 64)
	var cell: float = HeightField.CELL_M
	var first := ScatterStrokeCommand.begin(sf, 0)
	first.stamp(16.0 * cell, 16.0 * cell, 8.0 * cell)
	first.commit()
	var after_first: PackedByteArray = sf.mask.values.duplicate()
	t.eq(sf.mask.slot_at(16, 16), 0)

	var second := ScatterStrokeCommand.begin(sf, 1)
	second.stamp(16.0 * cell, 16.0 * cell, 4.0 * cell)
	t.eq(second.commit(), true)
	t.eq(sf.mask.slot_at(16, 16), 1, "the second species won")
	second.undo()
	t.eq(sf.mask.values, after_first, "undo restores the first species")
	t.eq(sf.mask.slot_at(16, 16), 0)

	var eraser := ScatterStrokeCommand.begin(sf, -1)
	eraser.stamp(16.0 * cell, 16.0 * cell, 8.0 * cell)
	t.eq(eraser.commit(), true)
	t.eq(sf.mask.slot_at(16, 16), -1, "black erases")
	eraser.undo()
	t.eq(sf.mask.values, after_first, "and the erase undoes")


func _empty_stroke(t) -> void:
	var sf := _make(64, 64)
	var cmd := ScatterStrokeCommand.begin(sf, 0)
	t.eq(cmd.commit(), false, "a stroke that never stamped is not a history entry")
	var off := ScatterStrokeCommand.begin(sf, 0)
	off.stamp(-500.0, -500.0, 20.0)
	t.eq(off.commit(), false, "nor is one that missed the map")
	# Repainting the same value writes nothing new.
	var cell: float = HeightField.CELL_M
	var a := ScatterStrokeCommand.begin(sf, 0)
	a.stamp(10.0 * cell, 10.0 * cell, 4.0 * cell)
	t.eq(a.commit(), true)
	var b := ScatterStrokeCommand.begin(sf, 0)
	b.stamp(10.0 * cell, 10.0 * cell, 4.0 * cell)
	t.eq(b.commit(), false, "painting the same slot again is a no-op")
	var nowhere := ScatterStrokeCommand.begin(null, 0)
	t.eq(nowhere.commit(), false, "no field, no stroke")


func _labels(t) -> void:
	var sf := _make(64, 64)
	t.eq(ScatterStrokeCommand.begin(sf, 0).describe(), "scatter grass")
	t.eq(ScatterStrokeCommand.begin(sf, 1).describe(), "scatter rock")
	t.eq(ScatterStrokeCommand.begin(sf, -1).describe(), "erase scatter")
	t.eq(ScatterStrokeCommand.begin(sf, 9).describe(), "scatter slot 9")
