extends RefCounted
class_name BzCheckFormats
## Tier 1 structural validation (port of validate/formats.py).
##
## Instantiated as MapValidator(dirpath, reference_dir=). `validate_map` is
## the module-level wrapper.

## Ground-snap tolerance in metres (docs/06 §Tier 1; measured corpus max 1.04 m).
const GROUND_SNAP_TOLERANCE_M := 1.5

## Object classes counted as geysers / scrap for cross-file checks.
const GEYSER_CLASSES := {"eggeizr1": true}

## Python `SCRAP_CLASSES = KNOWN_SCRAP_PRJIDS` (bzmap.formats.odf).
const SCRAP_CLASSES := {
	"npscr1": true,
	"npscr2": true,
	"npscr3": true,
	"sscr_1": true,
	"blc-pell": true,
}

## Variant suffixes that may accompany a base terrain name (corpus convention).
const VARIANTS := ["_S", "_ST", "_SW"]

const SPAWN_CLASS := "pspwn_1"


var dirpath: String = ""
var reference_dir: String = ""


func _init(p_dirpath: String = "", p_reference_dir: String = "") -> void:
	dirpath = p_dirpath
	reference_dir = p_reference_dir


func validate() -> PackedStringArray:
	## Run every Tier 1 check and return the list of problems.
	var problems := PackedStringArray()
	problems.append_array(_check_roundtrip())
	problems.append_array(_check_per_map_invariants())
	problems.append_array(_check_cross_file())
	problems.append_array(_check_ground_snapping())
	problems.append_array(_check_terrain_name_collision())
	return problems


static func validate_map(p_dirpath: String, p_reference_dir: String = "") -> PackedStringArray:
	return BzCheckFormats.new(p_dirpath, p_reference_dir).validate()


func _bzn_files() -> Array:
	## `[ [basename, path], ... ]` for every `.bzn` in the directory.
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dirpath):
		return out
	var da := DirAccess.open(dirpath)
	if da == null:
		return out
	da.include_hidden = true
	da.include_navigational = false
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if not da.current_is_dir() and fn.get_extension().to_lower() == "bzn":
			var base: String = fn.substr(0, fn.length() - fn.get_extension().length() - 1)
			out.append([base, dirpath.path_join(fn)])
		fn = da.get_next()
	da.list_dir_end()
	return out


func _find_file(basename: String, suffix: String) -> String:
	## Case-insensitively locate `<basename><suffix>` in dirpath. Empty if none.
	var target: String = (basename + suffix).to_lower()
	var da := DirAccess.open(dirpath)
	if da == null:
		return ""
	da.include_hidden = true
	da.include_navigational = false
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if not da.current_is_dir() and fn.to_lower() == target:
			da.list_dir_end()
			return dirpath.path_join(fn)
		fn = da.get_next()
	da.list_dir_end()
	return ""


func _terrain_basename() -> String:
	## Longest shared stem across BZN files; else first .trn/.hg2 stem.
	var stems: Array = []
	for pair in _bzn_files():
		stems.append(str(pair[0]))
	if stems.is_empty():
		var da := DirAccess.open(dirpath)
		if da == null:
			return ""
		da.list_dir_begin()
		var fn: String = da.get_next()
		while fn != "":
			if not da.current_is_dir():
				var ext: String = fn.get_extension().to_lower()
				if ext == "trn" or ext == "hg2":
					da.list_dir_end()
					return fn.substr(0, fn.length() - ext.length() - 1)
			fn = da.get_next()
		da.list_dir_end()
		return ""
	var base: String = str(stems[0])
	var shortest: int = str(stems[0]).length()
	for s in stems:
		shortest = mini(shortest, str(s).length())
	var cut := shortest
	for i in shortest:
		var ch: String = base.substr(i, 1)
		var mismatch := false
		for s in stems:
			if str(s).substr(i, 1) != ch:
				mismatch = true
				break
		if mismatch:
			cut = i
			break
	return base.substr(0, cut)


