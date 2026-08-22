extends RefCounted
class_name TerrainClipmap
## Geometry clipmap — concentric rings of flat XZ tiles centred on the camera,
## each ring twice the previous ring's quad size. Implemented from NVIDIA GPU
## Gems 2 chapter 2 ("Terrain Rendering Using GPU-Based Geometry Clipmaps",
## Asirvatham & Hoppe): fixed ring structure, per-ring toroidal snapping,
## interior trim for the odd/even parity gap, degenerate outer seam.
##
## Chosen over a quadtree because the map is bounded and the camera flies
## freely: instance count, triangle count and vertex-buffer contents are all
## constant, and nothing pops when the camera merely rotates.
##
## Meshes hold XZ only — height comes from the height texture in the vertex
## shader, so a sculpt edit costs nothing here. They are built once by
## setup() and never touched again; only instance transforms move.
##
## Layout, per level, in that level's quad units. Slots along an axis:
##     A [-2T, -T]   B [-T, 0]   C [0, 1]   D [1, T+1]   E [T+1, 2T+1]
## The footprint is therefore [-2T, 2T+1] = 4T+1 quads. Level 0 fills it with
## all 16 A/B/D/E tile pairs plus a full cross over slot C. Every outer level
## drops the four B/D×B/D tiles and the inner arms of the cross, leaving a
## hole of exactly [-T, T+1] — which is 4T+2 quads of the *next finer* level,
## one quad more than that level's own 4T+1 footprint. That single-quad
## L-shaped remainder is the trim.

const TILE_QUADS := 32
## Half-width of a level, in that level's quads: the footprint runs
## [-(HALF_SPAN - 1), HALF_SPAN] and the trim square runs [-HALF_SPAN, HALF_SPAN].
const HALF_SPAN := 2 * TILE_QUADS + 1
## Vertical slack on instance AABBs (m). Absorbs an in-progress sculpt stroke,
## which updates the height texture before the range map hears about it.
const AABB_PAD_M := 48.0
## Fallback vertical extent when no range map is available: the widest a raw
## u16 heightfield can be. Loose, but never culls something that is on screen.
const AABB_FALLBACK := Vector2(0.0, 6553.5)

const KIND_TILE := 0
const KIND_FILLER := 1
const KIND_TRIM := 2
const KIND_SEAM := 3

var levels: int = 0

var _tile_mesh: ArrayMesh
var _filler_full_mesh: ArrayMesh
var _filler_ring_mesh: ArrayMesh
var _trim_mesh: ArrayMesh
var _seam_mesh: ArrayMesh

var _inst: Array[RID] = []
var _level: PackedInt32Array = PackedInt32Array()
var _kind: PackedInt32Array = PackedInt32Array()
var _offset: PackedVector2Array = PackedVector2Array()
var _bounds: Array[Rect2] = []
var _xform: Array[Transform3D] = []

## Quarter-turn bases for the four trim orientations. Rotation, never mirror:
## a mirrored basis flips the winding and cull_back would eat the piece.
var _trim_basis: Array[Basis] = []


func setup(scenario: RID, material: RID, p_levels: int) -> void:
	clear()
	levels = clampi(p_levels, 2, 12)
	_build_meshes()
	_build_slots()
	for i in _kind.size():
		var inst := RenderingServer.instance_create()
		RenderingServer.instance_set_scenario(inst, scenario)
		RenderingServer.instance_set_base(inst, _mesh_for(_kind[i], _level[i]).get_rid())
		RenderingServer.instance_geometry_set_material_override(inst, material)
		# Rings cast into the sun's shadow map. The ring meshes are flat until
		# the vertex shader displaces them, and the shadow pass runs that same
		# shader, so a caster follows the sculpted surface. Outer rings are
		# coarse, but they are also past the 2350 m shadow distance.
		RenderingServer.instance_geometry_set_cast_shadows_setting(
			inst, RenderingServer.SHADOW_CASTING_SETTING_ON)
		RenderingServer.instance_set_visible(inst, false)
		_inst.append(inst)


## The owning node calls this from _exit_tree. Not from NOTIFICATION_PREDELETE:
## by then the instance's own members are gone and freeing there only produces
## null-instance errors on the way out.
func clear() -> void:
	for inst in _inst:
		RenderingServer.free_rid(inst)
	_inst.clear()
	_level.clear()
	_kind.clear()
	_offset.clear()
	_bounds.clear()
	_xform.clear()
	# Drop the ring meshes too. Freeing only the instances leaves the five
	# ArrayMesh resources referenced by this object, which the renderer
	# reports at shutdown as leaked Mesh and Material RIDs. setup() rebuilds
	# them, so releasing here costs nothing.
	_tile_mesh = null
	_filler_full_mesh = null
	_filler_ring_mesh = null
	_trim_mesh = null
	_seam_mesh = null
	levels = 0


