extends RefCounted
class_name BzCheckConnectivity
## Tier 2 connectivity validation — rules C1-C4 (port of validate/connectivity.py).

## 30° slope in metres-per-metre (tan 30°). Rule C1/C2 traversable threshold.
const SLOPE_30_DEG := 0.5773502691896257

## Rule C2 — disconnected traversable pocket larger than this (m²) is a trap.
## Retained for the measured values; the check itself warns at C2_WARN_AREA_M2.
const C2_MAX_TRAP_AREA_M2 := 200.0

## C2 warning threshold — the corpus p99 pocket size (measured 2026-08-11).
const C2_WARN_AREA_M2 := 5000.0

## Rule C3 — corridor width (m) deleted around the shortest path before re-search.
const C3_CORRIDOR_WIDTH_M := 30.0

## Rule C4 — a main-route corridor narrower than this (m) is a warning.
const C4_MIN_WIDTH_M := 30.0

const ERROR := "[error]"
const WARNING := "[warning]"

## Node kinds that must be reachable from every base (Rule C1).
const _REACHABLE_KINDS := {
	BzLayout.BASE: true,
	BzLayout.GEYSER: true,
	BzLayout.SCRAP: true,
}


var heightmap: BzHg2.HeightMap = null
var layout: BzLayout = null


func _init(p_heightmap: Variant = null, p_layout: BzLayout = null) -> void:
	layout = p_layout
	if p_heightmap != null:
		heightmap = BzCheckTerrain._coerce_heightmap(p_heightmap)


func measure() -> Dictionary:
	## Raw measured values (docs/06 §Reporting), not just verdicts.
	var empty := {
		"traversable_pct": 0.0,
		"unreachable_economy": [],
		"trap_areas_m2": [],
		"single_corridor_pairs": [],
		"min_corridor_width_m": null,
	}
	if heightmap == null or layout == null:
		return empty
	var hm: BzHg2.HeightMap = heightmap
	var gx: int = hm.grid_x
	var gz: int = hm.grid_z
	var mask: PackedByteArray = _traversable_mask(hm)
	var n: int = mask.size()
	var trav := 0
	for i in n:
		if mask[i] != 0:
			trav += 1
	var labels: PackedInt32Array = _components(mask, gx, gz)
	var nodes: Dictionary = layout.nodes()
	var base_cells: Dictionary = {}
	for nid in nodes.keys():
		var node: BzLayout.LayoutNode = nodes[nid]
		if node.kind == BzLayout.BASE:
			base_cells[node.id] = _cell_of(node.x, node.z)
	var base_labels: Dictionary = {}
	for bid in base_cells.keys():
		var cell: Vector2i = base_cells[bid]
		var lab: int = _label_at(labels, gx, gz, cell)
		if lab != 0:
			base_labels[lab] = true

	var unreachable: Array = []
	if base_labels.is_empty():
		for nid in nodes.keys():
			var node: BzLayout.LayoutNode = nodes[nid]
			if _REACHABLE_KINDS.has(node.kind):
				unreachable.append(node.id)
	elif base_labels.size() > 1:
		for nid in nodes.keys():
			var node: BzLayout.LayoutNode = nodes[nid]
			if _REACHABLE_KINDS.has(node.kind):
				unreachable.append(node.id)
	else:
		var reachable_label: int = int(base_labels.keys()[0])
		for nid in nodes.keys():
			var node: BzLayout.LayoutNode = nodes[nid]
			if not _REACHABLE_KINDS.has(node.kind):
				continue
			if _label_at(labels, gx, gz, _cell_of(node.x, node.z)) != reachable_label:
				unreachable.append(node.id)
	unreachable.sort()

	var max_label := 0
	for i in labels.size():
		if labels[i] > max_label:
			max_label = labels[i]
	var trap_areas: Array = []
	for label in range(1, max_label + 1):
		if base_labels.has(label):
			continue
		var area_cells := 0
		for i in labels.size():
			if labels[i] == label:
				area_cells += 1
		var area_m2: float = float(area_cells) * BzHg2.GRID_M * BzHg2.GRID_M
		if area_m2 > C2_MAX_TRAP_AREA_M2:
			trap_areas.append(area_m2)
	trap_areas.sort()

	var single_corridor: Array = []
	var min_width_m: float = INF
	var bids: Array = layout.base_ids()
	for i in bids.size():
		for j in range(i + 1, bids.size()):
			var a: String = str(bids[i])
			var b: String = str(bids[j])
			var na: BzLayout.LayoutNode = nodes[a]
			var nb: BzLayout.LayoutNode = nodes[b]
			var start: Vector2i = _cell_of(na.x, na.z)
			var goal: Vector2i = _cell_of(nb.x, nb.z)
			if not _in_grid(gx, gz, start) or not _in_grid(gx, gz, goal):
				single_corridor.append([a, b])
				continue
			var path: Array = _astar(mask, gx, gz, start, goal)
			if path.is_empty():
				single_corridor.append([a, b])
				continue
			var radius: int = int(round(C3_CORRIDOR_WIDTH_M / 2.0 / BzHg2.GRID_M))
			var blocked: PackedByteArray = mask.duplicate()
			var removed: PackedByteArray = _dilate(path, radius, gx, gz)
			for ci in removed.size():
				if removed[ci] != 0:
					blocked[ci] = 0
			var start_buf: PackedByteArray = _dilate([start], radius, gx, gz)
			for ci in start_buf.size():
				if start_buf[ci] != 0:
					blocked[ci] = 1
			var goal_buf: PackedByteArray = _dilate([goal], radius, gx, gz)
			for ci in goal_buf.size():
				if goal_buf[ci] != 0:
					blocked[ci] = 1
			if _astar(blocked, gx, gz, start, goal).is_empty():
				single_corridor.append([a, b])
			var dist: PackedInt32Array = _distance_to_wall(mask, gx, gz)
			for cell_v in path:
				var cell: Vector2i = cell_v
				var d: int = dist[cell.x * gx + cell.y]
				# cell stored as Vector2i(z, x) — see _cell_of / _astar.
				d = dist[cell.x * gx + cell.y]
				if d < 0:
					continue
				var w: float = float(maxi(0, d - 1)) * 2.0 * BzHg2.GRID_M
				if w < min_width_m:
					min_width_m = w

	return {
		"traversable_pct": (float(trav) / float(n)) * 100.0 if n > 0 else 0.0,
		"unreachable_economy": unreachable,
		"trap_areas_m2": trap_areas,
		"single_corridor_pairs": single_corridor,
		"min_corridor_width_m": null if min_width_m == INF else min_width_m,
	}