func _check_roundtrip() -> PackedStringArray:
	var problems := PackedStringArray()
	var da := DirAccess.open(dirpath)
	if da == null:
		return problems
	da.include_hidden = true
	da.include_navigational = false
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if not da.current_is_dir():
			var ext: String = fn.get_extension().to_lower()
			var path: String = dirpath.path_join(fn)
			if ext == "bzn":
				problems.append_array(_roundtrip_bzn(path))
			elif ext == "hg2":
				problems.append_array(_roundtrip_hg2(path))
		fn = da.get_next()
	da.list_dir_end()
	return problems


func _roundtrip_bzn(path: String) -> PackedStringArray:
	var original: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var out: String = path + ".rt"
	var parsed: Dictionary = BzBzn.read_bzn(path)
	if not parsed.get("ok", false):
		_unlink(out)
		var msg: String = _err_message(parsed)
		return PackedStringArray(["%s: BZN round-trip failed: ValueError: %s" % [path.get_file(), msg]])
	var bzn: BzBzn.BznFile = parsed["bznfile"]
	var wr: Dictionary = bzn.write(out)
	if not wr.get("ok", false):
		_unlink(out)
		return PackedStringArray([
			"%s: BZN round-trip failed: OSError: %s" % [path.get_file(), _err_message(wr)]
		])
	var rewritten: PackedByteArray = FileAccess.get_file_as_bytes(out)
	_unlink(out)
	if rewritten != original:
		return PackedStringArray(["%s: BZN does not re-emit byte-identically" % path.get_file()])
	return PackedStringArray()


func _roundtrip_hg2(path: String) -> PackedStringArray:
	var original: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var out: String = path + ".rt"
	var parsed: Dictionary = BzHg2.read_hg2(path)
	if not parsed.get("ok", false):
		_unlink(out)
		return PackedStringArray([
			"%s: HG2 round-trip failed: ValueError: %s" % [path.get_file(), _err_message(parsed)]
		])
	var hm: BzHg2.HeightMap = parsed["heightmap"]
	var wr: Dictionary = hm.write(out)
	if not wr.get("ok", false):
		_unlink(out)
		return PackedStringArray([
			"%s: HG2 round-trip failed: OSError: %s" % [path.get_file(), _err_message(wr)]
		])
	var rewritten: PackedByteArray = FileAccess.get_file_as_bytes(out)
	_unlink(out)
	if rewritten != original:
		return PackedStringArray(["%s: HG2 does not re-emit byte-identically" % path.get_file()])
	return PackedStringArray()


func _check_per_map_invariants() -> PackedStringArray:
	var problems := PackedStringArray()
	var base: String = _terrain_basename()
	var hg2: String = _find_file(base, ".hg2")
	var trn: String = _find_file(base, ".trn")
	var hm: BzHg2.HeightMap = null
	if not hg2.is_empty():
		var parsed: Dictionary = BzHg2.read_hg2(hg2)
		if parsed.get("ok", false):
			hm = parsed["heightmap"]
		else:
			problems.append("%s: %s" % [hg2.get_file(), _err_message(parsed)])
	if hm != null:
		problems.append_array(_check_size_consistency(hm))
		problems.append_array(_check_byte_counts(hm))
	if not trn.is_empty():
		if not FileAccess.file_exists(trn):
			problems.append("%s: OSError: cannot read" % trn.get_file())
		elif hm != null:
			var size: Variant = _trn_size_from_path(trn)
			if size != null:
				var width: float = float(size[0])
				var depth: float = float(size[1])
				var exp_w: float = float(hm.zonesX) * BzHg2.ZONE_M
				var exp_d: float = float(hm.zonesZ) * BzHg2.ZONE_M
				if absf(width - exp_w) > 1e-6 or absf(depth - exp_d) > 1e-6:
					problems.append(
						"%s: [Size] %sx%s does not match HG2 header %sx%s"
						% [trn.get_file(), _num(width), _num(depth), _num(exp_w), _num(exp_d)]
					)
	for pair in _bzn_files():
		var path: String = str(pair[1])
		var parsed: Dictionary = BzBzn.read_bzn(path)
		if not parsed.get("ok", false):
			problems.append("%s: ValueError: %s" % [path.get_file(), _err_message(parsed)])
			continue
		var bzn: BzBzn.BznFile = parsed["bznfile"]
		for problem in bzn.validate():
			problems.append("%s: %s" % [path.get_file(), problem])
	return problems


