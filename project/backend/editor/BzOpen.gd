extends RefCounted
class_name BzOpen
## ``bzmap editor open`` — map file set -> session directory.
##
## Port of ``backend/bzmap/editor/open.py``. Python raises EditorError;
## this returns BzErrors.err(...) / the verb payload.
##
## docs/02 §3 "open" says binary BZNs are converted via WorldBuilder's
## BinaryBZNParser with ``converted_from_binary: true``. Python open.py
## refuses them (``binary_bzn_unsupported``). Python wins (docs/03); there
## is deliberately no binary reader.
##
## Session helpers below are private copies of BzSession / session.py.
## BzSession.gd does not compile on Godot 4.7 (`String.is_absolute`); do
## not call it from this file.

const CONTRACT_VERSION: int = 1
const HEIGHT_MASK: int = 0x1FFF
const FLAG_SHIFT: int = 13
const VARIANT_SUFFIXES: Array[String] = ["", "_S", "_ST", "_SW"]
const _VARIANT_STEM_SUFFIXES: Array[String] = ["_SW", "_ST", "_MS", "_S"]


static func is_binary_bzn(path: String) -> bool:
	## True when a .bzn is a 1998-era binary save, not ASCII.
	##
	## Do not treat ``missionSave = true`` as binary — that flag is on every
	## ASCII corpus file. Only ``binarySave`` itself, NULs, or a non-UTF-8
	## decode count.
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var raw: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if raw.is_empty():
		return false
	var n: int = mini(raw.size(), 256)
	for i in n:
		if raw[i] == 0:
			return true
	if not _is_valid_utf8(raw):
		return true
	var text: String = raw.get_string_from_utf8()
	var stripped: String = text.strip_edges(true, false)
	if not stripped.to_lower().begins_with("version"):
		return true
	var lines: PackedStringArray = _splitlines(stripped)
	var limit: int = mini(lines.size(), 20)
	for i in limit:
		var line: String = lines[i].strip_edges()
		var low: String = line.to_lower()
		if low == "binarysave [1] =" and i + 1 < lines.size():
			return lines[i + 1].strip_edges().to_lower() == "true"
		if low.begins_with("binarysave") and low.contains("true"):
			return true
	return false


