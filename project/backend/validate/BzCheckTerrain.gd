extends RefCounted
class_name BzCheckTerrain
## Tier 2 terrain validation — rules T1-T4 (port of validate/terrain.py).

## 5° slope in metres-per-metre (tan 5°). Rule T1 flat threshold.
const SLOPE_5_DEG := 0.08748866352592401

## 45° slope in metres-per-metre (tan 45°). Rule T4 impassable ring threshold.
const SLOPE_45_DEG := 0.9999999999999999

## Rule T1 — minimum fraction of the map that must be under 5° slope.
const T1_MIN_FLAT_FRACTION := 0.175

## Rule T2 — modal raw height must lie in this inclusive range.
const T2_MODAL_MIN := 500
const T2_MODAL_MAX := 1500

## Rule T3 — 99th percentile raw height must stay below this ceiling.
const T3_P99_MAX := 3900

## Rule T4 — the outer boundary band (fraction of the map edge) must be
## impassable so players cannot drive off the heightmap.
const T4_BOUNDARY_FRACTION := 0.05

const ERROR := "[error]"
const WARNING := "[warning]"

## Sections a playable terrain config must carry beyond [Size].
const TRN_REQUIRED_SECTIONS := ["Color", "Sky", "Atlases"]


var heightmap: BzHg2.HeightMap = null


func _init(p_heightmap: Variant = null) -> void:
	if p_heightmap == null:
		return
	heightmap = _coerce_heightmap(p_heightmap)


static func _coerce_heightmap(heightmap: Variant) -> BzHg2.HeightMap:
	if heightmap is BzHg2.HeightMap:
		return heightmap
	if typeof(heightmap) == TYPE_STRING:
		var result: Dictionary = BzHg2.read_hg2(str(heightmap))
		if result.get("ok", false):
			return result["heightmap"]
		return null
	if typeof(heightmap) == TYPE_DICTIONARY:
		var d: Dictionary = heightmap
		if d.get("ok", false) and d.has("heightmap"):
			return d["heightmap"]
	return null


func measure() -> Dictionary:
	## Raw measured values (docs/06 §Reporting), not just verdicts.
	var hm: BzHg2.HeightMap = heightmap
	if hm == null:
		return {
			"flat_pct": 0.0,
			"flat_connected_pct": 0.0,
			"flat_distributed": false,
			"modal_raw": 0,
			"p99_raw": 0.0,
			"boundary_impassable": false,
		}
	var flat: PackedByteArray = _flat_mask(hm)
	var comp: PackedByteArray = _largest_component(flat, hm.grid_x, hm.grid_z)
	var n: int = flat.size()
	var flat_sum := 0
	var comp_sum := 0
	for i in n:
		if flat[i] != 0:
			flat_sum += 1
		if comp[i] != 0:
			comp_sum += 1
	return {
		"flat_pct": (float(flat_sum) / float(n)) * 100.0 if n > 0 else 0.0,
		"flat_connected_pct": (float(comp_sum) / float(n)) * 100.0 if n > 0 else 0.0,
		"flat_distributed": _flat_distributed(flat, hm.grid_x, hm.grid_z),
		"modal_raw": _modal_raw(hm),
		"p99_raw": _percentile(hm.data, 99.0),
		"boundary_impassable": _boundary_impassable(hm),
	}


func validate() -> PackedStringArray:
	var m: Dictionary = measure()
	var problems := PackedStringArray()
	problems.append_array(_check_t1(m))
	problems.append_array(_check_t2(m))
	problems.append_array(_check_t3(m))
	problems.append_array(_check_t4(m))
	return problems


func _check_t1(m: Dictionary) -> PackedStringArray:
	var flat_pct: float = float(m["flat_pct"])
	var problems := PackedStringArray()
	if flat_pct < T1_MIN_FLAT_FRACTION * 100.0:
		problems.append(
			"%s T1: only %.1f%% of map under 5° slope; need at least %.0f%%"
			% [ERROR, flat_pct, T1_MIN_FLAT_FRACTION * 100.0]
		)
	elif not bool(m["flat_distributed"]):
		problems.append(
			"%s T1: %.1f%% flat but the flat ground is not connected and distributed — it does not reach all quadrants"
			% [ERROR, flat_pct]
		)
	return problems


func _check_t2(m: Dictionary) -> PackedStringArray:
	var modal: int = int(m["modal_raw"])
	if not (T2_MODAL_MIN <= modal and modal <= T2_MODAL_MAX):
		return PackedStringArray([
			"%s T2: modal raw height %d outside %d-%d; build up from a mid-range plateau, not from 0"
			% [WARNING, modal, T2_MODAL_MIN, T2_MODAL_MAX]
		])
	return PackedStringArray()