func _check_size_consistency(_hm: BzHg2.HeightMap) -> PackedStringArray:
	return PackedStringArray()


func _check_byte_counts(hm: BzHg2.HeightMap) -> PackedStringArray:
	var problems := PackedStringArray()
	var base: String = _terrain_basename()
	var expected := {
		".hg2": hm.zonesX * hm.zonesZ * 256 * 256 * 2 + 12,
		".mat": (hm.zonesX * 64) * (hm.zonesZ * 64) * 2,
		".lgt": (hm.zonesX * hm.zonesZ + 1) * 65536,
	}
	for suffix in expected.keys():
		var p: String = _find_file(base, str(suffix))
		if p.is_empty():
			continue
		var got: int = _file_size(p)
		var want: int = int(expected[suffix])
		if got != want:
			problems.append(
				"%s: size %d does not match expected %d for %dx%d zones"
				% [p.get_file(), got, want, hm.zonesX, hm.zonesZ]
			)
	return problems


func _check_cross_file() -> PackedStringArray:
	var problems := PackedStringArray()
	problems.append_array(_check_variant_files_exist())
	problems.append_array(_check_des_counts())
	problems.append_array(_check_ini_max_players())
	return problems


func _check_variant_files_exist() -> PackedStringArray:
	var base: String = _terrain_basename()
	if base.is_empty():
		return PackedStringArray()
	var problems := PackedStringArray()
	for suffix in [".trn", ".hg2", ".mat"]:
		if _find_file(base, suffix).is_empty():
			problems.append(
				"terrain file <%s%s> implied by the BZN filenames is missing" % [base, suffix]
			)
	return problems


func _check_des_counts() -> PackedStringArray:
	var base: String = _terrain_basename()
	var des: String = _find_file(base, ".des")
	var s_bzn: String = _find_file(base + "_S", ".bzn")
	if des.is_empty() or s_bzn.is_empty():
		return PackedStringArray()
	if not FileAccess.file_exists(des):
		return PackedStringArray(["%s: OSError: cannot read" % des.get_file()])
	var text: String = FileAccess.get_file_as_string(des)
	var geysers: Variant = null
	var scrap: Variant = null
	for line in text.split("\n"):
		var raw: String = line.trim_suffix("\r")
		if raw.begins_with("GEYSERS:"):
			var bits: PackedStringArray = raw.split(":", true, 1)
			if bits.size() >= 2:
				var tok: PackedStringArray = bits[1].strip_edges().replace("\t", " ").split(" ", false)
				if not tok.is_empty() and tok[0].is_valid_int():
					geysers = tok[0].to_int()
		elif raw.begins_with("SCRAP:"):
			var bits: PackedStringArray = raw.split(":", true, 1)
			if bits.size() >= 2:
				var tok: PackedStringArray = bits[1].strip_edges().replace("\t", " ").split(" ", false)
				if not tok.is_empty() and tok[0].is_valid_int():
					scrap = tok[0].to_int()
	var parsed: Dictionary = BzBzn.read_bzn(s_bzn)
	if not parsed.get("ok", false):
		return PackedStringArray(["%s: ValueError: %s" % [s_bzn.get_file(), _err_message(parsed)]])
	var counts: Array = _bzn_geyser_scrap_spawns(parsed["bznfile"])
	var problems := PackedStringArray()
	if geysers != null and int(geysers) != int(counts[0]):
		problems.append(
			"%s: states %d GEYSERS but _S has %d" % [des.get_file(), int(geysers), int(counts[0])]
		)
	if scrap != null and int(scrap) != int(counts[1]):
		problems.append(
			"%s: states %d SCRAP but _S has %d" % [des.get_file(), int(scrap), int(counts[1])]
		)
	return problems


