extends RefCounted
class_name BzAssets
## `assets` verb — live class index + proxy cache (docs/02 §3).
## Port of `backend/bzmap/editor/assets.py`.
##
## The editor ships no game content. This walks the user's install, enumerates
## every placeable ODF, and writes Godot-loadable PNG icons plus an index.
## Meshes stay on the proxy rung unless a converted `.glb` is already in cache
## or BzConvert can produce one (BzOgre / BzGeo / BzBwd2 / BzMaptex / BzGlb).

const _ODF_SUFFIXES := {".odf": true}

## Classes that are known-safe BZN clones across the corpus (docs/02 §6).
const _ALWAYS_VERIFIED := {
	"player": true,
	"pspwn_1": true,
	"eggeizr1": true,
	"npscr1": true,
	"npscr2": true,
	"npscr3": true,
	"sscr_1": true,
}

const _CATEGORY_COLORS := {
	"craft": [60, 140, 80],
	"building": [80, 90, 150],
	"pilot": [190, 120, 170],
	"prop": [130, 120, 90],
	"scrap": [200, 160, 40],
	"geyser": [210, 90, 40],
	"spawn": [220, 200, 50],
	"pickup": [90, 170, 180],
	"weapon": [150, 80, 80],
	"environment": [70, 130, 110],
	"other": [110, 110, 115],
}

const _DEFAULT_FOOTPRINT := {
	"craft": [10.0, 10.0],
	"building": [24.0, 24.0],
	"prop": [8.0, 8.0],
	"scrap": [4.0, 4.0],
	"geyser": [16.0, 16.0],
	"spawn": [6.0, 6.0],
	"environment": [32.0, 32.0],
	"other": [8.0, 8.0],
}

const _DEFAULT_HEIGHT := {
	"craft": 4.0,
	"building": 12.0,
	"prop": 4.0,
	"scrap": 1.5,
	"geyser": 8.0,
	"spawn": 1.0,
	"environment": 6.0,
	"other": 4.0,
}


## Convert one class to a cached `.glb` if it is not already there.
## Used when Import Assets skipped conversion (index + proxies only).
static func ensure_converted_mesh(prjid: String, game_root: String, cache_dir: String) -> Dictionary:
	var stem := prjid.to_lower()
	if stem.is_empty() or cache_dir.is_empty():
		return {}
	var glb := cache_dir.path_join("meshes").path_join("%s.glb" % stem)
	if FileAccess.file_exists(glb):
		return {"path": glb, "fidelity": "hd"}
	var root := game_root
	if root.is_empty() or not BzDiscover.is_game_install(root):
		return {}
	var search_roots: Array = [
		root,
		root.path_join("BZ_ASSETS"),
		root.path_join("Edit"),
	]
	return _convert_class(stem, search_roots, glb)


