extends RefCounted
class_name BzSession
## Session directory layout and buffer helpers (docs/02 §1, session.py).
##
## Fallible helpers return the Python value on success, or BzErrors.err()
## (check with BzErrors.is_err). Python **kwargs become a Dictionary.

const CONTRACT_VERSION: int = 1
const HEIGHT_MASK: int = 0x1FFF
const FLAG_SHIFT: int = 13
const VARIANT_SUFFIXES: Array[String] = ["", "_S", "_ST", "_SW"]

const _VARIANT_STEM_SUFFIXES: Array[String] = ["_SW", "_ST", "_MS", "_S"]


static func session_paths(session_dir: String) -> Dictionary:
	var root: String = session_dir
	var residue: String = root.path_join("residue")
	return {
		"root": root,
		"manifest": root.path_join("manifest.json"),
		"terrain": root.path_join("terrain.r16"),
		"materials": root.path_join("materials.u16"),
		"objects": root.path_join("objects.json"),
		"features": root.path_join("features.json"),
		"meta": root.path_join("meta.json"),
		"dirty": root.path_join("dirty.json"),
		"report": root.path_join("report.json"),
		"masks": root.path_join("masks"),
		"residue": residue,
		"source": residue.path_join("source"),
		"hg2_header": residue.path_join("hg2_header.json"),
		"hg2_flags": residue.path_join("hg2_flags.u8"),
	}


static func ensure_session_dir(session_dir: String) -> Dictionary:
	var paths: Dictionary = session_paths(session_dir)
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


static func write_json(path: String, payload: Variant) -> Dictionary:
	var text: String = JSON.stringify(payload, "  ")
	if text.is_empty() and typeof(payload) != TYPE_NIL:
		# JSON.stringify returns "" on failure; an empty object is "{}".
		if typeof(payload) != TYPE_DICTIONARY and typeof(payload) != TYPE_ARRAY:
			pass
		elif typeof(payload) == TYPE_DICTIONARY and (payload as Dictionary).is_empty():
			text = "{}"
		elif typeof(payload) == TYPE_ARRAY and (payload as Array).is_empty():
			text = "[]"
		else:
			return BzErrors.err(
				"write_failed",
				"failed to serialize JSON: %s" % path,
				"",
				path
			)
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


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return BzErrors.err(
			"not_found",
			"no such file or directory: %s" % path,
			"",
			path
		)
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null and text.strip_edges() != "null":
		return BzErrors.err(
			"invalid_json",
			"failed to parse JSON: %s" % path,
			"",
			path
		)
	return parsed


static func empty_dirty(variants: Variant = null) -> Dictionary:
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


static func write_terrain_r16(path: String, heightmap: Variant) -> Dictionary:
	var words: PackedInt32Array = _grid_words(heightmap)
	var masked := PackedInt32Array()
	masked.resize(words.size())
	for i in words.size():
		masked[i] = words[i] & HEIGHT_MASK
	return _write_u16_le(path, masked)


static func write_hg2_flags(path: String, heightmap: Variant) -> Dictionary:
	var words: PackedInt32Array = _grid_words(heightmap)
	var flags := PackedByteArray()
	flags.resize(words.size())
	for i in words.size():
		flags[i] = (words[i] >> FLAG_SHIFT) & 0xFF
	return _write_bytes(path, flags)


static func write_materials_u16(path: String, grid: Variant) -> Dictionary:
	return _write_u16_le(path, _grid_words(grid))


static func read_terrain_r16(path: String, grid_z: int, grid_x: int) -> Variant:
	var raw: Variant = _read_u16_le(path)
	if BzErrors.is_err(raw):
		return raw
	var samples: PackedInt32Array = raw
	var expected: int = grid_z * grid_x
	if samples.size() != expected:
		return BzErrors.err(
			"terrain_size_mismatch",
			"terrain.r16 has %d samples, expected %d (%dx%d)"
			% [samples.size(), expected, grid_z, grid_x],
			"",
			path
		)
	return samples


static func read_hg2_flags(path: String, grid_z: int, grid_x: int) -> Variant:
	if not FileAccess.file_exists(path):
		return BzErrors.err(
			"not_found",
			"no such file or directory: %s" % path,
			"",
			path
		)
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var expected: int = grid_z * grid_x
	if raw.size() != expected:
		return BzErrors.err(
			"flags_size_mismatch",
			"hg2_flags.u8 has %d samples, expected %d" % [raw.size(), expected],
			"",
			path
		)
	return raw


static func read_materials_u16(path: String, grid_z: int, grid_x: int) -> Variant:
	var raw: Variant = _read_u16_le(path)
	if BzErrors.is_err(raw):
		return raw
	var samples: PackedInt32Array = raw
	var expected: int = grid_z * grid_x
	if samples.size() != expected:
		return BzErrors.err(
			"materials_size_mismatch",
			"materials.u16 has %d samples, expected %d" % [samples.size(), expected],
			"",
			path
		)
	return BzMat.MaterialGrid.new(samples, grid_z, grid_x)


