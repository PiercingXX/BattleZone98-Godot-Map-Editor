extends Node3D
class_name ScatterPreview
## Viewport preview of painted scatter: one MultiMesh per occupied chunk.
##
## Plants used to be invisible — a green tint on the mask overlay was the only
## feedback — so what you painted could not be judged until the map was saved
## and launched. This draws them.
##
## Rebuilds are chunk-local and TIME-BUDGETED: dirty chunks go on a queue and
## each frame drains it until a microsecond budget is spent. A brush drag
## touches chunks faster than they can be regenerated, and a stall that
## tracks brush speed is a broken tool, not a slow one (C17). One chunk is
## always taken per pump so a chunk costlier than the whole budget still
## makes progress instead of wedging the queue.
##
## Empty chunks never allocate: the mask's occupancy bit is checked before
## anything is generated, and a chunk that empties frees its node outright,
## so a map with one painted corner draws one MultiMesh.

## Session-only View toggle, same ownership as AiPathOverlay/BalanceOverlay.
static var enabled: bool = true

const BUDGET_USEC := 1000
## A chunk past this is drawn truncated rather than blowing the frame; at the
## 2 m spacing floor a 160 m chunk holds ~4400 discs.
const MAX_PER_CHUNK := 6000
## Vertical slack on the per-chunk AABB, in metres.
const AABB_PAD_M := 8.0

var scatter: ScatterField
var terrain: ScatterField.Terrain
var budget_usec: int = BUDGET_USEC
## Chunks rebuilt / instances drawn by the last pump. Read by the status bar.
var last_rebuilt: int = 0
var last_instances: int = 0

var _active: bool = false
var _nodes: Dictionary = {}
var _queue: Array[int] = []
var _queued: Dictionary = {}
var _mesh: ArrayMesh
var _material: StandardMaterial3D


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	if not _active:
		return
	queue_dirty()
	pump(budget_usec)


## Point the preview at a field and the terrain its rules read. Either may be
## null, which simply leaves nothing to draw.
func attach(p_scatter: ScatterField, p_terrain: ScatterField.Terrain) -> void:
	scatter = p_scatter
	terrain = p_terrain
	clear()
	if _active:
		queue_all()


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	if on:
		queue_all()
	else:
		clear()


func is_active() -> bool:
	return _active


## Discard every built chunk and empty the queue.
func clear() -> void:
	for k in _nodes.keys():
		_free_node(_nodes[k])
	_nodes.clear()
	_queue.clear()
	_queued.clear()
	last_rebuilt = 0
	last_instances = 0


func queue_all() -> void:
	if scatter == null:
		return
	scatter.mask.mark_all_dirty()
	queue_dirty()


## Move the mask's dirty chunks onto the rebuild queue. Returns how many were
## newly queued — a chunk already waiting is not queued twice.
func queue_dirty() -> int:
	if scatter == null or not scatter.mask.has_dirty():
		return 0
	var n := 0
	for key in scatter.mask.take_dirty_chunks():
		if _queued.has(key):
			continue
		_queued[key] = true
		_queue.append(key)
		n += 1
	return n


func queue_chunk(cx: int, cz: int) -> void:
	var key := ScatterMask.chunk_key(cx, cz)
	if _queued.has(key):
		return
	_queued[key] = true
	_queue.append(key)


func queued() -> int:
	return _queue.size()


## Rebuild queued chunks until the budget is spent. Returns chunks rebuilt.
func pump(usec: int = BUDGET_USEC) -> int:
	last_rebuilt = 0
	last_instances = 0
	if scatter == null or _queue.is_empty():
		return 0
	var started := Time.get_ticks_usec()
	var limit := maxi(usec, 1)
	while not _queue.is_empty():
		var key: int = _queue.pop_front()
		_queued.erase(key)
		last_instances += _rebuild_chunk(ScatterMask.key_x(key), ScatterMask.key_z(key))
		last_rebuilt += 1
		if Time.get_ticks_usec() - started >= limit:
			break
	return last_rebuilt


func chunk_nodes() -> int:
	return _nodes.size()


func instance_count() -> int:
	var n := 0
	for k in _nodes.keys():
		var mmi: MultiMeshInstance3D = _nodes[k]
		if mmi != null and mmi.multimesh != null:
			n += mmi.multimesh.instance_count
	return n


func has_chunk(cx: int, cz: int) -> bool:
	return _nodes.has(ScatterMask.chunk_key(cx, cz))


func _rebuild_chunk(cx: int, cz: int) -> int:
	var key := ScatterMask.chunk_key(cx, cz)
	# Occupancy first: an empty chunk must not reach the generator at all.
	if scatter == null or not scatter.mask.chunk_occupied(cx, cz) or terrain == null:
		_drop_chunk(key)
		return 0
	var list: Array = scatter.chunk_instances(cx, cz, terrain)
	if list.is_empty():
		_drop_chunk(key)
		return 0
	var n: int = mini(list.size(), MAX_PER_CHUNK)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _blade_mesh()
	mm.instance_count = n
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in n:
		var inst: Dictionary = list[i]
		var w := float(inst["w"])
		var h := float(inst["h"])
		var pos := Vector3(float(inst["x"]), float(inst["y"]), float(inst["z"]))
		var basis := Basis(Vector3.UP, float(inst["yaw"])).scaled(Vector3(w, h, w))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		mm.set_instance_color(i, ScatterSpecies.tint(int(inst["slot"])))
		lo = lo.min(pos - Vector3(w, 0.0, w))
		hi = hi.max(pos + Vector3(w, h, w))
	var mmi: MultiMeshInstance3D = _nodes.get(key)
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.name = "ScatterChunk_%d_%d" % [cx, cz]
		mmi.material_override = _blade_material()
		add_child(mmi)
		_nodes[key] = mmi
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(
		lo - Vector3(0.0, AABB_PAD_M, 0.0),
		(hi - lo) + Vector3(0.0, AABB_PAD_M * 2.0, 0.0)
	)
	return n


func _drop_chunk(key: int) -> void:
	if not _nodes.has(key):
		return
	_free_node(_nodes[key])
	_nodes.erase(key)


func _free_node(node: Variant) -> void:
	var n := node as Node
	if n == null:
		return
	if n.is_inside_tree():
		n.get_parent().remove_child(n)
		n.queue_free()
	else:
		n.free()


## Unit crossed billboard: two quads, base at y = 0, one metre each way, so
## the per-instance basis carries the whole size.
func _blade_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for quad in 2:
		var a: float = PI * 0.5 * float(quad)
		var dx: float = cos(a) * 0.5
		var dz: float = sin(a) * 0.5
		var base: int = verts.size()
		verts.append(Vector3(-dx, 0.0, -dz))
		verts.append(Vector3(dx, 0.0, dz))
		verts.append(Vector3(-dx, 1.0, -dz))
		verts.append(Vector3(dx, 1.0, dz))
		uvs.append(Vector2(0.0, 1.0))
		uvs.append(Vector2(1.0, 1.0))
		uvs.append(Vector2(0.0, 0.0))
		uvs.append(Vector2(1.0, 0.0))
		for _i in 4:
			norms.append(Vector3(0.0, 0.0, 1.0))
		idx.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh


func _blade_material() -> StandardMaterial3D:
	if _material != null:
		return _material
	_material = StandardMaterial3D.new()
	# Untextured on purpose: the preview shows WHERE and WHICH species, and
	# the species tint has to survive whatever the map's lighting is doing.
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	return _material