func _check_ini_max_players() -> PackedStringArray:
	var base: String = _terrain_basename()
	var ini: String = _find_file(base, ".ini")
	var base_bzn: String = _find_file(base, ".bzn")
	if ini.is_empty() or base_bzn.is_empty():
		return PackedStringArray()
	if not FileAccess.file_exists(ini):
		return PackedStringArray(["%s: OSError: cannot read" % ini.get_file()])
	var sections: Dictionary = _parse_ini(ini)
	var mp: Dictionary = sections.get("MULTIPLAYER", {})
	if not mp.has("maxPlayers"):
		return PackedStringArray()
	var max_players_raw: String = str(mp["maxPlayers"])
	if not max_players_raw.is_valid_int():
		return PackedStringArray([
			"%s: maxPlayers '%s' is not an integer" % [ini.get_file(), max_players_raw]
		])
	var max_players: int = max_players_raw.to_int()
	var parsed: Dictionary = BzBzn.read_bzn(base_bzn)
	if not parsed.get("ok", false):
		return PackedStringArray([
			"%s: ValueError: %s" % [base_bzn.get_file(), _err_message(parsed)]
		])
	var counts: Array = _bzn_geyser_scrap_spawns(parsed["bznfile"])
	var spawns: int = int(counts[2])
	if spawns > max_players:
		return PackedStringArray([
			"%s: maxPlayers %d is less than the deathmatch spawn count %d"
			% [ini.get_file(), max_players, spawns]
		])
	return PackedStringArray()


func _check_ground_snapping() -> PackedStringArray:
	var problems := PackedStringArray()
	var hg2: String = _find_file(_terrain_basename(), ".hg2")
	if hg2.is_empty():
		return problems
	var parsed_hm: Dictionary = BzHg2.read_hg2(hg2)
	if not parsed_hm.get("ok", false):
		return PackedStringArray(["%s: %s" % [hg2.get_file(), _err_message(parsed_hm)]])
	var hm: BzHg2.HeightMap = parsed_hm["heightmap"]
	for pair in _bzn_files():
		var path: String = str(pair[1])
		var parsed: Dictionary = BzBzn.read_bzn(path)
		if not parsed.get("ok", false):
			continue
		var bzn: BzBzn.BznFile = parsed["bznfile"]
		for i in bzn.objects.size():
			var obj: BzBzn.GameObject = bzn.objects[i]
			var pos: Variant = _object_position(obj)
			if pos == null:
				problems.append("%s: object %d has no parseable position" % [path.get_file(), i])
				continue
			var x: float = float(pos[0])
			var y: float = float(pos[1])
			var z: float = float(pos[2])
			var ground: float = BzHg2.sample_m(hm, x, z)
			if absf(y - ground) > GROUND_SNAP_TOLERANCE_M:
				var prjid: String = "None" if obj.prjid == null else str(obj.prjid)
				problems.append(
					"%s: object %d (%s) Y=%.2f is %.2f m from terrain height %.2f at (%.1f, %.1f)"
					% [path.get_file(), i, prjid, y, absf(y - ground), ground, x, z]
				)
	return problems


func _check_terrain_name_collision() -> PackedStringArray:
	if reference_dir.is_empty():
		return PackedStringArray()
	var base: String = _terrain_basename()
	if base.is_empty():
		return PackedStringArray()
	var existing: Dictionary = _installed_terrain_names(reference_dir)
	if existing.is_empty():
		return PackedStringArray()
	if existing.has(base.to_lower()):
		return PackedStringArray([
			"terrain name <%s> collides with an installed terrain in %s" % [base, reference_dir]
		])
	return PackedStringArray()


static func _object_position(obj: BzBzn.GameObject) -> Variant:
	## `(x, y, z)` from the first `pos [1] =` block, or null.
	var lines: PackedStringArray = obj.lines
	for i in lines.size():
		if lines[i].strip_edges() != "pos [1] =":
			continue
		var values: Dictionary = {}
		var end: int = mini(i + 7, lines.size())
		for j in range(end - (i + 1)):
			var bl: String = lines[i + 1 + j]
			var stripped: String = bl.strip_edges()
			for axis in ["x", "y", "z"]:
				if stripped == "%s [1] =" % axis and i + j + 2 < lines.size():
					var raw: String = lines[i + j + 2].strip_edges()
					if not raw.is_valid_float():
						return null
					values[axis] = raw.to_float()
		if values.size() == 3:
			return [values["x"], values["y"], values["z"]]
	return null