func _check_t3(m: Dictionary) -> PackedStringArray:
	var p99: float = float(m["p99_raw"])
	if p99 >= float(T3_P99_MAX):
		return PackedStringArray([
			"%s T3: 99th percentile raw height %.0f at or above the %d saturation ceiling; clipping produces flat-topped mesas"
			% [ERROR, p99, T3_P99_MAX]
		])
	return PackedStringArray()


func _check_t4(m: Dictionary) -> PackedStringArray:
	if not bool(m["boundary_impassable"]):
		return PackedStringArray([
			"%s T4: the map edge is not ringed by impassable (>45°) terrain; players can drive off the heightmap"
			% ERROR
		])
	return PackedStringArray()


static func validate_terrain(heightmap: Variant) -> PackedStringArray:
	return BzCheckTerrain.new(heightmap).validate()


static func _modal_raw(hm: BzHg2.HeightMap) -> int:
	## Modal raw height via a histogram (numpy.bincount, minlength=4096).
	var data: PackedInt32Array = hm.data
	var max_v := 0
	for i in data.size():
		if data[i] > max_v:
			max_v = data[i]
	var ncounts: int = maxi(4096, max_v + 1)
	var counts := PackedInt32Array()
	counts.resize(ncounts)
	for i in data.size():
		var v: int = data[i]
		if v >= 0 and v < ncounts:
			counts[v] += 1
	var best := 0
	for i in ncounts:
		if counts[i] > counts[best]:
			best = i
	return best


static func _percentile(data: PackedInt32Array, q: float) -> float:
	## numpy.percentile(..., method='linear'): index = q/100 * (n-1).
	var n: int = data.size()
	if n == 0:
		return 0.0
	var sorted := data.duplicate()
	sorted.sort()
	var pos: float = (q / 100.0) * float(n - 1)
	var lo: int = int(floor(pos))
	var hi: int = int(ceil(pos))
	if lo < 0:
		lo = 0
	if hi >= n:
		hi = n - 1
	if lo == hi:
		return float(sorted[lo])
	var frac: float = pos - float(lo)
	return float(sorted[lo]) * (1.0 - frac) + float(sorted[hi]) * frac


static func _flat_mask(hm: BzHg2.HeightMap) -> PackedByteArray:
	var s: PackedFloat64Array = BzHg2.slope(hm)
	var out := PackedByteArray()
	out.resize(s.size())
	for i in s.size():
		out[i] = 1 if s[i] <= SLOPE_5_DEG else 0
	return out


static func _largest_component(mask: PackedByteArray, gx: int, gz: int) -> PackedByteArray:
	## Largest 4-connected component of `mask`. O(cells) flood fill.
	var best := PackedByteArray()
	best.resize(mask.size())
	var best_count := 0
	var visited := PackedByteArray()
	visited.resize(mask.size())
	var qz := PackedInt32Array()
	var qx := PackedInt32Array()
	for z0 in gz:
		for x0 in gx:
			var start: int = z0 * gx + x0
			if mask[start] == 0 or visited[start] != 0:
				continue
			qz.clear()
			qx.clear()
			qz.append(z0)
			qx.append(x0)
			visited[start] = 1
			var comp := PackedByteArray()
			comp.resize(mask.size())
			comp[start] = 1
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
					if mask[ni] != 0 and visited[ni] == 0:
						visited[ni] = 1
						comp[ni] = 1
						qz.append(nz)
						qx.append(nx)
			if count > best_count:
				best_count = count
				best = comp
	return best


static func _flat_distributed(flat: PackedByteArray, gx: int, gz: int) -> bool:
	var comp: PackedByteArray = _largest_component(flat, gx, gz)
	var mid_z: int = gz / 2
	var mid_x: int = gx / 2
	return (
		_quad_any(comp, gx, 0, mid_z, 0, mid_x)
		and _quad_any(comp, gx, 0, mid_z, mid_x, gx)
		and _quad_any(comp, gx, mid_z, gz, 0, mid_x)
		and _quad_any(comp, gx, mid_z, gz, mid_x, gx)
	)


static func _quad_any(
	comp: PackedByteArray, gx: int, z0: int, z1: int, x0: int, x1: int
) -> bool:
	for z in range(z0, z1):
		var row: int = z * gx
		for x in range(x0, x1):
			if comp[row + x] != 0:
				return true
	return false


static func _boundary_impassable(hm: BzHg2.HeightMap) -> bool:
	var gz: int = hm.grid_z
	var gx: int = hm.grid_x
	if gz < 1 or gx < 1:
		return false
	var b: int = maxi(1, int(round(T4_BOUNDARY_FRACTION * float(mini(gz, gx)))))
	var s: PackedFloat64Array = BzHg2.slope(hm)
	var sum := 0.0
	var n := 0
	for z in gz:
		for x in gx:
			if z < b or z >= gz - b or x < b or x >= gx - b:
				sum += s[z * gx + x]
				n += 1
	if n == 0:
		return false
	return (sum / float(n)) > SLOPE_45_DEG


