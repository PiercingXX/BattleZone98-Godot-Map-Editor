extends RefCounted
class_name BzLayout
## Layout graph used by the Tier 2 validators (port of model/layout.py).
##
## Only the construction + path APIs that the Tier 2 validators import.
## Generator-only graph rules (LayoutGraph.validate / RuleResult /
## LayoutReport) are out of scope.
##
## Python `Node` is `BzLayout.LayoutNode` here — Godot already owns `Node`.

const BASE := "base"
const GEYSER := "geyser"
const SCRAP := "scrap"
const SPAWN := "spawn"

## Rule B2: nearest-base separation as a fraction of the map diagonal.
const B2_MIN_FRAC := 0.35
const B2_MAX_FRAC := 0.60

## Rule E4: maximum allowed per-base economy spread (fraction of the mean).
const E4_MAX_SPREAD := 0.05

## Rule E5: contested geysers must be this fraction of all geysers.
const E5_MIN_FRAC := 0.30
const E5_MAX_FRAC := 0.50

## Rule E5: a geyser is contested when its two nearest bases are within this
## relative path-distance gap.
const E5_GAP := 0.15

## Rule B3: deathmatch/_SW spawn count.
const SW_SPAWN_COUNT := 14


class LayoutNode:
	extends RefCounted
	## A single node in the layout graph. `x`/`z` are world metres.

	var id: String = ""
	var x: float = 0.0
	var z: float = 0.0
	var kind: String = ""
	var team: int = -1

	func _init(
		p_id: String = "",
		p_x: float = 0.0,
		p_z: float = 0.0,
		p_kind: String = "",
		p_team: int = -1
	) -> void:
		id = p_id
		x = float(p_x)
		z = float(p_z)
		kind = p_kind
		team = int(p_team)


var width_m: float = 0.0
var depth_m: float = 0.0
var n_teams: int = 2
var _nodes: Dictionary = {}
## Undirected edges: sorted-id key -> path length in metres.
var _edges: Dictionary = {}


func _init(p_width_m: float = 0.0, p_depth_m: float = 0.0, p_n_teams: int = 2) -> void:
	width_m = float(p_width_m)
	depth_m = float(p_depth_m)
	n_teams = int(p_n_teams)


func add_node(id: String, x: float, z: float, kind: String, team: int = -1) -> LayoutNode:
	## Add a node, replacing any existing node with the same id.
	var node := LayoutNode.new(id, x, z, kind, team)
	_nodes[id] = node
	return node


func add_route(a: String, b: String, length: Variant = null) -> float:
	## Add an undirected route. `length` omitted → straight-line distance.
	## Python raises KeyError on unknown nodes; we return NAN (no exceptions).
	if not _nodes.has(a) or not _nodes.has(b):
		return NAN
	var stored: float
	if length == null:
		var na: LayoutNode = _nodes[a]
		var nb: LayoutNode = _nodes[b]
		var dx: float = na.x - nb.x
		var dz: float = na.z - nb.z
		stored = sqrt(dx * dx + dz * dz)
	else:
		stored = float(length)
	_edges[_edge_key(a, b)] = stored
	return stored


func nodes() -> Dictionary:
	## Copy of id -> LayoutNode (Python `LayoutGraph.nodes` property).
	return _nodes.duplicate()


func base_ids() -> Array:
	var out: Array = []
	for id in _nodes.keys():
		var n: LayoutNode = _nodes[id]
		if n.kind == BASE:
			out.append(n.id)
	return out


func economy_ids() -> Array:
	var out: Array = []
	for id in _nodes.keys():
		var n: LayoutNode = _nodes[id]
		if n.kind == GEYSER or n.kind == SCRAP:
			out.append(n.id)
	return out


func geyser_ids() -> Array:
	var out: Array = []
	for id in _nodes.keys():
		var n: LayoutNode = _nodes[id]
		if n.kind == GEYSER:
			out.append(n.id)
	return out


func diagonal_m() -> float:
	return sqrt(width_m * width_m + depth_m * depth_m)