static func _trn_size_from_path(path: String) -> Variant:
	## `[Size]` Width/Depth. Parsed locally so we do not call BzTrn.Section.get
	## (that method shadows Object.get and has been uncompilable mid-port).
	var text: String = FileAccess.get_file_as_string(path)
	if text.begins_with("\uFEFF"):
		text = text.substr(1)
	var in_size := false
	var width: Variant = null
	var depth: Variant = null
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("[") and line.find("]") > 0:
			var name: String = line.substr(1, line.find("]") - 1)
			in_size = name == "Size"
			continue
		if not in_size or not line.contains("="):
			continue
		var eq: int = line.find("=")
		var key: String = line.substr(0, eq).strip_edges()
		var value: String = line.substr(eq + 1).strip_edges()
		if key == "Width":
			width = value
		elif key == "Depth":
			depth = value
	if width == null or depth == null:
		return null
	var ws: String = str(width).strip_edges()
	var ds: String = str(depth).strip_edges()
	if not ws.is_valid_float() or not ds.is_valid_float():
		return null
	return [ws.to_float(), ds.to_float()]


static func _bzn_geyser_scrap_spawns(bzn: BzBzn.BznFile) -> Array:
	var geysers := 0
	var scrap := 0
	var spawns := 0
	for obj_v in bzn.objects:
		var obj: BzBzn.GameObject = obj_v
		var prjid: String = "" if obj.prjid == null else str(obj.prjid)
		if GEYSER_CLASSES.has(prjid):
			geysers += 1
		elif SCRAP_CLASSES.has(prjid):
			scrap += 1
		elif prjid == SPAWN_CLASS:
			spawns += 1
	return [geysers, scrap, spawns]


static func _installed_terrain_names(p_reference_dir: String) -> Dictionary:
	var names := {}
	_walk_trn(p_reference_dir, names)
	return names


static func _walk_trn(dir_path: String, names: Dictionary) -> void:
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	da.include_hidden = false
	da.include_navigational = false
	for fn in da.get_files():
		if fn.get_extension().to_lower() == "trn":
			var stem: String = fn.substr(0, fn.length() - fn.get_extension().length() - 1)
			names[stem.to_lower()] = true
	for sub in da.get_directories():
		if sub == "." or sub == "..":
			continue
		_walk_trn(dir_path.path_join(sub), names)


static func _parse_ini(path: String) -> Dictionary:
	## `{section: {key: value}}`. Mirrors `bzmap.cli.parse_ini` / formats.py.
	var sections := {}
	var current: Variant = null
	var text: String = FileAccess.get_file_as_string(path)
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.is_empty() or line.begins_with(";") or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			current = line.substr(1, line.length() - 2).strip_edges()
			if not sections.has(current):
				sections[current] = {}
			continue
		if not line.contains("=") or current == null:
			continue
		var eq: int = line.find("=")
		var key: String = line.substr(0, eq).strip_edges()
		var value: String = line.substr(eq + 1).strip_edges()
		if (
			value.length() >= 2
			and value[0] == value[value.length() - 1]
			and (value[0] == "\"" or value[0] == "'")
		):
			value = value.substr(1, value.length() - 2)
		var sec: Dictionary = sections[current]
		sec[key] = value
		sections[current] = sec
	return sections


static func _unlink(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n: int = f.get_length()
	f.close()
	return n


static func _err_message(payload: Dictionary) -> String:
	var err: Variant = payload.get("error", {})
	if typeof(err) == TYPE_DICTIONARY:
		return str((err as Dictionary).get("message", ""))
	return str(payload)


static func _num(v: float) -> String:
	## Python `str(float)` for whole values keeps a trailing `.0`.
	if is_equal_approx(v, float(int(v))):
		return "%d.0" % int(v)
	return str(v)