static func build_assets(
	game_root: String,
	cache_dir: String,
	pack_paths: Variant = null,
	refresh: bool = false,
	convert: bool = true
) -> Dictionary:
	## Build or refresh the asset cache. Returns the contract payload.
	var root := game_root
	if root.is_empty():
		root = BzDiscover.first_game_root()
	if root.is_empty() or not BzDiscover.is_game_install(root):
		return BzErrors.err(
			"no_game",
			"no game install found; pass --game-root",
			"run probe first"
		)
	root = BzDiscover._resolve(root) if not root.is_empty() else root
	if cache_dir.is_empty():
		return BzErrors.err(
			"bad_input",
			"cache directory is required",
			"pass a writable cache path"
		)
	var cache := cache_dir
	if not cache.is_absolute_path():
		cache = BzDiscover._resolve(cache)
	var mk := DirAccess.make_dir_recursive_absolute(cache)
	if mk != OK and not DirAccess.dir_exists_absolute(cache):
		return BzErrors.err(
			"io",
			"cannot create cache dir: %s" % cache,
			error_string(mk),
			cache
		)
	var index_path := cache.path_join("index.json")

	var packs := _as_string_array(pack_paths)
	# Python: `if not pack_paths` — empty list also auto-discovers workshop items.
	if packs.is_empty():
		var discovery := BzDiscover.discover()
		if not BzErrors.is_err(discovery):
			for item in discovery.get("installs", []):
				if typeof(item) == TYPE_DICTIONARY and item.get("kind") == "workshop_item":
					packs.append(str(item.get("path", "")))

	var fingerprint := _fingerprint(root, packs)
	if FileAccess.file_exists(index_path) and not refresh:
		var existing := _read_json(index_path)
		if str(existing.get("source_fingerprint", "")) == fingerprint:
			existing["ok"] = true
			existing["cache_dir"] = BzDiscover._resolve(cache)
			return existing

	var found := {}  # prjid -> [path, source]
	# Base game first; packs override by prjid so BZP classes win their layer.
	for rec in _scan_odfs(root.path_join("BZ_ASSETS"), "game"):
		found[rec[0]] = [rec[1], rec[2]]
	# Also loose ODFs at the install root (rare).
	for rec in _scan_odfs(root.path_join("addon"), "game"):
		if not found.has(rec[0]):
			found[rec[0]] = [rec[1], rec[2]]

	for pack in packs:
		var source_id := String(pack).get_file()
		for rec in _scan_odfs(pack, source_id):
			found[rec[0]] = [rec[1], rec[2]]

	var verified := _verified_prjids(packs)
	var search_roots: Array = []
	if convert:
		search_roots.append(root)
		search_roots.append(root.path_join("BZ_ASSETS"))
		search_roots.append(root.path_join("Edit"))
		for p in packs:
			search_roots.append(p)

	var classes: Array = []
	var unresolved: Array = []
	var prjids: Array = found.keys()
	prjids.sort()
	for prjid in prjids:
		var pair: Array = found[prjid]
		var rec := _class_record(
			str(prjid),
			str(pair[0]),
			str(pair[1]),
			verified,
			cache,
			search_roots if convert else []
		)
		if rec.get("ok", true) == false:
			unresolved.append({
				"prjid": str(prjid),
				"reason": str(rec.get("reason", "failed")),
			})
		else:
			classes.append(rec)

	var payload := {
		"ok": true,
		"cache_dir": BzDiscover._resolve(cache),
		"generated_at": _utc_now(),
		"source_fingerprint": fingerprint,
		"classes": classes,
		"unresolved": unresolved,
	}
	_write_json(index_path, payload)
	return payload


static func _parse_odf(path: String) -> Dictionary:
	var data := {}
	var section := ""
	var text := _read_latin1(path)
	if text.is_empty() and not FileAccess.file_exists(path):
		return data
	for raw in _splitlines(text):
		var line := raw
		var cmt := line.find("//")
		if cmt >= 0:
			line = line.substr(0, cmt)
		line = line.strip_edges()
		if line.is_empty() or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.contains("]"):
			section = line.substr(1, line.find("]") - 1).strip_edges()
			continue
		if not line.contains("="):
			continue
		var eq := line.find("=")
		var key := line.substr(0, eq).strip_edges().to_lower()
		var value := line.substr(eq + 1).strip_edges()
		value = value.trim_prefix("\"").trim_suffix("\"")
		value = value.trim_prefix("'").trim_suffix("'")
		data[key] = value
		if not section.is_empty():
			data["%s.%s" % [section.to_lower(), key]] = value
	return data


static func _categorize(prjid: String, class_label: String) -> String:
	var p := prjid.to_lower()
	var cl := class_label.to_lower()
	if p == "player" or cl.contains("player"):
		return "craft"
	if cl.contains("scrap") or p.begins_with("npscr") or p == "sscr_1" or p == "blc-pell":
		return "scrap"
	if cl.contains("geyser") or p.contains("geiz"):
		return "geyser"
	if cl.contains("spawn") or p.begins_with("pspwn"):
		return "spawn"
	if cl.contains("person") or cl.contains("pilot"):
		return "pilot"
	for token in ["i76building2", "i76building", "environment"]:
		if cl.contains(token):
			return "environment"
	for token in [
		"building", "factory", "recycler", "constructor", "silo",
		"extractor", "powerplant", "armory", "barracks", "gun",
		"depot", "commtower", "shieldtower", "hangar",
	]:
		if cl.contains(token):
			return "building"
	for token in [
		"wingman", "craft", "hover", "tank", "walker", "turret",
		"scout", "bomber", "apc", "tug", "howitzer",
		"constructionrig", "scavenger", "minelayer", "sav",
	]:
		if cl.contains(token):
			return "craft"
	for token in ["ammopack", "repairkit", "camerapod", "daywrecker"]:
		if cl.contains(token):
			return "pickup"
	for token in [
		"explosion", "spraybomb", "bouncebomb", "wpnpower", "cannon",
		"rocket", "tracer", "mortar", "planarexpl", "bolt", "grenade",
		"beam", "blast", "bullet", "torpedo", "flamepuff", "missile",
		"launcher", "damper", "flare", "magnet", "proximity", "torpedo",
		"dispenser", "weapon",
	]:
		if cl.contains(token):
			return "weapon"
	return "prop"