static func open_map(path: String, session_dir: String) -> Dictionary:
	## Open a map file set into ``session_dir``. Returns the response dict.
	var resolved: Dictionary = _resolve_map_input(path)
	if BzErrors.is_err(resolved):
		return resolved
	var directory: String = str(resolved["directory"])
	var stem: String = str(resolved["stem"])
	var files: Array = resolved["files"]
	var warnings: Array = []

	var binary_bzns: Array = []
	for p in files:
		var fp: String = str(p)
		if fp.get_extension().to_lower() == "bzn" and is_binary_bzn(fp):
			binary_bzns.append(fp)
	if not binary_bzns.is_empty():
		var first: String = str(binary_bzns[0])
		return BzErrors.err(
			"binary_bzn_unsupported",
			"%s is a binary BZN; a binary reader is not in bzmap yet" % first.get_file(),
			"re-save from the game with the asciisave launch argument, or wait for the binary reader",
			first
		)

	var paths: Dictionary = _ensure_session_dir(session_dir)
	if BzErrors.is_err(paths):
		return paths

	var copied: Variant = _copy_into_residue(files, str(paths["source"]))
	if BzErrors.is_err(copied):
		return copied

	var hg2_path: String = _find_source_file(str(paths["source"]), stem, ".hg2")
	if hg2_path.is_empty():
		return BzErrors.err(
			"missing_hg2",
			"no .hg2 for stem '%s' next to %s" % [stem, path],
			"",
			directory
		)

	var hg2_res: Dictionary = BzHg2.read_hg2(hg2_path)
	if not bool(hg2_res.get("ok", false)):
		return hg2_res
	var heightmap: BzHg2.HeightMap = hg2_res["heightmap"]

	var wr: Dictionary = _write_terrain_r16(str(paths["terrain"]), heightmap)
	if BzErrors.is_err(wr):
		return wr
	wr = _write_hg2_flags(str(paths["hg2_flags"]), heightmap)
	if BzErrors.is_err(wr):
		return wr
	wr = _write_json(str(paths["hg2_header"]), {
		"version": heightmap.version,
		"depth": heightmap.depth,
		"zonesX": heightmap.zonesX,
		"zonesZ": heightmap.zonesZ,
		"unknownA": heightmap.unknownA,
		"unknownB": heightmap.unknownB,
	})
	if BzErrors.is_err(wr):
		return wr

	var mat_path: String = _find_source_file(str(paths["source"]), stem, ".mat")
	var mat_grid_x: int
	var mat_grid_z: int
	if not mat_path.is_empty():
		var mat_res: Dictionary = BzMat.read_mat(mat_path)
		if not bool(mat_res.get("ok", false)):
			return mat_res
		var grid: BzMat.MaterialGrid = mat_res["grid"]
		wr = _write_materials_u16(str(paths["materials"]), grid)
		if BzErrors.is_err(wr):
			return wr
		mat_grid_x = grid.grid_x
		mat_grid_z = grid.grid_z
	else:
		warnings.append("no .mat in the basename group")
		mat_grid_x = int(heightmap.grid_x / 4)
		mat_grid_z = int(heightmap.grid_z / 4)
		var empty_data := PackedInt32Array()
		empty_data.resize(mat_grid_z * mat_grid_x)
		empty_data.fill(0)
		var empty := BzMat.MaterialGrid.new(empty_data, mat_grid_z, mat_grid_x)
		wr = _write_materials_u16(str(paths["materials"]), empty)
		if BzErrors.is_err(wr):
			return wr

	var objects := {}
	for v in VARIANT_SUFFIXES:
		objects[v] = []
	var present_variants: Array = []
	for variant in VARIANT_SUFFIXES:
		var bzn_path: String = _find_source_file(
			str(paths["source"]), stem, _variant_bzn_suffix(variant)
		)
		if bzn_path.is_empty():
			continue
		var prefix: String = "obj" if str(variant) == "" else "obj%s" % str(variant).to_lower()
		var loaded: Dictionary = BzObjects.load_variant_objects(bzn_path, prefix)
		if BzErrors.is_err(loaded) or not bool(loaded.get("ok", false)):
			return loaded
		objects[variant] = loaded["records"]
		present_variants.append(variant)

	if present_variants.is_empty():
		warnings.append("no .bzn in the basename group")
		present_variants = [""]

	var trn_path: String = _find_source_file(str(paths["source"]), stem, ".trn")
	var world: String = _world_from_trn(trn_path)
	var pack_context: Dictionary = _detect_pack_context(directory, files)

	var over: bool = _height_over_ceiling(heightmap)
	if over:
		warnings.append(
			"source heightmap has cells above the editor authoring ceiling "
			+ "(raw 4095); inherited values are preserved"
		)

	var features := {"water": [], "plants": []}
	var sidecar: String = directory.path_join("features.json")
	if FileAccess.file_exists(sidecar):
		var loaded_feat: Variant = _read_json(sidecar)
		if not BzErrors.is_err(loaded_feat) and typeof(loaded_feat) == TYPE_DICTIONARY:
			var feat_dict: Dictionary = loaded_feat
			if feat_dict.has("water") or feat_dict.has("plants"):
				features = feat_dict

	var meta: Dictionary = _parse_meta(files, stem)
	var dirty: Dictionary = _empty_dirty(present_variants)

	wr = _write_json(str(paths["objects"]), objects)
	if BzErrors.is_err(wr):
		return wr
	wr = _write_json(str(paths["features"]), features)
	if BzErrors.is_err(wr):
		return wr
	wr = _write_json(str(paths["meta"]), meta)
	if BzErrors.is_err(wr):
		return wr
	wr = _write_json(str(paths["dirty"]), dirty)
	if BzErrors.is_err(wr):
		return wr

	var lgt_path: String = _find_source_file(str(paths["source"]), stem, ".lgt")
	var manifest_v: Variant = _write_manifest(str(paths["manifest"]), {
		"stem": stem,
		"source_path": _abspath(directory),
		"converted_from_binary": false,
		"world": world,
		"width_m": int(heightmap.width_m),
		"depth_m": int(heightmap.depth_m),
		"grid_x": int(heightmap.grid_x),
		"grid_z": int(heightmap.grid_z),
		"cell_m": 5.0,
		"height_scale": BzHg2.HEIGHT_SCALE,
		"height_max_raw": 4095,
		"height_over_ceiling": over,
		"mat_grid_x": int(mat_grid_x),
		"mat_grid_z": int(mat_grid_z),
		"mat_cell_m": BzMat.TILE_M,
		"variants": present_variants,
		"has_lightmap": not lgt_path.is_empty(),
		"pack_context": pack_context,
	})
	if BzErrors.is_err(manifest_v):
		return manifest_v

	return {
		"ok": true,
		"session": _abspath(str(paths["root"])),
		"manifest": manifest_v,
		"warnings": warnings,
	}


