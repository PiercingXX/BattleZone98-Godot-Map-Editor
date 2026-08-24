extends RefCounted
class_name ScatterField
## Painted scatter, resolved into instances on demand.
##
## The record is a mask plus a seed. No transform list is ever stored, in the
## session or in the map: every instance is re-derived, so a 1024^2 map's
## scatter costs one byte per cell however dense it is.
##
## Generation is chunk-local — a brush stamp rebuilds the chunks it touched —
## and every RNG is CONSTRUCTED FRESH from (seed, slot, chunk) at the point of
## use. No generator state survives a rebuild, so rebuilding twice yields the
## same instances in the same order, which is what C6's byte-identical
## round-trip rests on.
##
## Cross-chunk spacing: each chunk's raw disc set is independent, then a point
## is dropped when a raw point of a LOWER-ordered neighbouring chunk lies
## within r. The rule is asymmetric, so of any too-close pair exactly one
## survives and the kept set still honours the disc radius — without making a
## chunk's result depend on the order chunks happen to be rebuilt in.

const CHUNK_CELLS := ScatterMask.CHUNK_CELLS
## Billboards are sunk so the opaque part of the texture roots at ground
## level; the mesh path does the same (BzMeshGen.build_plant_field).
const SINK_M := 2.5
## Cached raw disc sets, keyed by slot and chunk. Generating one is the
## single most expensive thing here, so the cache is sized to hold a whole
## large map (a few KB per entry) and is dropped wholesale only when a change
## invalidates everything anyway.
const RAW_CACHE_MAX := 4096

var seed: int = 0
var mask := ScatterMask.new()
var species: Array[ScatterSpecies] = []
var k_samples: int = PoissonDisc.K_DEFAULT

var _raw: Dictionary = {}


## Terrain the rules are evaluated against. One adapter so the viewport
## (HeightField) and the save path (BzHg2.HeightMap) sample identically —
## the height/normal maths stays in TerrainRaycast, this only routes to it.
class Terrain:
	extends RefCounted

	const MAT_TILE_M := 20.0

	var field: HeightField
	var materials: PackedInt32Array = PackedInt32Array()
	var mat_grid_x: int = 0
	var mat_grid_z: int = 0
	## Optional min/max map. Supplies each chunk's height range without a
	## scan, which decides both the height-band early-out and the slope
	## bound below.
	var range_map: HeightRangeMap

	static func of(p_field: HeightField) -> Terrain:
		var t := Terrain.new()
		t.field = p_field
		return t

	## Adapt a backend heightmap. Its data is the same row-major raw word
	## array HeightField holds, flag bits and all (C1), at the same 0.1 m
	## scale — so this is a rebind, not a conversion.
	static func from_heightmap(hm: BzHg2.HeightMap) -> Terrain:
		var f := HeightField.new()
		if hm != null:
			f.grid_x = hm.grid_x
			f.grid_z = hm.grid_z
			f.heights = hm.data
		return of(f)

	func set_materials(p_materials: PackedInt32Array, p_gx: int, p_gz: int) -> void:
		if p_gx > 0 and p_gz > 0 and p_materials.size() == p_gx * p_gz:
			materials = p_materials
			mat_grid_x = p_gx
			mat_grid_z = p_gz

	func valid() -> bool:
		return field != null and field.grid_x > 1 and field.grid_z > 1

	func height_at(x_m: float, z_m: float) -> float:
		return TerrainRaycast.height_at(field, x_m, z_m)

	func slope_deg_at(x_m: float, z_m: float) -> float:
		var n := TerrainRaycast.normal_at(field, x_m, z_m)
		return rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))

	## Material slot of the 20 m tile under a world point, or -1 when the map
	## has no material grid (C4). Usually the high nibble, but a diagonal puts
	## its lone corner there and fills the tile with `mat_b`.
	func slot_at(x_m: float, z_m: float) -> int:
		if mat_grid_x < 1 or materials.is_empty():
			return -1
		var tx := clampi(int(floor(x_m / MAT_TILE_M)), 0, mat_grid_x - 1)
		var tz := clampi(int(floor(z_m / MAT_TILE_M)), 0, mat_grid_z - 1)
		return BzMat.fill_of_entry(materials[tz * mat_grid_x + tx])


func resize(grid_x: int, grid_z: int) -> void:
	mask.resize(grid_x, grid_z)
	_raw.clear()


func set_seed(v: int) -> void:
	if seed == v:
		return
	seed = v
	invalidate()


func set_species(list: Array) -> void:
	var typed: Array[ScatterSpecies] = []
	for sp in list:
		if sp is ScatterSpecies:
			typed.append(sp)
	species = typed
	invalidate()


func add_species(sp: ScatterSpecies) -> int:
	if sp == null or species.size() >= ScatterMask.SLOTS:
		return -1
	species.append(sp)
	invalidate()
	return species.size() - 1