static func _faction(prjid: String) -> Variant:
	var p := prjid.to_lower()
	if p.is_empty():
		return null
	var first := p.substr(0, 1)
	var table := {
		"a": "NSDF",
		"s": "CCA",
		"b": "Black Dog",
		"c": "Chinese",
		"f": "Fury",
		"i": "ISDF",
		"e": null,
		"n": null,
		"p": null,
	}
	if table.has(first):
		return table[first]
	return null


static func _float_field(data: Dictionary, names: PackedStringArray, default_value: Variant = null) -> Variant:
	for name in names:
		if not data.has(name):
			continue
		var raw: Variant = data[name]
		if raw == null:
			continue
		var token := _first_token(str(raw))
		if token.is_empty():
			continue
		if token.is_valid_float():
			return float(token)
	return default_value


static func _scan_odfs(root: String, source_id: String) -> Array:
	## Yield `[prjid, path, source_id]` for every `.odf` under `root`.
	##
	## Workshop items are flat; the base game uses nested trees. Walk both.
	## Matching is case-insensitive on the suffix only.
	var out: Array = []
	if not DirAccess.dir_exists_absolute(root):
		return out
	for path in _walk_files(root):
		if not _ODF_SUFFIXES.has(_suffix_lower(path)):
			continue
		var prjid := path.get_file().get_basename().to_lower()
		out.append([prjid, path, source_id])
	return out


static func _verified_prjids(pack_dirs: PackedStringArray) -> Dictionary:
	var verified := {}
	for k in _ALWAYS_VERIFIED.keys():
		verified[k] = true
	var scanned := 0
	for pack in pack_dirs:
		if not DirAccess.dir_exists_absolute(pack):
			continue
		var da := DirAccess.open(pack)
		if da == null:
			continue
		da.include_hidden = false
		da.include_navigational = false
		for fname in da.get_files():
			if _suffix_lower(String(fname)) != ".bzn":
				continue
			scanned += 1
			if scanned > 24:
				# A couple of dozen corpus BZNs already cover the verified set.
				# Full 128 is slow and does not change the safety gate.
				return verified
			var path := String(pack).path_join(String(fname))
			for prjid in _bzn_prjids(path):
				if not prjid.is_empty():
					verified[prjid.to_lower()] = true
	return verified


static func _bzn_prjids(path: String) -> PackedStringArray:
	## Prefer BzBzn.read_bzn; scan PrjID value lines if the parse fails.
	var via: Variant = _try_bzn_prjids(path)
	if via != null:
		return via
	var out := PackedStringArray()
	if not FileAccess.file_exists(path):
		return out
	var text := _read_latin1(path)
	if text.is_empty():
		text = _read_text(path)
	var lines := _splitlines(text)
	var i := 0
	while i < lines.size():
		var stripped := String(lines[i]).strip_edges()
		if stripped == "PrjID [1] =":
			if i + 1 < lines.size():
				var val := String(lines[i + 1]).strip_edges()
				if not val.is_empty():
					out.append(val)
		elif stripped.begins_with("PrjID [1] ="):
			var val := stripped.substr("PrjID [1] =".length()).strip_edges()
			if not val.is_empty():
				out.append(val)
		i += 1
	return out


static func _fingerprint(game_root: String, pack_dirs: PackedStringArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var roots: Array = [game_root]
	for p in pack_dirs:
		roots.append(p)
	for root in roots:
		ctx.update(str(root).to_utf8_buffer())
		var mtime := FileAccess.get_modified_time(root)
		ctx.update(str(int(mtime)).to_utf8_buffer())
		# Python hashes `st.st_size` (4096-ish for a directory). Godot does
		# not expose directory size; 0 keeps the digest stable within the port.
		ctx.update(str(_stat_size(root)).to_utf8_buffer())
		var models := String(root).path_join("BZ_ASSETS").path_join("common").path_join("models")
		if DirAccess.dir_exists_absolute(models):
			var mm := FileAccess.get_modified_time(models)
			ctx.update(str(int(mm)).to_utf8_buffer())
	return "sha256:" + ctx.finish().hex_encode()


static func _icon(prjid: String, category: String, out_path: String) -> bool:
	var rgb: Array = _CATEGORY_COLORS.get(category, _CATEGORY_COLORS["other"])
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color8(int(rgb[0]), int(rgb[1]), int(rgb[2])))
	var outline := Color8(240, 240, 240)
	for x in range(1, 63):
		img.set_pixel(x, 1, outline)
		img.set_pixel(x, 62, outline)
	for y in range(1, 63):
		img.set_pixel(1, y, outline)
		img.set_pixel(62, y, outline)
	var label := (prjid if not prjid.is_empty() else "?")
	if label.length() > 8:
		label = label.substr(0, 8)
	_draw_label(img, label, 4, 24, Color8(250, 250, 250))
	var parent := out_path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	var err := img.save_png(out_path)
	return err == OK


