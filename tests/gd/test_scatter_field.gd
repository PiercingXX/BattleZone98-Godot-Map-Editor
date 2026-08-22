extends RefCounted
## ScatterField: placement rules, chunk-local generation, and the determinism
## the byte-identical round-trip depends on (C6).

## md5 of the legacy seed-and-count plant mesh for the fixture below, taken
## from the code as it stood before painted scatter existed. Painted scatter
## feeds build_plant_field; it must never change what the old path emits.
const LEGACY_MESH_MD5 := "c5c8978f44803d5286af4e8da9bd79dd"


func run(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz_scatter_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_rules(t)
	_material_exclusion(t)
	_spacing(t)
	_chunk_locality(t)
	_determinism(t)
	_range_map(t)
	_mesh_path(t, tmp)
	_legacy_untouched(t, tmp)
	_serialization(t)
	_rm_rf(tmp)


# --- fixtures ---------------------------------------------------------------

func _field(gx: int, gz: int, raw: int) -> HeightField:
	var f := HeightField.new()
	f.grid_x = gx
	f.grid_z = gz
	var h := PackedInt32Array()
	h.resize(gx * gz)
	h.fill(raw)
	f.heights = h
	return f


func _ramp_field(gx: int, gz: int, rise_raw_per_cell: int) -> HeightField:
	var f := _field(gx, gz, 0)
	for z in gz:
		for x in gx:
			f.heights[z * gx + x] = x * rise_raw_per_cell
	return f


func _scatter(gx: int, gz: int, sp: ScatterSpecies) -> ScatterField:
	var sf := ScatterField.new()
	sf.resize(gx, gz)
	sf.set_species([sp])
	sf.set_seed(4242)
	return sf


func _paint_cells(sf: ScatterField, x0: int, z0: int, x1: int, z1: int, slot: int) -> void:
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			sf.mask.set_slot(x, z, slot)


# --- tests ------------------------------------------------------------------

func _rules(t) -> void:
	var sp := ScatterSpecies.make("grass", 10.0)
	var sf := _scatter(64, 64, sp)
	_paint_cells(sf, 0, 0, 31, 31, 0)
	var flat := ScatterField.Terrain.of(_field(64, 64, 1000))
	var n: int = sf.chunk_instances(0, 0, flat).size()
	t.ok(n > 10, "flat ground inside the band scatters, got %d" % n)

	sp.height_max_m = 50.0
	sf.invalidate()
	t.eq(sf.chunk_instances(0, 0, flat).size(), 0, "100 m ground fails a 50 m ceiling")
	sp.height_max_m = 10000.0
	sp.height_min_m = 150.0
	sf.invalidate()
	t.eq(sf.chunk_instances(0, 0, flat).size(), 0, "and a 150 m floor")
	sp.height_min_m = -10000.0
	sf.invalidate()
	t.eq(sf.chunk_instances(0, 0, flat).size(), n, "band restored, same field")

	# 5 m of rise per 5 m cell is 45 degrees.
	var steep := ScatterField.Terrain.of(_ramp_field(64, 64, 50))
	t.eq(sf.chunk_instances(0, 0, steep).size(), 0, "45 deg fails a 12 deg ceiling")
	sp.slope_max_deg = 60.0
	sf.invalidate()
	t.ok(sf.chunk_instances(0, 0, steep).size() > 10, "raising the ceiling lets it through")
	sp.slope_min_deg = 60.0
	sf.invalidate()
	t.eq(sf.chunk_instances(0, 0, steep).size(), 0, "and a floor above the slope excludes it")

	# Instances must sit ON the ground, sunk by the same amount the mesh uses.
	sp.slope_min_deg = 0.0
	sp.slope_max_deg = 12.0
	sf.invalidate()
	var list: Array = sf.chunk_instances(0, 0, flat)
	var inst: Dictionary = list[0]
	t.near(float(inst["y"]), 100.0 - ScatterField.SINK_M, 0.01, "billboard base is sunk")
	t.ok(float(inst["h"]) > 0.0 and float(inst["w"]) > 0.0, "size jitter is positive")
	t.eq(int(inst["slot"]), 0)


func _material_exclusion(t) -> void:
	var sp := ScatterSpecies.make("scrub", 10.0)
	var sf := _scatter(64, 64, sp)
	_paint_cells(sf, 0, 0, 31, 31, 0)
	var terrain := ScatterField.Terrain.of(_field(64, 64, 1000))
	var words := PackedInt32Array()
	words.resize(16 * 16)
	words.fill(3 << 12)
	terrain.set_materials(words, 16, 16)
	t.ok(sf.chunk_instances(0, 0, terrain).size() > 10, "slot 3 allowed by default")
	sp.exclude_slots = PackedInt32Array([3])
	sf.invalidate()
	t.eq(sf.chunk_instances(0, 0, terrain).size(), 0, "excluded slot grows nothing")
	sp.exclude_slots = PackedInt32Array([4])
	sf.invalidate()
	t.ok(sf.chunk_instances(0, 0, terrain).size() > 10, "a different slot is irrelevant")


func _spacing(t) -> void:
	## Discs are generated per chunk, so the interesting case is the seam.
	var sp := ScatterSpecies.make("tree", 20.0)
	var sf := _scatter(96, 96, sp)
	_paint_cells(sf, 0, 0, 95, 95, 0)
	var terrain := ScatterField.Terrain.of(_field(96, 96, 1000))
	var list: Array = sf.instances(terrain)
	t.ok(list.size() > 60, "three chunks square scatters, got %d" % list.size())
	var r2: float = 20.0 * 20.0
	var worst := INF
	for i in list.size():
		var a: Dictionary = list[i]
		for j in range(i + 1, list.size()):
			var b: Dictionary = list[j]
			var dx: float = float(a["x"]) - float(b["x"])
			var dz: float = float(a["z"]) - float(b["z"])
			worst = minf(worst, dx * dx + dz * dz)
	t.ok(worst >= r2, "spacing holds across chunk seams (worst %.2f m)" % sqrt(worst))


func _chunk_locality(t) -> void:
	var sp := ScatterSpecies.make("grass", 12.0)
	var sf := _scatter(128, 128, sp)
	_paint_cells(sf, 0, 0, 31, 31, 0)
	var terrain := ScatterField.Terrain.of(_field(128, 128, 1000))
	var before: Array = sf.chunk_instances(0, 0, terrain)
	t.ok(before.size() > 5, "chunk 0,0 has instances")
	t.eq(sf.chunk_instances(2, 2, terrain).size(), 0, "unpainted chunk is empty")
	# Painting a chunk that is not a neighbour must leave 0,0 untouched — an
	# edit costs the chunks it reached, not a whole-map regeneration.
	_paint_cells(sf, 64, 64, 95, 95, 0)
	t.eq(sf.chunk_instances(0, 0, terrain), before, "a distant edit changes nothing here")
	t.ok(sf.chunk_instances(2, 2, terrain).size() > 5, "the edited chunk filled in")
	# Erasing one cell only removes what stood on it.
	var after_erase_n: int = sf.chunk_instances(0, 0, terrain).size()
	_paint_cells(sf, 0, 0, 3, 3, -1)
	t.ok(sf.chunk_instances(0, 0, terrain).size() <= after_erase_n, "erase never adds")


func _determinism(t) -> void:
	var sp := ScatterSpecies.make("grass", 9.0)
	var sf := _scatter(96, 96, sp)
	_paint_cells(sf, 8, 8, 80, 80, 0)
	var terrain := ScatterField.Terrain.of(_field(96, 96, 1000))
	var a: Array = sf.instances(terrain)
	var b: Array = sf.instances(terrain)
	t.eq(a, b, "two rebuilds of the same field are identical")
	# A fresh object with the same record — the open-save-reopen shape.
	var sf2 := ScatterField.from_dict(sf.to_dict())
	sf2.resize(96, 96)
	t.eq(sf2.mask.adopt(sf.mask.values), true)
	t.eq(sf2.instances(terrain), a, "reloaded from its record, same instances")
	# Cache pressure must not perturb the result either.
	sf.invalidate()
	t.eq(sf.instances(terrain), a, "after dropping every cache, still identical")


func _range_map(t) -> void:
	var sp := ScatterSpecies.make("grass", 12.0)
	var sf := _scatter(64, 64, sp)
	_paint_cells(sf, 0, 0, 63, 63, 0)
	var field := _field(64, 64, 1000)
	var terrain := ScatterField.Terrain.of(field)
	var plain: Array = sf.instances(terrain)
	var rm := HeightRangeMap.new()
	rm.rebuild(field)
	terrain.range_map = rm
	t.eq(sf.instances(terrain), plain, "the range map is an early-out, not a filter")
	sp.height_min_m = 500.0
	sf.invalidate()
	t.eq(sf.instances(terrain), [], "a chunk outside the band is skipped whole")


func _mesh_path(t, tmp: String) -> void:
	var hm: BzHg2.HeightMap = _pit_heightmap()
	var sp := ScatterSpecies.make("grass", 14.0)
	var sf := ScatterField.new()
	sf.resize(256, 256)
	sf.set_species([sp])
	sf.set_seed(11)
	_paint_cells(sf, 100, 100, 160, 160, 0)
	var terrain := ScatterField.Terrain.from_heightmap(hm)
	var list: Array = sf.instances(terrain)
	t.ok(list.size() > 20, "painted scatter produced instances, got %d" % list.size())

	var a: String = tmp.path_join("mesh_a")
	var b: String = tmp.path_join("mesh_b")
	DirAccess.make_dir_recursive_absolute(a)
	DirAccess.make_dir_recursive_absolute(b)
	var r1: Dictionary = BzMeshGen.build_plant_field(
		a, "plnt1", hm, 0, 0, "plants", 0.0, 12.0, [], 140.0, 4.0, 2.2, null,
		PackedByteArray(), list
	)
	var r2: Dictionary = BzMeshGen.build_plant_field(
		b, "plnt1", hm, 0, 0, "plants", 0.0, 12.0, [], 140.0, 4.0, 2.2, null,
		PackedByteArray(), sf.instances(terrain)
	)
	t.eq(r1.get("written"), true, "instances emit a mesh")
	t.eq(r2.get("written"), true)
	t.eq(
		_md5(a.path_join("plnt1.mesh")),
		_md5(b.path_join("plnt1.mesh")),
		"same painted field, byte-identical mesh"
	)
	# Instances with no count must still refuse to invent geometry.
	var empty: Dictionary = BzMeshGen.build_plant_field(
		a, "plnt9", hm, 0, 0, "plants", 0.0, 12.0, [], 140.0, 4.0, 2.2, null,
		PackedByteArray(), []
	)
	t.eq(empty.get("written"), false, "no count and no instances writes nothing")


func _legacy_untouched(t, tmp: String) -> void:
	## The seed-and-count path is what shipped maps were built with. Its bytes
	## are frozen here: a map whose scatter was never touched must save the
	## same file it saved before painted scatter existed.
	var out: String = tmp.path_join("legacy")
	DirAccess.make_dir_recursive_absolute(out)
	var hm: BzHg2.HeightMap = _pit_heightmap()
	var r: Dictionary = BzMeshGen.build_plant_field(
		out, "plnt1", hm, 7, 40, "plants", 0.0, 12.0, [], 140.0, 4.0, 2.2, null,
		_flat_plant_mask()
	)
	t.eq(r.get("written"), true, "legacy field still writes")
	t.eq(_md5(out.path_join("plnt1.mesh")), LEGACY_MESH_MD5, "legacy plant mesh unchanged")


func _serialization(t) -> void:
	var sp := ScatterSpecies.make("thorn", 7.5)
	sp.slope_max_deg = 22.0
	sp.height_min_m = 12.0
	sp.exclude_slots = PackedInt32Array([2, 5])
	sp.scale_jitter = 0.4
	var round_trip := ScatterSpecies.from_dict(sp.to_dict())
	t.eq(round_trip.name, "thorn")
	t.near(round_trip.spacing_m, 7.5, 0.001)
	t.near(round_trip.slope_max_deg, 22.0, 0.001)
	t.near(round_trip.height_min_m, 12.0, 0.001)
	t.eq(round_trip.exclude_slots, PackedInt32Array([2, 5]))
	t.eq(round_trip.allows_slot(2), false)
	t.eq(round_trip.allows_slot(1), true)
	# Density and spacing are two views of one number.
	var r: float = ScatterSpecies.spacing_for_density(70.0)
	t.near(ScatterSpecies.density_for_spacing(r), 70.0, 0.01, "density round-trips")
	t.eq(ScatterSpecies.clamp_spacing(0.1), ScatterSpecies.MIN_SPACING_M, "spacing floor")
	t.eq(ScatterSpecies.clamp_spacing(9999.0), ScatterSpecies.MAX_SPACING_M, "spacing ceiling")

	var sf := ScatterField.new()
	sf.set_seed(9)
	sf.set_species([sp])
	var back := ScatterField.from_dict(sf.to_dict())
	t.eq(back.seed, 9)
	t.eq(back.species.size(), 1)
	t.eq(back.species[0].name, "thorn")
	# A legacy plants record carries no scatter block and must stay legacy.
	t.eq(ScatterField.from_feature({"stem": "plnt1", "density": 260}), null)
	var live := ScatterField.from_feature({"stem": "p", "seed": 5, "scatter": sf.to_dict()})
	t.ne(live, null)
	t.eq(live.seed, 5, "the record's seed wins")


# --- helpers ----------------------------------------------------------------

func _pit_heightmap() -> BzHg2.HeightMap:
	var data := PackedInt32Array()
	data.resize(256 * 256)
	data.fill(1000)
	for z in range(40, 81):
		for x in range(40, 81):
			data[z * 256 + x] = 400
	return BzHg2.HeightMap.new(1, 1, data)


func _flat_plant_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(256 * 256)
	mask.fill(1)
	for z in range(40, 81):
		for x in range(40, 81):
			mask[z * 256 + x] = 0
	return mask


func _md5(path: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()


func _rm_rf(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.include_hidden = true
	da.include_navigational = false
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		var child: String = path.path_join(fn)
		if da.current_is_dir():
			_rm_rf(child)
		else:
			DirAccess.remove_absolute(child)
		fn = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)