func neighbours(node: String) -> Array:
	## `[ [neighbour_id, edge_length], ... ]` for `node`.
	var out: Array = []
	for key in _edges.keys():
		var parts: PackedStringArray = str(key).split("\t", false)
		if parts.size() != 2:
			continue
		var a: String = parts[0]
		var b: String = parts[1]
		var length: float = float(_edges[key])
		if a == node:
			out.append([b, length])
		elif b == node:
			out.append([a, length])
	return out


func path_distance(start: String, goal: String) -> Variant:
	## Shortest path length (Dijkstra), or null when no route connects them.
	## Python raises KeyError on unknown endpoints; we return null.
	if not _nodes.has(start) or not _nodes.has(goal):
		return null
	if start == goal:
		return 0.0
	var dist: Dictionary = {start: 0.0}
	var heap := _MinHeap.new()
	heap.push(0.0, start)
	while not heap.is_empty():
		var popped: Array = heap.pop()
		var d: float = float(popped[0])
		var cur: String = str(popped[1])
		if cur == goal:
			return d
		if d > float(dist.get(cur, INF)):
			continue
		for pair in neighbours(cur):
			var nxt: String = str(pair[0])
			var nd: float = d + float(pair[1])
			if nd < float(dist.get(nxt, INF)):
				dist[nxt] = nd
				heap.push(nd, nxt)
	return null


func nearest_base(node_id: String) -> Variant:
	## `[base_id, path_distance]` of the nearest reachable base, or null.
	var dists: Array = []
	for bid in base_ids():
		var d: Variant = path_distance(node_id, str(bid))
		if d != null:
			dists.append([bid, float(d)])
	if dists.is_empty():
		return null
	var best: Array = dists[0]
	for item in dists:
		if float(item[1]) < float(best[1]):
			best = item
	return best


func _nearest_bases(node_id: String) -> Array:
	## All reachable bases sorted by path distance (stable on ties).
	var dists: Array = []
	for bid in base_ids():
		var d: Variant = path_distance(node_id, str(bid))
		if d != null:
			dists.append([bid, float(d)])
	dists.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	return dists


func _edge_key(a: String, b: String) -> String:
	if a < b:
		return a + "\t" + b
	return b + "\t" + a


class _MinHeap:
	extends RefCounted
	## Binary heap of (distance, node_id). Ties break on id like heapq tuples.

	var _keys: PackedFloat64Array = PackedFloat64Array()
	var _ids: PackedStringArray = PackedStringArray()

	func is_empty() -> bool:
		return _keys.is_empty()

	func push(key: float, id: String) -> void:
		_keys.append(key)
		_ids.append(id)
		_sift_up(_keys.size() - 1)

	func pop() -> Array:
		var k: float = _keys[0]
		var i: String = _ids[0]
		var last: int = _keys.size() - 1
		if last == 0:
			_keys.clear()
			_ids.clear()
			return [k, i]
		_keys[0] = _keys[last]
		_ids[0] = _ids[last]
		_keys.resize(last)
		_ids.resize(last)
		_sift_down(0)
		return [k, i]

	func _less(ia: int, ib: int) -> bool:
		if _keys[ia] < _keys[ib]:
			return true
		if _keys[ia] > _keys[ib]:
			return false
		return _ids[ia] < _ids[ib]

	func _sift_up(i: int) -> void:
		while i > 0:
			var p: int = (i - 1) / 2
			if not _less(i, p):
				break
			_swap(i, p)
			i = p

	func _sift_down(i: int) -> void:
		var n: int = _keys.size()
		while true:
			var l: int = i * 2 + 1
			var r: int = l + 1
			var smallest: int = i
			if l < n and _less(l, smallest):
				smallest = l
			if r < n and _less(r, smallest):
				smallest = r
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest

	func _swap(a: int, b: int) -> void:
		var tk: float = _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = tk
		var ti: String = _ids[a]
		_ids[a] = _ids[b]
		_ids[b] = ti