static func _class_record(
	prjid: String,
	path: String,
	source: String,
	verified: Dictionary,
	cache_dir: String,
	search_roots: Array
) -> Dictionary:
	var data := _parse_odf(path)
	var class_label := str(
		data.get("classlabel", data.get("gameobjectclass.classlabel", ""))
	)
	var category := _categorize(prjid, class_label)
	var fp: Array = _DEFAULT_FOOTPRINT.get(category, _DEFAULT_FOOTPRINT["other"])
	var radius: Variant = _float_field(
		data,
		PackedStringArray(["collisionradius", "boundingradius", "radius"]),
		float(fp[0]) * 0.5
	)
	var width: Variant = _float_field(
		data, PackedStringArray(["width", "size"]), float(radius) * 2.0
	)
	var length: Variant = _float_field(
		data, PackedStringArray(["length", "depth"]), float(radius) * 2.0
	)
	var height: Variant = _float_field(
		data,
		PackedStringArray(["height", "boundingheight"]),
		float(_DEFAULT_HEIGHT.get(category, 4.0))
	)
	var icon_rel := "icons/%s.png" % prjid
	var icon_path := cache_dir.path_join("icons").path_join("%s.png" % prjid)
	if not FileAccess.file_exists(icon_path):
		if not _icon(prjid, category, icon_path):
			return {"ok": false, "reason": "failed to write icon %s" % icon_path}
	var glb := cache_dir.path_join("meshes").path_join("%s.glb" % prjid)
	var fidelity := "proxy"
	var mesh := ""
	if FileAccess.file_exists(glb):
		mesh = glb
		fidelity = "hd"
	elif not search_roots.is_empty():
		var converted := _convert_class(prjid, search_roots, glb)
		if not str(converted.get("path", "")).is_empty():
			mesh = str(converted.get("path"))
			fidelity = str(converted.get("fidelity", "proxy"))
		else:
			fidelity = "proxy"
	var is_verified := verified.has(prjid.to_lower())
	return {
		"prjid": prjid,
		"odf": path.get_file(),
		"source": source,
		"category": category,
		"label": class_label if not class_label.is_empty() else prjid,
		"faction": _faction(prjid),
		"radius_m": float(radius),
		"footprint_m": [float(width), float(length)],
		"height_m": float(height),
		"mesh": mesh,
		"mesh_fidelity": fidelity,
		"icon": icon_rel.replace("\\", "/"),
		"template_verified": is_verified,
		"placement_mode": "bzn" if is_verified else "runtime",
		"class_label": class_label,
	}


static func _convert_class(stem: String, search_roots: Array, dest: String) -> Dictionary:
	## Delegates to BzConvert.convert_class. Returns `{path, fidelity, reason}`.
	var res: Variant = BzConvert.convert_class(stem, search_roots, dest)
	if typeof(res) == TYPE_ARRAY and (res as Array).size() >= 3:
		var path_v: Variant = res[0]
		var path := "" if path_v == null else str(path_v)
		return {
			"path": path,
			"fidelity": str(res[1]),
			"reason": str(res[2]),
		}
	if typeof(res) == TYPE_DICTIONARY:
		return res
	return {}


# --- helpers ----------------------------------------------------------------

static func _try_bzn_prjids(path: String) -> Variant:
	var res: Variant = BzBzn.read_bzn(path)
	if typeof(res) != TYPE_DICTIONARY:
		return null
	var payload: Dictionary = res
	if payload.get("ok", false) == false:
		return null
	var out := PackedStringArray()
	var bzn = payload.get("bznfile", payload.get("bzn", null))
	if bzn == null:
		return null
	for obj in bzn.objects:
		var prjid := str(obj.prjid) if obj.prjid != null else ""
		if not prjid.is_empty():
			out.append(prjid)
	return out


