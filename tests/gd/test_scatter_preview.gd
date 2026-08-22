extends RefCounted
## ScatterPreview: occupancy skipping, queue behaviour, and the frame budget.


func run(t) -> void:
	_empty_map_costs_nothing(t)
	_builds_painted_chunks(t)
	_erase_frees_chunks(t)
	_budget(t)
	_queue_dedupe(t)


func _terrain(gx: int, gz: int) -> ScatterField.Terrain:
	var f := HeightField.new()
	f.grid_x = gx
	f.grid_z = gz
	var h := PackedInt32Array()
	h.resize(gx * gz)
	h.fill(1000)
	f.heights = h
	return ScatterField.Terrain.of(f)


func _scatter(gx: int, gz: int) -> ScatterField:
	var sf := ScatterField.new()
	sf.resize(gx, gz)
	sf.set_species([ScatterSpecies.make("grass", 12.0)])
	sf.set_seed(3)
	return sf


func _paint(sf: ScatterField, x0: int, z0: int, x1: int, z1: int, slot: int) -> void:
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			sf.mask.set_slot(x, z, slot)


func _drain(preview: ScatterPreview) -> int:
	var pumps := 0
	while preview.queued() > 0 and pumps < 500:
		preview.pump(100000)
		pumps += 1
	return pumps


func _empty_map_costs_nothing(t) -> void:
	var preview := ScatterPreview.new()
	preview.attach(_scatter(128, 128), _terrain(128, 128))
	preview.set_active(true)
	t.eq(preview.queued(), 16, "every chunk queued on activation")
	_drain(preview)
	t.eq(preview.chunk_nodes(), 0, "an unpainted map allocates no MultiMesh")
	t.eq(preview.instance_count(), 0)
	preview.free()


func _builds_painted_chunks(t) -> void:
	var sf := _scatter(128, 128)
	var terrain := _terrain(128, 128)
	_paint(sf, 0, 0, 31, 31, 0)
	var preview := ScatterPreview.new()
	preview.attach(sf, terrain)
	preview.set_active(true)
	_drain(preview)
	t.eq(preview.chunk_nodes(), 1, "only the painted chunk is built")
	t.eq(preview.has_chunk(0, 0), true)
	t.eq(preview.has_chunk(1, 1), false)
	var expect: int = sf.chunk_instances(0, 0, terrain).size()
	t.ok(expect > 5, "the chunk has instances to draw")
	t.eq(preview.instance_count(), expect, "every instance reached the MultiMesh")
	preview.free()


func _erase_frees_chunks(t) -> void:
	var sf := _scatter(128, 128)
	var terrain := _terrain(128, 128)
	_paint(sf, 40, 40, 60, 60, 0)
	var preview := ScatterPreview.new()
	preview.attach(sf, terrain)
	preview.set_active(true)
	_drain(preview)
	t.eq(preview.chunk_nodes(), 1)
	t.eq(preview.has_chunk(1, 1), true)
	_paint(sf, 40, 40, 60, 60, -1)
	t.ok(preview.queue_dirty() > 0, "the erase dirtied its chunk")
	_drain(preview)
	t.eq(preview.chunk_nodes(), 0, "an emptied chunk gives its node back")
	t.eq(preview.instance_count(), 0)
	preview.set_active(false)
	t.eq(preview.queued(), 0, "deactivating drops the queue")
	preview.free()


func _budget(t) -> void:
	var sf := _scatter(256, 256)
	var terrain := _terrain(256, 256)
	_paint(sf, 0, 0, 255, 255, 0)
	var preview := ScatterPreview.new()
	preview.attach(sf, terrain)
	preview.set_active(true)
	t.eq(preview.queued(), 64, "8x8 chunks queued")
	# A budget too small for even one chunk must still make progress, or the
	# queue never drains and the preview never appears.
	var done: int = preview.pump(0)
	t.eq(done, 1, "one chunk per pump at minimum")
	t.eq(preview.queued(), 63, "the rest waits its turn")
	t.ok(preview.last_instances > 0, "the pump reports what it drew")
	# A generous budget takes several chunks in one go.
	var many: int = preview.pump(200000)
	t.ok(many > 1, "a bigger budget takes more chunks, got %d" % many)
	var pumps: int = _drain(preview)
	t.eq(preview.queued(), 0, "the queue drains")
	t.eq(preview.chunk_nodes(), 64, "every painted chunk ends up built")
	t.eq(preview.pump(1000), 0, "an empty queue is free")
	t.ok(pumps < 500, "drained in bounded pumps")
	preview.free()


func _queue_dedupe(t) -> void:
	var sf := _scatter(128, 128)
	var preview := ScatterPreview.new()
	preview.attach(sf, _terrain(128, 128))
	preview.queue_chunk(1, 1)
	preview.queue_chunk(1, 1)
	t.eq(preview.queued(), 1, "a chunk queued twice is queued once")
	preview.queue_chunk(2, 1)
	t.eq(preview.queued(), 2)
	preview.clear()
	t.eq(preview.queued(), 0)
	t.eq(preview.chunk_nodes(), 0)
	# With nothing attached the pump is inert rather than a crash.
	var bare := ScatterPreview.new()
	t.eq(bare.pump(1000), 0)
	bare.queue_chunk(0, 0)
	t.eq(bare.queued(), 1)
	t.eq(bare.pump(1000), 0, "no field, nothing to build")
	bare.free()
	preview.free()