func instance_count() -> int:
	return _inst.size()


func triangle_count() -> int:
	var n := 0
	for i in _kind.size():
		n += int(_mesh_for(_kind[i], _level[i]).surface_get_array_index_len(0) / 3)
	return n


## World placement of instance i for a given ring centre. This is the whole
## of the layout; update() only feeds it to the RenderingServer.
func placement(i: int, center: Vector2) -> Transform3D:
	var step := HeightField.CELL_M * float(1 << _level[i])
	var kind := _kind[i]
	if kind == KIND_TILE or kind == KIND_FILLER:
		var snapped := _snap(center, step) + _offset[i] * step
		return Transform3D(
			Basis().scaled(Vector3(step, 1.0, step)),
			Vector3(snapped.x, 0.0, snapped.y))
	# Trim and seam sit on the *parent* ring's hole, not on this ring's own
	# grid: the hole edge is what they have to meet.
	var snapped_c := _snap(center, step * 2.0)
	var origin := snapped_c + Vector2(step, step)
	var basis := Basis()
	if kind == KIND_TRIM:
		var snapped_f := _snap(center, step)
		basis = _trim_basis[_trim_rot(
			int(round((snapped_f.x - snapped_c.x) / step)),
			int(round((snapped_f.y - snapped_c.y) / step))
		)]
	return Transform3D(
		basis.scaled(Vector3(step, 1.0, step)),
		Vector3(origin.x, 0.0, origin.y))


func instance_mesh(i: int) -> ArrayMesh:
	return _mesh_for(_kind[i], _level[i])


func instance_level(i: int) -> int:
	return _level[i]


func instance_kind(i: int) -> int:
	return _kind[i]


## Re-snap every ring to the camera. Called per frame; touches transforms and
## AABBs only, never geometry.
func update(center: Vector2, ranges: HeightRangeMap, map_w: float, map_d: float) -> void:
	if _inst.is_empty():
		return
	var cell := HeightField.CELL_M
	for i in _inst.size():
		var xf := placement(i, center)
		if xf == _xform[i]:
			continue
		_xform[i] = xf
		var step := cell * float(1 << _level[i])
		var lr: Rect2 = _bounds[i]
		var x0 := xf.origin.x + lr.position.x * step
		var z0 := xf.origin.z + lr.position.y * step
		var x1 := xf.origin.x + lr.end.x * step
		var z1 := xf.origin.z + lr.end.y * step
		if x1 <= 0.0 or z1 <= 0.0 or x0 >= map_w or z0 >= map_d:
			# Wholly off the map. The fragment shader clips the pieces that
			# only straddle the edge; these need not be submitted at all.
			RenderingServer.instance_set_visible(_inst[i], false)
			continue
		var span := AABB_FALLBACK
		if ranges != null and ranges.valid():
			span = ranges.range_over(
				int(floor(x0 / cell)), int(floor(z0 / cell)),
				int(ceil(x1 / cell)), int(ceil(z1 / cell))
			)
		RenderingServer.instance_set_transform(_inst[i], xf)
		# Custom AABB or nothing: the mesh is flat, the height arrives in the
		# vertex shader, and Godot would cull a ridge that is plainly on screen.
		RenderingServer.instance_set_custom_aabb(_inst[i], AABB(
			Vector3(lr.position.x, span.x - AABB_PAD_M, lr.position.y),
			Vector3(lr.size.x, span.y - span.x + 2.0 * AABB_PAD_M, lr.size.y)
		))
		RenderingServer.instance_set_visible(_inst[i], true)


## Force the next update() to re-place everything (map size or range map changed).
func invalidate() -> void:
	for i in _xform.size():
		_xform[i] = Transform3D(Basis(), Vector3(INF, INF, INF))


static func _snap(c: Vector2, step: float) -> Vector2:
	return Vector2(floor(c.x / step) * step, floor(c.y / step) * step)


## Which quarter-turn puts the trim's L on the two hole edges the finer ring
## does not reach. d is the finer ring's offset from the hole corner, 0 or 1
## fine quads per axis; the L covers the low side when d is 1.
static func _trim_rot(dx: int, dz: int) -> int:
	if dx != 0:
		return 0 if dz != 0 else 1
	return 3 if dz != 0 else 2


func _mesh_for(kind: int, lvl: int) -> ArrayMesh:
	match kind:
		KIND_FILLER:
			# Only the innermost level has no hole, so only it needs the
			# middle of the cross.
			return _filler_full_mesh if lvl == 0 else _filler_ring_mesh
		KIND_TRIM:
			return _trim_mesh
		KIND_SEAM:
			return _seam_mesh
	return _tile_mesh