static func _walk_files(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array = [root]
	var seen := {}
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var key := dir_path
		if seen.has(key):
			continue
		seen[key] = true
		var da := DirAccess.open(dir_path)
		if da == null:
			continue
		da.include_hidden = false
		da.include_navigational = false
		for fname in da.get_files():
			out.append(dir_path.path_join(String(fname)))
		for dname in da.get_directories():
			stack.append(dir_path.path_join(String(dname)))
	return out


static func _read_latin1(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var bytes := FileAccess.get_file_as_bytes(path)
	var utf16 := PackedByteArray()
	utf16.resize(bytes.size() * 2)
	for i in bytes.size():
		utf16[i * 2] = bytes[i]
		utf16[i * 2 + 1] = 0
	return utf16.get_string_from_utf16()


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


static func _splitlines(text: String) -> PackedStringArray:
	var norm := text.replace("\r\n", "\n").replace("\r", "\n")
	if norm.ends_with("\n"):
		norm = norm.substr(0, norm.length() - 1)
	if norm.is_empty() and text.is_empty():
		return PackedStringArray()
	return norm.split("\n", true)


static func _first_token(s: String) -> String:
	var t := s.strip_edges()
	var i := 0
	while i < t.length():
		var ch := t[i]
		if ch == " " or ch == "\t":
			break
		i += 1
	return t.substr(0, i)


static func _suffix_lower(path: String) -> String:
	var ext := path.get_extension()
	if ext.is_empty():
		return ""
	return "." + ext.to_lower()


static func _as_string_array(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if v == null:
		return out
	if v is PackedStringArray:
		return v
	if v is Array:
		for item in v:
			out.append(str(item))
	elif typeof(v) == TYPE_STRING:
		out.append(str(v))
	return out


static func _stat_size(path: String) -> int:
	if FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			return int(f.get_length())
	return 0


static func _utc_now() -> String:
	var s := Time.get_datetime_string_from_system(true)
	if not s.ends_with("Z"):
		s += "Z"
	return s


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := _read_text(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func _write_json(path: String, payload: Dictionary) -> void:
	var parent := path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	var text := JSON.stringify(payload, "  ") + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)


static func _draw_label(img: Image, text: String, ox: int, oy: int, color: Color) -> void:
	var x := ox
	for i in text.length():
		_blit_glyph(img, text[i], x, oy, color)
		x += 6
		if x > 58:
			break


static func _blit_glyph(img: Image, ch: String, ox: int, oy: int, color: Color) -> void:
	var rows: Array = _glyph(ch)
	for y in rows.size():
		var bits: int = int(rows[y])
		for col in 5:
			if (bits & (1 << (4 - col))) != 0:
				var px := ox + col
				var py := oy + y
				if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
					img.set_pixel(px, py, color)


static func _glyph(ch: String) -> Array:
	## 5x7 bitmap. Unknown glyphs get a hollow box so the icon still reads.
	var up := ch.to_upper()
	var table := {
		"0": [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
		"1": [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
		"2": [0x0E, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1F],
		"3": [0x0E, 0x11, 0x01, 0x06, 0x01, 0x11, 0x0E],
		"4": [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
		"5": [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
		"6": [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
		"7": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
		"8": [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
		"9": [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
		"A": [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
		"B": [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
		"C": [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
		"D": [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E],
		"E": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
		"F": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
		"G": [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0E],
		"H": [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
		"I": [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
		"J": [0x01, 0x01, 0x01, 0x01, 0x11, 0x11, 0x0E],
		"K": [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
		"L": [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
		"M": [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
		"N": [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11],
		"O": [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
		"P": [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
		"Q": [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
		"R": [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
		"S": [0x0E, 0x11, 0x10, 0x0E, 0x01, 0x11, 0x0E],
		"T": [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
		"U": [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
		"V": [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
		"W": [0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11],
		"X": [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
		"Y": [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04],
		"Z": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
		"_": [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1F],
		"-": [0x00, 0x00, 0x00, 0x0E, 0x00, 0x00, 0x00],
		"?": [0x0E, 0x11, 0x01, 0x06, 0x04, 0x00, 0x04],
	}
	if table.has(up):
		return table[up]
	return [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E]