func validate() -> PackedStringArray:
	var m: Dictionary = measure()
	var problems := PackedStringArray()
	problems.append_array(_check_c1(m))
	problems.append_array(_check_c2(m))
	problems.append_array(_check_c3(m))
	problems.append_array(_check_c4(m))
	return problems


func _check_c1(m: Dictionary) -> PackedStringArray:
	var ids: Array = m["unreachable_economy"]
	if not ids.is_empty():
		return PackedStringArray([
			"%s C1: economy nodes unreachable from every base by a ≤30° ground path: %s"
			% [ERROR, _py_str_list(ids)]
		])
	return PackedStringArray()


func _check_c2(m: Dictionary) -> PackedStringArray:
	var big: Array = []
	for a in m["trap_areas_m2"]:
		if float(a) > C2_WARN_AREA_M2:
			big.append(float(a))
	if not big.is_empty():
		var largest := float(big[0])
		for a in big:
			if float(a) > largest:
				largest = float(a)
		return PackedStringArray([
			"%s C2: %d disconnected traversable pocket(s) > %.0f m² (largest %.0f m²) — corpus-normal on rugged worlds, review that no intended play space is cut off"
			% [WARNING, big.size(), C2_WARN_AREA_M2, largest]
		])
	return PackedStringArray()


func _check_c3(m: Dictionary) -> PackedStringArray:
	var pairs: Array = m["single_corridor_pairs"]
	if not pairs.is_empty():
		return PackedStringArray([
			"%s C3: single corridor between base pair(s) %s (no second route after removing a %.0f m-wide corridor)"
			% [ERROR, _py_pair_list(pairs), C3_CORRIDOR_WIDTH_M]
		])
	return PackedStringArray()