func _build_slots() -> void:
	var t := TILE_QUADS
	var slots: Array[int] = [-2 * t, -t, 1, t + 1]
	var full := Rect2(-2 * t, -2 * t, 4 * t + 1, 4 * t + 1)
	var square := Rect2(-HALF_SPAN, -HALF_SPAN, 2 * HALF_SPAN, 2 * HALF_SPAN)
	for lvl in levels:
		for sz in slots:
			for sx in slots:
				var inner := (sx == -t or sx == 1) and (sz == -t or sz == 1)
				if lvl > 0 and inner:
					continue  # the hole — the finer ring lives there
				_add_slot(lvl, KIND_TILE, Vector2(sx, sz), Rect2(0, 0, t, t))
		_add_slot(lvl, KIND_FILLER, Vector2.ZERO, full)
		if lvl < levels - 1:
			_add_slot(lvl, KIND_TRIM, Vector2.ZERO, square)
			_add_slot(lvl, KIND_SEAM, Vector2.ZERO, square)
	_xform.resize(_kind.size())
	invalidate()


func _add_slot(lvl: int, kind: int, off: Vector2, local: Rect2) -> void:
	_level.append(lvl)
	_kind.append(kind)
	_offset.append(off)
	_bounds.append(local)


func _build_meshes() -> void:
	var t := TILE_QUADS
	var h := HALF_SPAN
	_tile_mesh = _rect_mesh([Rect2i(0, 0, t, t)])
	# Level 0's cross: the whole slot-C column and row, split so no quad is
	# emitted twice.
	_filler_full_mesh = _rect_mesh([
		Rect2i(0, -2 * t, 1, 2 * t),
		Rect2i(0, 1, 1, 2 * t),
		Rect2i(-2 * t, 0, 2 * t, 1),
		Rect2i(1, 0, 2 * t, 1),
		Rect2i(0, 0, 1, 1),
	])
	# Outer levels keep only the four arms that fall outside the hole.
	_filler_ring_mesh = _rect_mesh([
		Rect2i(0, -2 * t, 1, t),
		Rect2i(0, t + 1, 1, t),
		Rect2i(-2 * t, 0, t, 1),
		Rect2i(t + 1, 0, t, 1),
	])
	# L of width one quad along the low x and low z edges of the hole.
	_trim_mesh = _rect_mesh([
		Rect2i(-h, -h, 1, 2 * h),
		Rect2i(-h + 1, -h, 2 * h - 1, 1),
	])
	_seam_mesh = _build_seam_mesh()
	_trim_basis.clear()
	for k in 4:
		_trim_basis.append(Basis.from_euler(Vector3(0.0, float(k) * PI * 0.5, 0.0)))


## Degenerate outer seam (GPU Gems 2, §2.4.1). Around the trim square — which
## is exactly the parent ring's hole edge — every second vertex of this ring
## has no partner on the coarse side. Geomorphing puts it on the coarse edge
## line, so these triangles collapse to zero area; if float rounding opens a
## pinhole they plug it. Both windings, because a collapsed triangle has no
## reliable facing and cull_back would drop half of them.
func _build_seam_mesh() -> ArrayMesh:
	var h := HALF_SPAN
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var sides: Array[Array] = [
		[Vector3(-h, 0, -h), Vector3(1, 0, 0)],
		[Vector3(h, 0, -h), Vector3(0, 0, 1)],
		[Vector3(h, 0, h), Vector3(-1, 0, 0)],
		[Vector3(-h, 0, h), Vector3(0, 0, -1)],
	]
	for side in sides:
		var start: Vector3 = side[0]
		var dir: Vector3 = side[1]
		var base := verts.size()
		for i in 2 * h + 1:
			verts.append(start + dir * float(i))
			norms.append(Vector3.UP)
		for i in h:
			var a := base + i * 2
			idx.append(a)
			idx.append(a + 1)
			idx.append(a + 2)
			idx.append(a)
			idx.append(a + 2)
			idx.append(a + 1)
	return _commit(verts, norms, idx)


func _rect_mesh(rects: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for r: Rect2i in rects:
		var base := verts.size()
		var nx := r.size.x + 1
		for z in r.size.y + 1:
			for x in nx:
				verts.append(Vector3(float(r.position.x + x), 0.0, float(r.position.y + z)))
				norms.append(Vector3.UP)
		for z in r.size.y:
			for x in r.size.x:
				var i0 := base + z * nx + x
				var i1 := i0 + 1
				var i2 := i0 + nx
				var i3 := i2 + 1
				# Same winding as the chunk mesh this replaced: seen from +Y
				# this order is front-facing, the reverse culls the terrain.
				idx.append(i0)
				idx.append(i1)
				idx.append(i2)
				idx.append(i1)
				idx.append(i3)
				idx.append(i2)
	return _commit(verts, norms, idx)


func _commit(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