# -- private helpers (open.py) -----------------------------------------------


static func _detect_pack_context(directory: String, files: Array) -> Dictionary:
	## Heuristic pack_context from the source location and sidecar files.
	var orig_parts: PackedStringArray = _path_parts(directory)
	var parts: Array = []
	for p in orig_parts:
		parts.append(p.to_lower())
	var has_odf: bool = false
	for f in files:
		if str(f).get_extension().to_lower() == "odf":
			has_odf = true
			break
	var in_workshop_tree: bool = parts.has("packaged_mods") or parts.has("workshop")
	if parts.has("3406347034") or (has_odf and in_workshop_tree):
		var workshop_id: Variant = null
		for i in orig_parts.size():
			var part: String = orig_parts[i]
			var digit_id: bool = (
				_is_digit_str(part)
				and part.length() >= 7
				and i > 0
				and orig_parts[i - 1].to_lower() in ["packaged_mods", "301650"]
			)
			if part.to_lower() == "3406347034" or digit_id:
				workshop_id = part
				break
		return {"kind": "bzp", "workshop_id": workshop_id if workshop_id != null else "3406347034"}
	if has_odf:
		return {"kind": "bzp", "workshop_id": null}
	return {"kind": "base"}


static func _world_from_trn(trn_path: String) -> String:
	if trn_path.is_empty():
		return ""
	# Private INI read — do not call BzTrn; a parse error in another
	# class_name (BzSession) can leave BzTrn bound as a bare GDScript.
	var sky: String = _trn_get(trn_path, "Sky", "SkyTexture").strip_edges().to_lower()
	if not sky.is_empty():
		var sky_stem: String = sky.get_file().get_basename().to_lower()
		if not sky_stem.is_empty():
			return sky_stem
	var palette: String = _trn_get(trn_path, "Color", "Palette").strip_edges().to_lower()
	if not palette.is_empty():
		return palette.get_file().get_basename().to_lower()
	return ""


static func _parse_meta(files: Array, _stem: String) -> Dictionary:
	var meta := {}
	var by_suf := {}
	for p in files:
		var fp: String = str(p)
		var ext: String = fp.get_extension().to_lower()
		var suf: String = (".%s" % ext) if not ext.is_empty() else ""
		by_suf[suf] = fp
	if by_suf.has(".ini"):
		meta["ini"] = {"raw": _read_text_replace(str(by_suf[".ini"]))}
	if by_suf.has(".des"):
		meta["des"] = {"raw": _read_text_replace(str(by_suf[".des"]))}
	if by_suf.has(".odf"):
		meta["odf"] = {"raw": _read_text_replace(str(by_suf[".odf"]))}
	if by_suf.has(".trn"):
		var trn_path: String = str(by_suf[".trn"])
		meta["trn"] = {
			"NormalView": _trn_section_dict(trn_path, "NormalView"),
			"World": _trn_section_dict(trn_path, "World"),
			"Sky": _trn_section_dict(trn_path, "Sky"),
			"Clouds": _trn_section_dict(trn_path, "Clouds"),
		}
	return meta


static func _trn_get(path: String, section: String, key: String) -> String:
	var items: Dictionary = _trn_section_dict(path, section)
	if items.has(key):
		return str(items[key])
	return ""


static func _trn_section_dict(path: String, section: String) -> Dictionary:
	## Line-preserving key/value extract matching TerrainConfig.get / items.
	var out := {}
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	var text: String = _read_text_replace(path)
	if text.begins_with("\uFEFF"):
		text = text.substr(1)
	var current: String = ""
	for line in _splitlines(text):
		var stripped: String = line.strip_edges()
		if stripped.is_empty() or stripped.begins_with(";") or stripped.begins_with("#"):
			continue
		if stripped.begins_with("["):
			var close: int = stripped.find("]")
			if close > 0:
				current = stripped.substr(1, close - 1)
			continue
		if current == section and line.contains("="):
			var eq: int = line.find("=")
			var k: String = line.substr(0, eq).strip_edges()
			var v: String = line.substr(eq + 1).strip_edges()
			if not out.has(k):
				out[k] = v
	return out


static func _read_text_replace(path: String) -> String:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	return bytes.get_string_from_utf8()


static func _path_parts(path: String) -> PackedStringArray:
	var norm: String = path.replace("\\", "/")
	return norm.split("/", false)


