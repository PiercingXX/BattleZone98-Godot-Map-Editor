extends RefCounted
class_name BzCheckBalance
## Tier 2 balance validation — rules E4-E5, B1-B3 (port of validate/balance.py).

## Rule E3/B1: slope ceiling (metres-per-metre) for buildable ground (tan 5°).
const BUILDABLE_SLOPE := 0.08748866352592401

## Rule B1: minimum contiguous buildable pocket area (m²) per base.
const B1_MIN_POCKET_M2 := 4000.0

## Rule B3: spawn spacing bounds (metres) within a cluster, corpus range.
const B3_MIN_SPACING_M := 12.0
const B3_MAX_SPACING_M := 70.0

const ERROR := "[error]"
const WARNING := "[warning]"


var heightmap: BzHg2.HeightMap = null
var layout: BzLayout = null
var spawns: Array = []


func _init(
	p_heightmap: Variant = null, p_layout: BzLayout = null, p_spawns: Variant = null
) -> void:
	layout = p_layout
	if p_heightmap != null:
		heightmap = BzCheckTerrain._coerce_heightmap(p_heightmap)
	if p_spawns == null:
		if layout != null:
			var nodes: Dictionary = layout.nodes()
			for nid in nodes.keys():
				var n: BzLayout.LayoutNode = nodes[nid]
				if n.kind == BzLayout.SPAWN:
					spawns.append(n)
	else:
		for s in p_spawns:
			spawns.append(s)


func measure() -> Dictionary:
	## Raw measured values (docs/06 §Reporting), not just verdicts.
	var empty_totals := {}
	if layout == null or heightmap == null:
		return {
			"per_base_economy": empty_totals,
			"e4_spread": 0.0,
			"e5_contested_frac": 0.0,
			"base_pocket_m2": {},
			"nearest_base_m": null,
			"b2_separation_frac": 0.0,
			"spawn_count": spawns.size(),
			"spawn_cluster_count": 0,
			"min_cluster_spacing_m": 0.0,
			"max_cluster_spacing_m": 0.0,
		}
	var buildable: PackedByteArray = BzHg2.buildable_mask(heightmap, BUILDABLE_SLOPE)
	var gx: int = heightmap.grid_x
	var gz: int = heightmap.grid_z

	var totals: Dictionary = {}
	for bid in layout.base_ids():
		totals[str(bid)] = 0
	for nid in layout.economy_ids():
		var nearest: Variant = layout.nearest_base(str(nid))
		if nearest != null:
			var bid: String = str(nearest[0])
			totals[bid] = int(totals.get(bid, 0)) + 1
	var values: Array = []
	for bid in totals.keys():
		values.append(int(totals[bid]))
	var mean := 0.0
	if not values.is_empty():
		var acc := 0
		for v in values:
			acc += int(v)
		mean = float(acc) / float(values.size())
	var e4_spread := 0.0
	if mean != 0.0:
		var vmax: int = int(values[0])
		var vmin: int = int(values[0])
		for v in values:
			vmax = maxi(vmax, int(v))
			vmin = mini(vmin, int(v))
		e4_spread = float(vmax - vmin) / mean

	var geysers: Array = layout.geyser_ids()
	var contested := 0
	for gid in geysers:
		var nearest: Array = layout._nearest_bases(str(gid))
		if nearest.size() < 2:
			continue
		var d1: float = float(nearest[0][1])
		var d2: float = float(nearest[1][1])
		if d1 > 0.0 and (d2 - d1) / d1 <= BzLayout.E5_GAP:
			contested += 1
	var e5_frac := 0.0
	if not geysers.is_empty():
		e5_frac = float(contested) / float(geysers.size())

	var pocket_areas: Dictionary = {}
	var nodes: Dictionary = layout.nodes()
	for bid in layout.base_ids():
		var base: BzLayout.LayoutNode = nodes[str(bid)]
		pocket_areas[str(bid)] = _buildable_component_area(
			buildable, gx, gz, _cell_of(base.x, base.z)
		)

	var base_ids: Array = layout.base_ids()
	var nearest_dist: Variant = null
	for i in base_ids.size():
		for j in range(i + 1, base_ids.size()):
			var d: Variant = layout.path_distance(str(base_ids[i]), str(base_ids[j]))
			if d != null and (nearest_dist == null or float(d) < float(nearest_dist)):
				nearest_dist = float(d)
	var diag: float = layout.diagonal_m()
	var b2_frac := 0.0
	if nearest_dist != null and diag != 0.0:
		b2_frac = float(nearest_dist) / diag

	var spawn_count: int = spawns.size()
	var clusters: Dictionary = {}
	for s in spawns:
		var team: int = _spawn_team(s)
		if not clusters.has(team):
			clusters[team] = []
		var members: Array = clusters[team]
		members.append(s)
		clusters[team] = members
	var cluster_count := 0
	for team in clusters.keys():
		var members: Array = clusters[team]
		if not members.is_empty():
			cluster_count += 1
	var nearest_gaps: Array = []
	for team in clusters.keys():
		var members: Array = clusters[team]
		if members.size() < 2:
			continue
		for i in members.size():
			var ax: float = _spawn_x(members[i])
			var az: float = _spawn_z(members[i])
			var gap := INF
			for j in members.size():
				if j == i:
					continue
				var dx: float = ax - _spawn_x(members[j])
				var dz: float = az - _spawn_z(members[j])
				var g: float = sqrt(dx * dx + dz * dz)
				if g < gap:
					gap = g
			nearest_gaps.append(gap)
	var min_spacing := 0.0
	var max_spacing := 0.0
	if not nearest_gaps.is_empty():
		min_spacing = float(nearest_gaps[0])
		max_spacing = float(nearest_gaps[0])
		for g in nearest_gaps:
			min_spacing = minf(min_spacing, float(g))
			max_spacing = maxf(max_spacing, float(g))

	return {
		"per_base_economy": totals,
		"e4_spread": e4_spread,
		"e5_contested_frac": e5_frac,
		"base_pocket_m2": pocket_areas,
		"nearest_base_m": nearest_dist,
		"b2_separation_frac": b2_frac,
		"spawn_count": spawn_count,
		"spawn_cluster_count": cluster_count,
		"min_cluster_spacing_m": min_spacing,
		"max_cluster_spacing_m": max_spacing,
	}