func _check_c4(m: Dictionary) -> PackedStringArray:
	var w: Variant = m["min_corridor_width_m"]
	if w != null and float(w) < C4_MIN_WIDTH_M:
		return PackedStringArray([
			"%s C4: main-route corridor as narrow as %.0f m; want at least %.0f m"
			% [WARNING, float(w), C4_MIN_WIDTH_M]
		])
	return PackedStringArray()


static func validate_connectivity(heightmap: Variant, layout: BzLayout) -> PackedStringArray:
	return BzCheckConnectivity.new(heightmap, layout).validate()


static func _cell_of(x: float, z: float) -> Vector2i:
	## Grid cell stored as Vector2i(z, x) to match Python `(z, x)`.
	return Vector2i(int(round(z / BzHg2.GRID_M)), int(round(x / BzHg2.GRID_M)))


static func _in_grid(gx: int, gz: int, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < gz and cell.y >= 0 and cell.y < gx


static func _label_at(labels: PackedInt32Array, gx: int, gz: int, cell: Vector2i) -> int:
	if cell.x >= 0 and cell.x < gz and cell.y >= 0 and cell.y < gx:
		return int(labels[cell.x * gx + cell.y])
	return 0


static func _traversable_mask(hm: BzHg2.HeightMap) -> PackedByteArray:
	var s: PackedFloat64Array = BzHg2.slope(hm)
	var out := PackedByteArray()
	out.resize(s.size())
	for i in s.size():
		out[i] = 1 if s[i] <= SLOPE_30_DEG else 0
	return out


static func _components(mask: PackedByteArray, gx: int, gz: int) -> PackedInt32Array:
	var labels := PackedInt32Array()
	labels.resize(mask.size())
	var label := 0
	var qz := PackedInt32Array()
	var qx := PackedInt32Array()
	for z0 in gz:
		for x0 in gx:
			var start: int = z0 * gx + x0
			if mask[start] == 0 or labels[start] != 0:
				continue
			label += 1
			qz.clear()
			qx.clear()
			qz.append(z0)
			qx.append(x0)
			labels[start] = label
			var head := 0
			while head < qz.size():
				var z: int = qz[head]
				var x: int = qx[head]
				head += 1
				for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
					var nz: int = z + int(d[0])
					var nx: int = x + int(d[1])
					if nz < 0 or nz >= gz or nx < 0 or nx >= gx:
						continue
					var ni: int = nz * gx + nx
					if mask[ni] != 0 and labels[ni] == 0:
						labels[ni] = label
						qz.append(nz)
						qx.append(nx)
	return labels


static func _astar(
	mask: PackedByteArray, gx: int, gz: int, start: Vector2i, goal: Vector2i
) -> Array:
	## Shortest 4-connected path. Empty array = no path (Python None).
	if not _in_grid(gx, gz, start) or not _in_grid(gx, gz, goal):
		return []
	if mask[start.x * gx + start.y] == 0 or mask[goal.x * gx + goal.y] == 0:
		return []
	if start == goal:
		return [start]
	var heap := _AStarHeap.new()
	var g_score: Dictionary = {}
	var prev: Dictionary = {}
	var start_k: int = start.x * gx + start.y
	var goal_k: int = goal.x * gx + goal.y
	g_score[start_k] = 0
	heap.push(0, 0, start.x, start.y)
	var counter := 1
	while not heap.is_empty():
		var cur: Vector4i = heap.pop()
		var cz: int = cur.z
		var cx: int = cur.w
		var ck: int = cz * gx + cx
		if ck == goal_k:
			break
		for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
			var nz: int = cz + int(d[0])
			var nx: int = cx + int(d[1])
			if nz < 0 or nz >= gz or nx < 0 or nx >= gx:
				continue
			var nk: int = nz * gx + nx
			if mask[nk] == 0:
				continue
			var tentative: int = int(g_score[ck]) + 1
			if tentative < int(g_score.get(nk, 0x7fffffff)):
				g_score[nk] = tentative
				prev[nk] = ck
				var f: int = tentative + absi(nz - goal.x) + absi(nx - goal.y)
				heap.push(f, counter, nz, nx)
				counter += 1
	if not g_score.has(goal_k):
		return []
	var path: Array = []
	var walk: int = goal_k
	while true:
		path.append(Vector2i(walk / gx, walk % gx))
		if walk == start_k:
			break
		walk = int(prev[walk])
	path.reverse()
	return path


static func _dilate(path: Array, radius_cells: int, gx: int, gz: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(gx * gz)
	for cell_v in path:
		var cell: Vector2i = cell_v
		for dz in range(-radius_cells, radius_cells + 1):
			for dx in range(-radius_cells, radius_cells + 1):
				var nz: int = cell.x + dz
				var nx: int = cell.y + dx
				if nz >= 0 and nz < gz and nx >= 0 and nx < gx:
					out[nz * gx + nx] = 1
	return out


static func _distance_to_wall(mask: PackedByteArray, gx: int, gz: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(mask.size())
	dist.fill(-1)
	var qz := PackedInt32Array()
	var qx := PackedInt32Array()
	for z in gz:
		for x in gx:
			if mask[z * gx + x] == 0:
				dist[z * gx + x] = 0
				qz.append(z)
				qx.append(x)
	var head := 0
	while head < qz.size():
		var z: int = qz[head]
		var x: int = qx[head]
		head += 1
		for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
			var nz: int = z + int(d[0])
			var nx: int = x + int(d[1])
			if nz < 0 or nz >= gz or nx < 0 or nx >= gx:
				continue
			var ni: int = nz * gx + nx
			if dist[ni] < 0:
				dist[ni] = dist[z * gx + x] + 1
				qz.append(nz)
				qx.append(nx)
	return dist


static func _py_str_list(ids: Array) -> String:
	var parts := PackedStringArray()
	for id in ids:
		parts.append("'%s'" % str(id))
	return "[" + ", ".join(parts) + "]"


static func _py_pair_list(pairs: Array) -> String:
	var parts := PackedStringArray()
	for p in pairs:
		parts.append("('%s', '%s')" % [str(p[0]), str(p[1])])
	return "[" + ", ".join(parts) + "]"


class _AStarHeap:
	extends RefCounted
	## Min-heap of (f, counter, z, x).

	var _f: PackedInt32Array = PackedInt32Array()
	var _c: PackedInt32Array = PackedInt32Array()
	var _z: PackedInt32Array = PackedInt32Array()
	var _x: PackedInt32Array = PackedInt32Array()

	func is_empty() -> bool:
		return _f.is_empty()

	func push(f: int, c: int, z: int, x: int) -> void:
		_f.append(f)
		_c.append(c)
		_z.append(z)
		_x.append(x)
		_sift_up(_f.size() - 1)

	func pop() -> Vector4i:
		var out := Vector4i(_f[0], _c[0], _z[0], _x[0])
		var last: int = _f.size() - 1
		if last == 0:
			_f.clear()
			_c.clear()
			_z.clear()
			_x.clear()
			return out
		_f[0] = _f[last]
		_c[0] = _c[last]
		_z[0] = _z[last]
		_x[0] = _x[last]
		_f.resize(last)
		_c.resize(last)
		_z.resize(last)
		_x.resize(last)
		_sift_down(0)
		return out

	func _less(ia: int, ib: int) -> bool:
		if _f[ia] != _f[ib]:
			return _f[ia] < _f[ib]
		return _c[ia] < _c[ib]

	func _sift_up(i: int) -> void:
		while i > 0:
			var p: int = (i - 1) / 2
			if not _less(i, p):
				break
			_swap(i, p)
			i = p

	func _sift_down(i: int) -> void:
		var n: int = _f.size()
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
		var tf: int = _f[a]
		_f[a] = _f[b]
		_f[b] = tf
		var tc: int = _c[a]
		_c[a] = _c[b]
		_c[b] = tc
		var tz: int = _z[a]
		_z[a] = _z[b]
		_z[b] = tz
		var tx: int = _x[a]
		_x[a] = _x[b]
		_x[b] = tx