static func _is_digit_str(s: String) -> bool:
	if s.is_empty():
		return false
	for i in s.length():
		var ch: String = s.substr(i, 1)
		if ch < "0" or ch > "9":
			return false
	return true


static func _abspath(path: String) -> String:
	var p: String = path
	if p == "~" or p.begins_with("~/") or p.begins_with("~\\"):
		var home: String = OS.get_environment("HOME")
		if home.is_empty():
			home = OS.get_environment("USERPROFILE")
		if p == "~":
			p = home
		else:
			p = home.path_join(p.substr(2))
	if p.is_absolute_path():
		return p.simplify_path()
	var cwd := DirAccess.open(".")
	if cwd == null:
		return p.simplify_path()
	return cwd.get_current_dir().path_join(p).simplify_path()


static func _splitlines(text: String) -> PackedStringArray:
	## Python ``str.splitlines()`` for CR / LF / CRLF.
	var lines := PackedStringArray()
	var i: int = 0
	var n: int = text.length()
	while i < n:
		var start: int = i
		while i < n:
			var ch: int = text.unicode_at(i)
			if ch == 0x0A or ch == 0x0D:
				break
			i += 1
		lines.append(text.substr(start, i - start))
		if i >= n:
			break
		if text.unicode_at(i) == 0x0D and i + 1 < n and text.unicode_at(i + 1) == 0x0A:
			i += 2
		else:
			i += 1
	return lines


static func _is_valid_utf8(data: PackedByteArray) -> bool:
	## CPython strict UTF-8 (overlong / surrogates / >U+10FFFF rejected).
	var i: int = 0
	var n: int = data.size()
	while i < n:
		var c: int = int(data[i])
		if c <= 0x7F:
			i += 1
			continue
		if c >= 0xC2 and c <= 0xDF:
			if i + 1 >= n or (int(data[i + 1]) & 0xC0) != 0x80:
				return false
			i += 2
			continue
		if c == 0xE0:
			if i + 2 >= n:
				return false
			var c1: int = int(data[i + 1])
			var c2: int = int(data[i + 2])
			if c1 < 0xA0 or c1 > 0xBF or (c2 & 0xC0) != 0x80:
				return false
			i += 3
			continue
		if c >= 0xE1 and c <= 0xEC:
			if i + 2 >= n:
				return false
			if (int(data[i + 1]) & 0xC0) != 0x80 or (int(data[i + 2]) & 0xC0) != 0x80:
				return false
			i += 3
			continue
		if c == 0xED:
			if i + 2 >= n:
				return false
			var d1: int = int(data[i + 1])
			var d2: int = int(data[i + 2])
			if d1 < 0x80 or d1 > 0x9F or (d2 & 0xC0) != 0x80:
				return false
			i += 3
			continue
		if c >= 0xEE and c <= 0xEF:
			if i + 2 >= n:
				return false
			if (int(data[i + 1]) & 0xC0) != 0x80 or (int(data[i + 2]) & 0xC0) != 0x80:
				return false
			i += 3
			continue
		if c == 0xF0:
			if i + 3 >= n:
				return false
			var e1: int = int(data[i + 1])
			if e1 < 0x90 or e1 > 0xBF:
				return false
			if (int(data[i + 2]) & 0xC0) != 0x80 or (int(data[i + 3]) & 0xC0) != 0x80:
				return false
			i += 4
			continue
		if c >= 0xF1 and c <= 0xF3:
			if i + 3 >= n:
				return false
			if (
				(int(data[i + 1]) & 0xC0) != 0x80
				or (int(data[i + 2]) & 0xC0) != 0x80
				or (int(data[i + 3]) & 0xC0) != 0x80
			):
				return false
			i += 4
			continue
		if c == 0xF4:
			if i + 3 >= n:
				return false
			var f1: int = int(data[i + 1])
			if f1 < 0x80 or f1 > 0x8F:
				return false
			if (int(data[i + 2]) & 0xC0) != 0x80 or (int(data[i + 3]) & 0xC0) != 0x80:
				return false
			i += 4
			continue
		return false
	return true


# -- private copies of BzSession / session.py --------------------------------