func species_at(slot: int) -> ScatterSpecies:
	if slot < 0 or slot >= species.size():
		return null
	return species[slot]


## Drop every cached disc set and repaint the preview. Anything that changes
## what generation would produce must call this.
func invalidate() -> void:
	_raw.clear()
	mask.mark_all_dirty()


## Instances in one chunk, in stable order: slot ascending, then disc order.
func chunk_instances(cx: int, cz: int, terrain: Terrain) -> Array:
	var out: Array = []
	if terrain == null or not terrain.valid() or species.is_empty():
		return out
	if not mask.chunk_occupied(cx, cz):
		return out
	var bits := mask.chunk_slot_bits(cx, cz)
	if bits == 0:
		return out
	var band := _chunk_band(terrain, cx, cz)
	# Sound upper bound on the slope anywhere in the chunk: a central
	# difference spans 2 cells, so no gradient can exceed the chunk's whole
	# height range over that span. Cheap, and it lets gentle ground skip the
	# per-instance normal entirely.
	var slope_cap := rad_to_deg(atan(
		(band.y - band.x) * sqrt(2.0) / (2.0 * HeightField.CELL_M)
	))
	for slot in mini(species.size(), ScatterMask.SLOTS):
		if bits & (1 << slot) == 0:
			continue
		var sp: ScatterSpecies = species[slot]
		if sp == null:
			continue
		if band.y < sp.height_min_m or band.x > sp.height_max_m:
			continue
		if sp.slope_min_deg > slope_cap:
			continue
		_gather_slot(out, slot, sp, cx, cz, terrain, slope_cap)
	return out


## Every instance on the map, chunks row-major (C7).
func instances(terrain: Terrain) -> Array:
	var out: Array = []
	for cz in mask.chunks_z:
		for cx in mask.chunks_x:
			out.append_array(chunk_instances(cx, cz, terrain))
	return out


func to_dict() -> Dictionary:
	return {
		"version": 1,
		"seed": seed,
		"k": k_samples,
		"species": ScatterSpecies.list_to(species),
	}


static func from_dict(d: Dictionary) -> ScatterField:
	var sf := ScatterField.new()
	sf.seed = int(d.get("seed", 0))
	sf.k_samples = maxi(1, int(d.get("k", PoissonDisc.K_DEFAULT)))
	sf.species = ScatterSpecies.list_from(d.get("species", []))
	return sf


## Build from a features.json plants record. Returns null when the record
## carries no scatter block — that entry is a legacy count-and-seed field and
## must keep taking the old mesh path untouched.
static func from_feature(rec: Dictionary) -> ScatterField:
	var block: Variant = rec.get("scatter", null)
	if typeof(block) != TYPE_DICTIONARY:
		return null
	var sf := from_dict(block)
	if rec.has("seed"):
		sf.seed = int(rec.get("seed", sf.seed))
	return sf


func _gather_slot(
	out: Array,
	slot: int,
	sp: ScatterSpecies,
	cx: int,
	cz: int,
	terrain: Terrain,
	slope_cap: float
) -> void:
	var raw: Dictionary = _raw_set(slot, cx, cz, sp)
	var pts: PackedVector2Array = raw["pos"]
	if pts.is_empty():
		return
	var r := sp.radius_m()
	var r2 := r * r
	var yaws: PackedFloat32Array = raw["yaw"]
	var hs: PackedFloat32Array = raw["hs"]
	var ws: PackedFloat32Array = raw["ws"]
	var cell := HeightField.CELL_M
	# The neighbouring disc sets are fetched once, not once per point: the
	# lookup is the expensive part, the distance test is not.
	var guards: Array = _lower_neighbours(slot, cx, cz, sp)
	var span := float(CHUNK_CELLS) * cell
	var x0 := float(cx * CHUNK_CELLS) * cell
	var z0 := float(cz * CHUNK_CELLS) * cell
	var x1 := x0 + span
	var z1 := z0 + span
	# Slope costs four height samples per instance — the single most
	# expensive rule. When the chunk's own bound already satisfies the
	# species, no instance in it needs sampling at all.
	var skip_slope: bool = sp.slope_min_deg <= 0.0 and slope_cap <= sp.slope_max_deg
	for i in pts.size():
		var p := pts[i]
		if mask.slot_at(int(p.x / cell), int(p.y / cell)) != slot:
			continue
		if not guards.is_empty() \
				and (p.x - x0 <= r or x1 - p.x <= r or p.y - z0 <= r or z1 - p.y <= r) \
				and _blocked(guards, p, r2):
			continue
		var h := terrain.height_at(p.x, p.y)
		if not sp.allows_height(h):
			continue
		var mat_slot := terrain.slot_at(p.x, p.y)
		if mat_slot >= 0 and not sp.allows_slot(mat_slot):
			continue
		if not skip_slope and not sp.allows_slope(terrain.slope_deg_at(p.x, p.y)):
			continue
		out.append({
			"slot": slot,
			"x": p.x,
			"z": p.y,
			"y": h - SINK_M,
			"yaw": float(yaws[i]),
			"h": sp.blade_h_m * float(hs[i]),
			"w": sp.blade_w_m * float(ws[i]),
		})