static func reconstruct_heightmap(paths: Dictionary, header: Dictionary) -> Variant:
	var zones_x: int = int(header.get("zonesX", 0))
	var zones_z: int = int(header.get("zonesZ", 0))
	var grid_x: int = zones_x * BzHg2.ZONE_SIZE
	var grid_z: int = zones_z * BzHg2.ZONE_SIZE
	var heights_v: Variant = read_terrain_r16(str(paths.get("terrain", "")), grid_z, grid_x)
	if BzErrors.is_err(heights_v):
		return heights_v
	var heights: PackedInt32Array = heights_v
	var flags := PackedByteArray()
	flags.resize(grid_z * grid_x)
	var flags_path: String = str(paths.get("hg2_flags", ""))
	if FileAccess.file_exists(flags_path):
		var flags_v: Variant = read_hg2_flags(flags_path, grid_z, grid_x)
		if BzErrors.is_err(flags_v):
			return flags_v
		flags = flags_v
	var words := PackedInt32Array()
	words.resize(heights.size())
	for i in heights.size():
		var fl: int = flags[i] if i < flags.size() else 0
		words[i] = ((fl << FLAG_SHIFT) | (heights[i] & HEIGHT_MASK)) & 0xFFFF
	return BzHg2.HeightMap.new(
		zones_x,
		zones_z,
		words,
		int(header.get("version", 1)),
		int(header.get("depth", 8)),
		int(header.get("unknownA", 10)),
		int(header.get("unknownB", 0))
	)


static func copy_into_residue(source_files: Array, source_dir: String) -> Variant:
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
		if _same_path(src, dest):
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


static func find_source_file(source_dir: String, stem: String, suffix: String) -> String:
	var target: String = (stem + suffix).to_lower()
	for p in _list_files(source_dir):
		if p.get_file().to_lower() == target:
			return p
	return ""


static func variant_bzn_suffix(variant: String) -> String:
	return "%s.bzn" % variant if not variant.is_empty() else ".bzn"


static func collect_map_files(root: String, stem: String) -> Array:
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


static func resolve_map_input(path: String) -> Dictionary:
	path = _expand_user(path)
	if not _exists(path):
		return BzErrors.err(
			"not_found",
			"no such file or directory: %s" % path,
			"",
			path
		)
	var directory: String
	var stem: String
	if _is_dir(path):
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
	var files: Array = collect_map_files(directory, stem)
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


static func write_manifest(path: String, fields: Dictionary = {}) -> Variant:
	var payload := {"contract_version": CONTRACT_VERSION}
	for key in fields.keys():
		payload[key] = fields[key]
	var wr: Dictionary = write_json(path, payload)
	if BzErrors.is_err(wr):
		return wr
	return payload


static func height_over_ceiling(heightmap: Variant) -> bool:
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


static func _grid_words(grid: Variant) -> PackedInt32Array:
	if grid is PackedInt32Array:
		return grid
	if grid is PackedByteArray:
		var bytes: PackedByteArray = grid
		var out := PackedInt32Array()
		out.resize(bytes.size() / 2)
		for i in out.size():
			out[i] = bytes.decode_u16(i * 2)
		return out
	if typeof(grid) == TYPE_DICTIONARY:
		return _grid_words((grid as Dictionary).get("data"))
	if grid is Object:
		return _grid_words(grid.get("data"))
	if grid is Array:
		var arr: Array = grid
		var out := PackedInt32Array()
		if arr.is_empty():
			return out
		if typeof(arr[0]) == TYPE_ARRAY or arr[0] is PackedInt32Array:
			for row in arr:
				for v in row:
					out.append(int(v))
			return out
		for v in arr:
			out.append(int(v))
		return out
	return PackedInt32Array()


static func _write_u16_le(path: String, values: PackedInt32Array) -> Dictionary:
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 2)
	for i in values.size():
		bytes.encode_u16(i * 2, values[i] & 0xFFFF)
	return _write_bytes(path, bytes)


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


static func _read_u16_le(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return BzErrors.err(
			"not_found",
			"no such file or directory: %s" % path,
			"",
			path
		)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() % 2 != 0:
		return BzErrors.err(
			"terrain_size_mismatch",
			"%s has %d bytes (not a whole number of uint16 samples)" % [path, bytes.size()],
			"",
			path
		)
	var out := PackedInt32Array()
	out.resize(bytes.size() / 2)
	for i in out.size():
		out[i] = bytes.decode_u16(i * 2)
	return out


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


static func _exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


static func _is_dir(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path)


static func _expand_user(path: String) -> String:
	if path == "~" or path.begins_with("~/") or path.begins_with("~\\"):
		var home: String = OS.get_environment("HOME")
		if home.is_empty():
			home = OS.get_environment("USERPROFILE")
		if path == "~":
			return home
		return home.path_join(path.substr(2))
	return path


static func _same_path(a: String, b: String) -> bool:
	return _resolve_path(a) == _resolve_path(b)


static func _resolve_path(path: String) -> String:
	var p: String = _expand_user(path)
	if p.is_absolute_path():
		return p.simplify_path()
	var cwd := DirAccess.open(".")
	if cwd == null:
		return p.simplify_path()
	return cwd.get_current_dir().path_join(p).simplify_path()