static func _session_paths(session_dir: String) -> Dictionary:
	var residue: String = session_dir.path_join("residue")
	return {
		"root": session_dir,
		"manifest": session_dir.path_join("manifest.json"),
		"terrain": session_dir.path_join("terrain.r16"),
		"materials": session_dir.path_join("materials.u16"),
		"objects": session_dir.path_join("objects.json"),
		"features": session_dir.path_join("features.json"),
		"meta": session_dir.path_join("meta.json"),
		"dirty": session_dir.path_join("dirty.json"),
		"report": session_dir.path_join("report.json"),
		"masks": session_dir.path_join("masks"),
		"residue": residue,
		"source": residue.path_join("source"),
		"hg2_header": residue.path_join("hg2_header.json"),
		"hg2_flags": residue.path_join("hg2_flags.u8"),
	}


static func _ensure_session_dir(session_dir: String) -> Dictionary:
	var paths: Dictionary = _session_paths(session_dir)
	for key in ["root", "masks", "residue", "source"]:
		var dir_path: String = str(paths[key])
		var err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK and not DirAccess.dir_exists_absolute(dir_path):
			return BzErrors.err(
				"session_dir_unusable",
				"cannot create session directory: %s" % dir_path,
				"check permissions and path",
				dir_path
			)
	return paths


static func _write_json(path: String, payload: Variant) -> Dictionary:
	var text: String = JSON.stringify(payload, "  ")
	if text.is_empty() and typeof(payload) != TYPE_NIL:
		if typeof(payload) == TYPE_DICTIONARY and (payload as Dictionary).is_empty():
			text = "{}"
		elif typeof(payload) == TYPE_ARRAY and (payload as Array).is_empty():
			text = "[]"
		elif typeof(payload) == TYPE_DICTIONARY or typeof(payload) == TYPE_ARRAY:
			return BzErrors.err("write_failed", "failed to serialize JSON: %s" % path, "", path)
	if not text.ends_with("\n"):
		text += "\n"
	var parent: String = path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return BzErrors.err(
			"write_failed",
			"cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())],
			"",
			path
		)
	file.store_string(text)
	file.close()
	return {"ok": true}


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return BzErrors.err("not_found", "no such file or directory: %s" % path, "", path)
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null and text.strip_edges() != "null":
		return BzErrors.err("invalid_json", "failed to parse JSON: %s" % path, "", path)
	return parsed


static func _empty_dirty(variants: Variant = null) -> Dictionary:
	var list: Array = [""]
	if variants != null:
		list = []
		for v in variants:
			list.append(str(v))
	var objects := {}
	for v in list:
		objects[str(v)] = []
	return {
		"terrain": false,
		"materials": false,
		"objects": objects,
		"features": false,
		"meta": [],
	}


static func _grid_words(grid: Variant) -> PackedInt32Array:
	if grid is PackedInt32Array:
		return grid
	if typeof(grid) == TYPE_DICTIONARY:
		return _grid_words((grid as Dictionary).get("data"))
	if grid is Object:
		return _grid_words(grid.get("data"))
	return PackedInt32Array()


static func _write_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	var parent: String = path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return BzErrors.err(
			"write_failed",
			"cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())],
			"",
			path
		)
	file.store_buffer(bytes)
	file.close()
	return {"ok": true}


static func _write_u16_le(path: String, values: PackedInt32Array) -> Dictionary:
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 2)
	for i in values.size():
		bytes.encode_u16(i * 2, values[i] & 0xFFFF)
	return _write_bytes(path, bytes)


static func _write_terrain_r16(path: String, heightmap: Variant) -> Dictionary:
	var words: PackedInt32Array = _grid_words(heightmap)
	var masked := PackedInt32Array()
	masked.resize(words.size())
	for i in words.size():
		masked[i] = words[i] & HEIGHT_MASK
	return _write_u16_le(path, masked)


static func _write_hg2_flags(path: String, heightmap: Variant) -> Dictionary:
	var words: PackedInt32Array = _grid_words(heightmap)
	var flags := PackedByteArray()
	flags.resize(words.size())
	for i in words.size():
		flags[i] = (words[i] >> FLAG_SHIFT) & 0xFF
	return _write_bytes(path, flags)


static func _write_materials_u16(path: String, grid: Variant) -> Dictionary:
	return _write_u16_le(path, _grid_words(grid))


static func _copy_into_residue(source_files: Array, source_dir: String) -> Variant:
	var err: Error = DirAccess.make_dir_recursive_absolute(source_dir)
	if err != OK and not DirAccess.dir_exists_absolute(source_dir):
		return BzErrors.err(
			"write_failed",
			"cannot create residue source dir: %s" % source_dir,
			"",
			source_dir
		)
	var copied: Array = []
	for src_v in source_files:
		var src: String = str(src_v)
		var dest: String = source_dir.path_join(src.get_file())
		if _abspath(src) == _abspath(dest):
			copied.append(dest)
			continue
		var copy_err: Error = DirAccess.copy_absolute(src, dest)
		if copy_err != OK:
			return BzErrors.err(
				"write_failed",
				"cannot copy %s to %s (%s)" % [src, dest, error_string(copy_err)],
				"",
				src
			)
		copied.append(dest)
	return copied