static func check_trn_sufficiency(trn_path: String, mat_path: Variant = null) -> PackedStringArray:
	## Assert a `.trn` is complete enough to render a map.
	##
	## Section names are parsed locally (not via BzTrn.TerrainConfig) so this
	## checker does not depend on BzTrn.Section.get, which shadows Object.get.
	var problems := PackedStringArray()
	var path: String = "%s" % trn_path
	if not FileAccess.file_exists(path):
		problems.append("trn insufficiency: cannot read file")
		return problems
	var names: Dictionary = _trn_section_names(path)
	for required in TRN_REQUIRED_SECTIONS:
		if not names.has(required):
			problems.append("trn insufficiency: missing [%s] section" % required)
	var texture_types: Dictionary = {}
	for name in names.keys():
		if str(name).begins_with("TextureType"):
			texture_types[name] = true
	if texture_types.is_empty():
		problems.append("trn insufficiency: no [TextureType*] blocks at all")
	var mat: String = "" if mat_path == null else str(mat_path)
	if not mat.is_empty() and not texture_types.is_empty():
		if not FileAccess.file_exists(mat):
			problems.append("trn insufficiency: cannot read .MAT")
			return problems
		var raw: PackedByteArray = FileAccess.get_file_as_bytes(mat)
		var used: Dictionary = {}
		var i := 0
		while i + 1 < raw.size():
			var v: int = raw.decode_u16(i)
			used[v >> 12] = true
			i += 2
		var declared: Dictionary = {}
		for name in texture_types.keys():
			var suffix: String = str(name).substr("TextureType".length())
			if suffix.is_valid_int():
				declared[suffix.to_int()] = true
		var missing: Array = []
		for index in used.keys():
			if not declared.has(int(index)):
				missing.append(int(index))
		missing.sort()
		for index in missing:
			problems.append(
				"trn insufficiency: .MAT references material index %d but the .trn declares no [TextureType%d] block"
				% [int(index), int(index)]
			)
	return problems


static func _trn_section_names(path: String) -> Dictionary:
	## Names of `[Section]` headers. Matches trn.py: trailing text after `]`
	## is allowed (`[TextureType0] // Lava`).
	var names := {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.begins_with("\uFEFF"):
		text = text.substr(1)
	for raw in text.split("\n"):
		var stripped: String = raw.strip_edges()
		if stripped.is_empty() or stripped.begins_with(";") or stripped.begins_with("#"):
			continue
		if not stripped.begins_with("["):
			continue
		var close: int = stripped.find("]")
		if close > 0:
			names[stripped.substr(1, close - 1)] = true
	return names


static func des_size_band(width_m: float) -> String:
	## Canonical SIZE label — must agree with BzDes.size_band by construction.
	return BzDes.size_band(width_m)


static func check_des_fields(
	des_text: String, ini_text: String, stem: String, width_m: float
) -> PackedStringArray:
	## Human-facing metadata is real, not generator residue.
	var problems := PackedStringArray()
	var re_size := RegEx.new()
	re_size.compile("SIZE:\\s*(\\w+)")
	var m: RegExMatch = re_size.search(des_text)
	if m == null:
		problems.append("des: no SIZE field")
	else:
		var expect: String = des_size_band(width_m)
		var got: String = m.get_string(1)
		if got != expect:
			problems.append(
				"des: SIZE '%s' disagrees with dimensions (%.0f m -> '%s')"
				% [got, width_m, expect]
			)
	var re_name := RegEx.new()
	re_name.compile('missionName\\s*=\\s*"([^"]*)"')
	var mn: RegExMatch = re_name.search(ini_text)
	if mn == null:
		problems.append("ini: no missionName")
	elif mn.get_string(1).strip_edges().to_lower() == stem.to_lower():
		problems.append(
			"ini: missionName '%s' is the raw terrain slug — players see this in the lobby; give the map a real display name"
			% mn.get_string(1)
		)
	var re_tags := RegEx.new()
	re_tags.compile('customtags\\s*=\\s*"([^"]*)"')
	var tg: RegExMatch = re_tags.search(ini_text)
	if tg == null or tg.get_string(1).strip_edges().is_empty():
		problems.append("ini: customtags is empty (33/36 corpus maps populate it)")
	return problems


static func check_vxt_players(vxt_text: String) -> PackedStringArray:
	## Observer list carries all five entries every corpus map ships.
	var problems := PackedStringArray()
	for line in BzVxt.STANDARD_OBSERVERS:
		var parts: PackedStringArray = line.split(" ", false)
		if parts.is_empty():
			continue
		var craft: String = parts[0]
		if not vxt_text.contains(craft):
			problems.append("vxt: missing observer entry '%s'" % craft)
	return problems