## Disc sets of the neighbouring chunks that outrank this one. Only those:
## the rule has to be asymmetric or two chunks would each defer to the other
## and both drop the point.
func _lower_neighbours(slot: int, cx: int, cz: int, sp: ScatterSpecies) -> Array:
	var here := cz * mask.chunks_x + cx
	var out: Array = []
	for dz in range(-1, 2):
		var nz := cz + dz
		if nz < 0 or nz >= mask.chunks_z:
			continue
		for dx in range(-1, 2):
			var nx := cx + dx
			if nx < 0 or nx >= mask.chunks_x:
				continue
			if nz * mask.chunks_x + nx >= here:
				continue
			var pts: PackedVector2Array = _raw_set(slot, nx, nz, sp)["pos"]
			if not pts.is_empty():
				out.append(pts)
	return out


func _blocked(guards: Array, p: Vector2, r2: float) -> bool:
	for g in guards:
		var pts: PackedVector2Array = g
		for i in pts.size():
			if pts[i].distance_squared_to(p) < r2:
				return true
	return false


## Height range in metres over the chunk plus a cell of border, which is
## what a central difference at the chunk edge reaches. From the range map
## when there is one; a direct scan otherwise, still far cheaper than the
## per-instance normals it saves.
func _chunk_band(terrain: Terrain, cx: int, cz: int) -> Vector2:
	if terrain.range_map != null and terrain.range_map.valid():
		return terrain.range_map.range_over(
			cx * CHUNK_CELLS - 1, cz * CHUNK_CELLS - 1,
			(cx + 1) * CHUNK_CELLS + 1, (cz + 1) * CHUNK_CELLS + 1
		)
	var field := terrain.field
	var gx := field.grid_x
	var x0 := maxi(cx * CHUNK_CELLS - 1, 0)
	var z0 := maxi(cz * CHUNK_CELLS - 1, 0)
	var x1 := mini((cx + 1) * CHUNK_CELLS + 1, gx - 1)
	var z1 := mini((cz + 1) * CHUNK_CELLS + 1, field.grid_z - 1)
	var lo := 0x7FFFFFFF
	var hi := -0x7FFFFFFF
	for z in range(z0, z1 + 1):
		var row := z * gx
		for x in range(x0, x1 + 1):
			var v := field.heights[row + x]
			if v < lo:
				lo = v
			if v > hi:
				hi = v
	if hi < lo:
		return Vector2.ZERO
	return Vector2(float(lo) * HeightField.HEIGHT_SCALE, float(hi) * HeightField.HEIGHT_SCALE)


## One chunk's disc set for one species: positions plus the per-instance yaw
## and size jitter, drawn from the same generator in the same pass. Tying the
## jitter to the disc set — not to the accepted subset — means editing one
## cell cannot re-roll the plant next to it.
func _raw_set(slot: int, cx: int, cz: int, sp: ScatterSpecies) -> Dictionary:
	var key := "%d:%d:%d" % [slot, cx, cz]
	if _raw.has(key):
		return _raw[key]
	if _raw.size() >= RAW_CACHE_MAX:
		_raw.clear()
	var cell := HeightField.CELL_M
	var rect := Rect2(
		float(cx * CHUNK_CELLS) * cell,
		float(cz * CHUNK_CELLS) * cell,
		float(CHUNK_CELLS) * cell,
		float(CHUNK_CELLS) * cell
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(slot, cx, cz)
	var pts := PoissonDisc.sample(rect, sp.radius_m(), rng, k_samples)
	var yaw := PackedFloat32Array()
	var hs := PackedFloat32Array()
	var ws := PackedFloat32Array()
	yaw.resize(pts.size())
	hs.resize(pts.size())
	ws.resize(pts.size())
	var lo := 1.0 - sp.scale_jitter
	var hi := 1.0 + sp.scale_jitter
	for i in pts.size():
		yaw[i] = rng.randf_range(0.0, PI)
		hs[i] = rng.randf_range(lo, hi)
		ws[i] = rng.randf_range(lo, hi)
	var rec := {"pos": pts, "yaw": yaw, "hs": hs, "ws": ws}
	_raw[key] = rec
	return rec


## Stable 31-bit mix. Folded at every step so nothing depends on how a
## platform handles 64-bit overflow — the same map must scatter the same way
## on Linux and Windows (C12).
func _chunk_seed(slot: int, cx: int, cz: int) -> int:
	var h := 0x9E3779B1
	for part in [seed, slot, cx, cz]:
		var v := int(part) & 0x7FFFFFFF
		h = (h ^ v) & 0x7FFFFFFF
		h = (h * 1103515245 + 12345) & 0x7FFFFFFF
		h = (h ^ (h >> 15)) & 0x7FFFFFFF
	return h
