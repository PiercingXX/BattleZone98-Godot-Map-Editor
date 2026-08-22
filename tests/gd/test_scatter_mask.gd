extends RefCounted
## ScatterMask: slot quantisation, chunk occupancy, brush stamps, dirty drain.


func run(t) -> void:
	_slots(t)
	_occupancy(t)
	_stamp(t)
	_dirty(t)
	_adopt(t)


func _slots(t) -> void:
	t.eq(ScatterMask.decode(ScatterMask.EMPTY), -1, "0 is empty, not slot 0")
	for slot in ScatterMask.SLOTS:
		var v: int = ScatterMask.encode(slot)
		t.ok(v > 0, "slot %d paints non-zero" % slot)
		t.eq(ScatterMask.decode(v), slot, "slot %d round-trips" % slot)
	t.eq(ScatterMask.encode(-1), ScatterMask.EMPTY, "erase encodes to 0")
	t.eq(ScatterMask.encode(ScatterMask.SLOTS), ScatterMask.EMPTY, "slot past the end is empty")
	t.eq(ScatterMask.encode(ScatterMask.SLOTS - 1), 255, "last slot is full white")
	# Quantisation is against a FIXED 16, so a byte keeps its meaning however
	# many species the map happens to define.
	t.eq(ScatterMask.decode(ScatterMask.encode(3)), 3)
	t.eq(ScatterMask.decode(200), 12, "an off-step byte snaps to its slot")


func _occupancy(t) -> void:
	var m := ScatterMask.new()
	m.resize(96, 64)
	t.eq(m.chunks_x, 3, "96 cells is 3 chunks of 32")
	t.eq(m.chunks_z, 2)
	t.eq(m.occupied_chunks(), 0, "a fresh mask is empty everywhere")
	t.eq(m.chunk_occupied(0, 0), false)
	m.set_slot(5, 5, 0)
	t.eq(m.chunk_occupied(0, 0), true, "the painted chunk is occupied")
	t.eq(m.chunk_occupied(1, 0), false, "its neighbour is not")
	t.eq(m.occupied_chunks(), 1)
	t.eq(m.chunk_slot_bits(0, 0), 1, "slot 0 present")
	m.set_slot(6, 5, 3)
	t.eq(m.chunk_slot_bits(0, 0), 1 | (1 << 3), "two slots present")
	t.eq(m.chunk_count(0, 0), 2)
	# Erasing the last cell must clear the bit — a bitmap that only ever sets
	# would leave the chunk being rebuilt forever.
	m.set_slot(5, 5, -1)
	m.set_slot(6, 5, -1)
	t.eq(m.chunk_count(0, 0), 0)
	t.eq(m.chunk_occupied(0, 0), false, "erase clears occupancy")
	t.eq(m.chunk_slot_bits(0, 0), 0)
	t.eq(m.occupied_chunks(), 0)
	var bits: PackedByteArray = m.occupancy_bits()
	t.eq(bits.size(), 1, "6 chunks fit one byte")


func _stamp(t) -> void:
	var m := ScatterMask.new()
	m.resize(64, 64)
	var cell: float = HeightField.CELL_M
	var rect: Rect2i = m.stamp_circle(32.0 * cell, 32.0 * cell, 3.0 * cell, 2)
	t.ok(rect.has_area(), "stamp reports a rect")
	t.eq(m.slot_at(32, 32), 2, "centre painted")
	t.eq(m.slot_at(34, 32), 2, "inside the radius")
	# The dab is a disc, not the square that bounds it.
	t.eq(m.slot_at(rect.position.x, rect.position.y), -1, "corner of the rect stays empty")
	t.eq(m.slot_at(0, 0), -1, "far cells untouched")
	var painted := 0
	for z in 64:
		for x in 64:
			if m.slot_at(x, z) >= 0:
				painted += 1
	t.ok(painted > 20 and painted < 60, "disc area, got %d" % painted)
	m.stamp_circle(32.0 * cell, 32.0 * cell, 3.0 * cell, -1)
	t.eq(m.chunk_count(1, 1), 0, "painting black erases")
	# Clipped brushes must not wrap or crash.
	m.stamp_circle(-100.0, -100.0, 20.0, 0)
	t.eq(m.occupied_chunks(), 0, "a brush off the map paints nothing")


func _dirty(t) -> void:
	var m := ScatterMask.new()
	m.resize(64, 64)
	t.eq(m.take_dirty_chunks().size(), 4, "resize dirties every chunk")
	t.eq(m.has_dirty(), false, "drained")
	m.set_slot(1, 1, 0)
	m.set_slot(2, 1, 0)
	var keys: PackedInt32Array = m.take_dirty_chunks()
	t.eq(keys.size(), 1, "two cells in one chunk is one dirty chunk")
	t.eq(ScatterMask.key_x(keys[0]), 0)
	t.eq(ScatterMask.key_z(keys[0]), 0)
	m.set_slot(40, 40, 0)
	t.eq(m.take_dirty_chunks().size(), 1)
	m.set_value(3, 3, ScatterMask.EMPTY)
	t.eq(m.has_dirty(), false, "a write that changes nothing is not dirty")


func _adopt(t) -> void:
	var m := ScatterMask.new()
	m.resize(64, 64)
	m.set_slot(10, 10, 1)
	m.set_slot(50, 50, 4)
	var saved: PackedByteArray = m.values.duplicate()
	var m2 := ScatterMask.new()
	m2.resize(64, 64)
	t.eq(m2.adopt(saved), true, "adopt a saved mask")
	t.eq(m2.values, saved, "bytes survive the round trip")
	t.eq(m2.chunk_occupied(0, 0), true)
	t.eq(m2.chunk_occupied(1, 1), true)
	t.eq(m2.chunk_slot_bits(1, 1), 1 << 4, "counts rebuilt from the bytes")
	t.eq(m2.occupied_chunks(), 2)
	var wrong := PackedByteArray()
	wrong.resize(10)
	t.eq(m2.adopt(wrong), false, "a wrong-sized mask is refused")