func validate() -> PackedStringArray:
	var m: Dictionary = measure()
	var problems := PackedStringArray()
	problems.append_array(_check_e4(m))
	problems.append_array(_check_e5(m))
	problems.append_array(_check_b1(m))
	problems.append_array(_check_b2(m))
	problems.append_array(_check_b3(m))
	return problems


func _check_e4(m: Dictionary) -> PackedStringArray:
	var totals: Dictionary = m["per_base_economy"]
	if totals.size() < 2:
		return PackedStringArray([
			"%s E4: need at least two bases to compare per-base economy" % ERROR
		])
	var total := 0
	for k in totals.keys():
		total += int(totals[k])
	if total == 0:
		return PackedStringArray([
			"%s E4: no economy nodes assigned to any base" % ERROR
		])
	var spread: float = float(m["e4_spread"])
	if spread > BzLayout.E4_MAX_SPREAD:
		return PackedStringArray([
			"%s E4: per-base economy spread %s exceeds %s: %s"
			% [ERROR, _fmt_pct(spread, 1), _fmt_pct(BzLayout.E4_MAX_SPREAD, 0), _py_int_dict(totals)]
		])
	return PackedStringArray()


func _check_e5(m: Dictionary) -> PackedStringArray:
	var frac: float = float(m["e5_contested_frac"])
	if not (BzLayout.E5_MIN_FRAC <= frac and frac <= BzLayout.E5_MAX_FRAC):
		return PackedStringArray([
			"%s E5: contested geysers %s; want %s-%s"
			% [
				WARNING,
				_fmt_pct(frac, 0),
				_fmt_pct(BzLayout.E5_MIN_FRAC, 0),
				_fmt_pct(BzLayout.E5_MAX_FRAC, 0),
			]
		])
	return PackedStringArray()