static func _find_source_file(source_dir: String, stem: String, suffix: String) -> String:
	var target: String = (stem + suffix).to_lower()
	for p in _list_files(source_dir):
		if p.get_file().to_lower() == target:
			return p
	return ""


static func _variant_bzn_suffix(variant: String) -> String:
	return "%s.bzn" % variant if not variant.is_empty() else ".bzn"


static func _collect_map_files(root: String, stem: String) -> Array:
	var stem_l: String = stem.to_lower()
	var found: Array = []
	for p in _list_files(root):
		var name: String = p.get_file()
		var lower: String = name.to_lower()
		var name_stem: String = name.get_basename()
		var base: String = name_stem
		for suffix in _VARIANT_STEM_SUFFIXES:
			if base.to_upper().ends_with(suffix):
				base = base.substr(0, base.length() - suffix.length())
				break
		if base.to_lower() == stem_l:
			found.append(p)
			continue
		if lower == "%smap.lua" % stem_l:
			found.append(p)
			continue
		if lower.begins_with(stem_l + ".") or lower.begins_with(stem_l + "_"):
			found.append(p)
	found.sort_custom(func(a, b): return str(a).get_file().to_lower() < str(b).get_file().to_lower())
	return found


static func _resolve_map_input(path: String) -> Dictionary:
	path = _expand_user(path)
	if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
		return BzErrors.err(
			"not_found",
			"no such file or directory: %s" % path,
			"",
			path
		)
	var directory: String
	var stem: String
	if DirAccess.dir_exists_absolute(path):
		directory = path
		var candidates: Array = []
		for p in _list_files(path):
			var suf: String = str(p).get_extension().to_lower()
			if suf == "trn" or suf == "hg2" or suf == "bzn" or suf == "mat":
				candidates.append(p)
		if candidates.is_empty():
			return BzErrors.err(
				"no_map_files",
				"no map files in %s" % path,
				"point at a .trn / .bzn / .hg2 or the directory that holds them",
				path
			)
		var chosen: String = str(candidates[0])
		var chosen_len: int = chosen.get_file().get_basename().length()
		for p in candidates:
			var n: int = str(p).get_file().get_basename().length()
			if n < chosen_len:
				chosen = str(p)
				chosen_len = n
		stem = _strip_variant(chosen.get_file().get_basename())
	else:
		directory = path.get_base_dir()
		stem = _strip_variant(path.get_file().get_basename())
	var files: Array = _collect_map_files(directory, stem)
	if files.is_empty():
		return BzErrors.err(
			"no_map_files",
			"no files for stem '%s' in %s" % [stem, directory],
			"",
			directory
		)
	return {
		"ok": true,
		"directory": directory,
		"stem": stem,
		"files": files,
	}


static func _write_manifest(path: String, fields: Dictionary = {}) -> Variant:
	var payload := {"contract_version": CONTRACT_VERSION}
	for key in fields.keys():
		payload[key] = fields[key]
	var wr: Dictionary = _write_json(path, payload)
	if BzErrors.is_err(wr):
		return wr
	return payload


static func _height_over_ceiling(heightmap: Variant) -> bool:
	var words: PackedInt32Array = _grid_words(heightmap)
	for i in words.size():
		if (words[i] & HEIGHT_MASK) > 4095:
			return true
	return false


static func _strip_variant(stem: String) -> String:
	var upper: String = stem.to_upper()
	for suffix in _VARIANT_STEM_SUFFIXES:
		if upper.ends_with(suffix):
			return stem.substr(0, stem.length() - suffix.length())
	return stem


static func _list_files(dir_path: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	da.include_hidden = true
	da.include_navigational = false
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		if not da.current_is_dir():
			out.append(dir_path.path_join(fn))
		fn = da.get_next()
	da.list_dir_end()
	return out


static func _expand_user(path: String) -> String:
	if path == "~" or path.begins_with("~/") or path.begins_with("~\\"):
		var home: String = OS.get_environment("HOME")
		if home.is_empty():
			home = OS.get_environment("USERPROFILE")
		if path == "~":
			return home
		return home.path_join(path.substr(2))
	return path