func _check_b1(m: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var pockets: Dictionary = m["base_pocket_m2"]
	for bid in pockets.keys():
		var area: float = float(pockets[bid])
		if area < B1_MIN_POCKET_M2:
			problems.append(
				"%s B1: base %s buildable pocket only %.0f m²; need at least %.0f m² under 5° slope"
				% [ERROR, str(bid), area, B1_MIN_POCKET_M2]
			)
	return problems


func _check_b2(m: Dictionary) -> PackedStringArray:
	var frac: float = float(m["b2_separation_frac"])
	if not (BzLayout.B2_MIN_FRAC <= frac and frac <= BzLayout.B2_MAX_FRAC):
		return PackedStringArray([
			"%s B2: nearest-base separation %s of diagonal; want %s-%s"
			% [
				WARNING,
				_fmt_pct(frac, 2),
				_fmt_pct(BzLayout.B2_MIN_FRAC, 0),
				_fmt_pct(BzLayout.B2_MAX_FRAC, 0),
			]
		])
	return PackedStringArray()


func _check_b3(m: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var count: int = int(m["spawn_count"])
	if count != BzLayout.SW_SPAWN_COUNT:
		problems.append(
			"%s B3: deathmatch/_SW needs %d spawns, got %d"
			% [ERROR, BzLayout.SW_SPAWN_COUNT, count]
		)
	var teams: int = 0 if layout == null else layout.n_teams
	if int(m["spawn_cluster_count"]) != teams:
		problems.append(
			"%s B3: spawns must form %d team clusters, got %d"
			% [ERROR, teams, int(m["spawn_cluster_count"])]
		)
	if float(m["min_cluster_spacing_m"]) < B3_MIN_SPACING_M:
		problems.append(
			"%s B3: spawns as close as %.0f m; want at least %.0f m apart"
			% [ERROR, float(m["min_cluster_spacing_m"]), B3_MIN_SPACING_M]
		)
	if float(m["max_cluster_spacing_m"]) > B3_MAX_SPACING_M:
		problems.append(
			"%s B3: spawns as far as %.0f m; want at most %.0f m apart"
			% [ERROR, float(m["max_cluster_spacing_m"]), B3_MAX_SPACING_M]
		)
	return problems


static func validate_balance(
	heightmap: Variant, layout: BzLayout, spawns: Variant = null
) -> PackedStringArray:
	return BzCheckBalance.new(heightmap, layout, spawns).validate()


static func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(round(z / BzHg2.GRID_M)), int(round(x / BzHg2.GRID_M)))


static func _buildable_component_area(
	buildable: PackedByteArray, gx: int, gz: int, start: Vector2i
) -> float:
	## Area (m²) of the 4-connected buildable component containing start.
	## Off-grid start returns 0 (Python would IndexError; flagged in summary).
	if start.x < 0 or start.x >= gz or start.y < 0 or start.y >= gx:
		return 0.0
	if buildable[start.x * gx + start.y] == 0:
		return 0.0
	var visited := PackedByteArray()
	visited.resize(buildable.size())
	var qz := PackedInt32Array()
	var qx := PackedInt32Array()
	qz.append(start.x)
	qx.append(start.y)
	visited[start.x * gx + start.y] = 1
	var count := 0
	var head := 0
	while head < qz.size():
		var z: int = qz[head]
		var x: int = qx[head]
		head += 1
		count += 1
		for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
			var nz: int = z + int(d[0])
			var nx: int = x + int(d[1])
			if nz < 0 or nz >= gz or nx < 0 or nx >= gx:
				continue
			var ni: int = nz * gx + nx
			if buildable[ni] != 0 and visited[ni] == 0:
				visited[ni] = 1
				qz.append(nz)
				qx.append(nx)
	return float(count) * BzHg2.GRID_M * BzHg2.GRID_M


static func _spawn_x(s: Variant) -> float:
	if s is Dictionary:
		return float((s as Dictionary).get("x", 0.0))
	return float(s.x)


static func _spawn_z(s: Variant) -> float:
	if s is Dictionary:
		return float((s as Dictionary).get("z", 0.0))
	return float(s.z)


static func _spawn_team(s: Variant) -> int:
	if s is Dictionary:
		return int((s as Dictionary).get("team", -1))
	if s is Object and s.get("team") != null:
		return int(s.team)
	return -1


static func _fmt_pct(frac: float, decimals: int) -> String:
	## Python `{frac:.Nf%}` — multiply by 100 and append `%`.
	var v: float = frac * 100.0
	if decimals <= 0:
		return "%d%%" % int(round(v))
	if decimals == 1:
		return "%.1f%%" % v
	return "%.2f%%" % v


static func _py_int_dict(d: Dictionary) -> String:
	## Python dict repr with single-quoted string keys.
	var parts := PackedStringArray()
	for k in d.keys():
		parts.append("'%s': %d" % [str(k), int(d[k])])
	return "{" + ", ".join(parts) + "}"
