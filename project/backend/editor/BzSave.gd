extends RefCounted
class_name BzSave
## ``bzmap editor save`` — session directory -> map file set.
##
## Port of ``backend/bzmap/editor/save.py``. Untouched inputs are copied from
## ``residue/source/`` byte for byte. Only domains marked in ``dirty.json``
## are re-encoded. Open→save with no edits is byte-identical by construction.

const _EOL := "\r\n"


static func save_session(session_dir: String, out_dir: String, stem: String = "") -> Dictionary:
	## Write the session to ``out_dir``. Returns the docs/02 §3 save payload.
	var paths: Dictionary = _session_paths(session_dir)
	if not FileAccess.file_exists(str(paths["manifest"])):
		return BzErrors.err(
			"no_session",
			"no manifest.json in %s" % session_dir,
			"open or new a map first",
			session_dir
		)
	var manifest_v: Variant = _read_json(str(paths["manifest"]))
	if BzErrors.is_err(manifest_v):
		return manifest_v
	if typeof(manifest_v) != TYPE_DICTIONARY:
		return BzErrors.err("invalid_json", "manifest.json is not an object", "", str(paths["manifest"]))
	var manifest: Dictionary = manifest_v
	var dirty := {}
	if FileAccess.file_exists(str(paths["dirty"])):
		var dirty_v: Variant = _read_json(str(paths["dirty"]))
		if BzErrors.is_err(dirty_v):
			return dirty_v
		if typeof(dirty_v) == TYPE_DICTIONARY:
			dirty = dirty_v
	var source_stem: String = str(manifest.get("stem", ""))
	var out_stem: String = stem if not stem.is_empty() else source_stem
	if out_stem.is_empty():
		return BzErrors.err("no_stem", "manifest has no stem and --stem was not given")
	var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(out_dir)
	if mkdir_err != OK and not DirAccess.dir_exists_absolute(out_dir):
		return BzErrors.err(
			"write_failed",
			"cannot create out dir: %s" % out_dir,
			"",
			out_dir
		)
	var source_dir: String = str(paths["source"])
	if not DirAccess.dir_exists_absolute(source_dir):
		return BzErrors.err(
			"no_residue",
			"session has no residue/source: %s" % source_dir,
			"",
			source_dir
		)
	var residue_files: Array = _list_files(source_dir)
	var written: Array = []
	var identical: Array = []
	var regenerated: Array = []
	var warnings: Array = []

	# Pass 1: copy or skip every residue file. We'll overwrite dirty domains.
	for src in residue_files:
		var dest: String = out_dir.path_join(_out_name(str(src), source_stem, out_stem))
		var cp: Dictionary = _copy_source(str(src), dest)
		if BzErrors.is_err(cp):
			return cp
		written.append(dest.get_file())

	# Terrain
	if _truthy(dirty.get("terrain")):
		var header_v: Variant = _read_json(str(paths["hg2_header"]))
		if BzErrors.is_err(header_v):
			return header_v
		if typeof(header_v) != TYPE_DICTIONARY:
			return BzErrors.err("invalid_json", "hg2_header.json is not an object", "", str(paths["hg2_header"]))
		var heightmap_v: Variant = _reconstruct_heightmap(paths, header_v)
		if BzErrors.is_err(heightmap_v):
			return heightmap_v
		var heightmap: BzHg2.HeightMap = heightmap_v as BzHg2.HeightMap
		if heightmap == null:
			return BzErrors.err("value_error", "reconstruct_heightmap did not return a HeightMap")
		var dest_hg2: String = out_dir.path_join("%s.hg2" % out_stem)
		var wr: Dictionary = heightmap.write(dest_hg2)
		if typeof(wr) == TYPE_DICTIONARY and wr.get("ok") == false:
			return wr
		if not written.has(dest_hg2.get_file()):
			written.append(dest_hg2.get_file())
		regenerated.append(dest_hg2.get_file())
		warnings.append("terrain re-encoded from terrain.r16")
	else:
		var dest_hg2_c: String = out_dir.path_join("%s.hg2" % out_stem)
		var src_hg2: String = _find_source_file(source_dir, source_stem, ".hg2")
		if (
			not src_hg2.is_empty()
			and FileAccess.file_exists(dest_hg2_c)
			and _same_bytes(dest_hg2_c, src_hg2)
		):
			identical.append(dest_hg2_c.get_file())

	# Materials
	if _truthy(dirty.get("materials")):
		var mat_x: int = int(manifest["mat_grid_x"])
		var mat_z: int = int(manifest["mat_grid_z"])
		var raw_v: Variant = _read_materials_u16(str(paths["materials"]), mat_z, mat_x)
		if BzErrors.is_err(raw_v):
			return raw_v
		var grid: BzMat.MaterialGrid = raw_v as BzMat.MaterialGrid
		if grid == null:
			return BzErrors.err("value_error", "materials.u16 did not yield a MaterialGrid")
		var dest_mat: String = out_dir.path_join("%s.mat" % out_stem)
		var wr_mat: Dictionary = grid.write(dest_mat)
		if typeof(wr_mat) == TYPE_DICTIONARY and wr_mat.get("ok") == false:
			return wr_mat
		if not written.has(dest_mat.get_file()):
			written.append(dest_mat.get_file())
		regenerated.append(dest_mat.get_file())
	else:
		var dest_mat_c: String = out_dir.path_join("%s.mat" % out_stem)
		var src_mat: String = _find_source_file(source_dir, source_stem, ".mat")
		if (
			not src_mat.is_empty()
			and FileAccess.file_exists(dest_mat_c)
			and _same_bytes(dest_mat_c, src_mat)
		):
			identical.append(dest_mat_c.get_file())

	# Objects
	if _objects_dirty(dirty):
		var objects_v: Variant = _read_json(str(paths["objects"]))
		if BzErrors.is_err(objects_v):
			return objects_v
		if typeof(objects_v) != TYPE_DICTIONARY:
			return BzErrors.err("invalid_json", "objects.json is not an object", "", str(paths["objects"]))
		var objects: Dictionary = objects_v
		var dirty_objects := {}
		var objects_field: Variant = dirty.get("objects")
		if typeof(objects_field) == TYPE_DICTIONARY:
			dirty_objects = objects_field
		for variant in objects.keys():
			var records_v: Variant = objects[variant]
			var records: Array = records_v if typeof(records_v) == TYPE_ARRAY else []
			var touched: Dictionary = _touched_set(dirty_objects, str(variant), objects_field, records)
			var dest_bzn: String = out_dir.path_join(
				"%s%s" % [out_stem, _variant_bzn_suffix(str(variant))]
			)
			var src_bzn: String = _find_source_file(
				source_dir, source_stem, _variant_bzn_suffix(str(variant))
			)
			if src_bzn.is_empty():
				warnings.append(
					"no residue BZN for variant %s; skipped" % _py_repr(str(variant))
				)
				continue
			if touched.is_empty():
				var cp_b: Dictionary = _copy_source(src_bzn, dest_bzn)
				if BzErrors.is_err(cp_b):
					return cp_b
				continue
			var applied: Dictionary = _apply_objects(
				src_bzn, dest_bzn, records, touched, source_dir, out_dir, out_stem, str(variant), warnings
			)
			if BzErrors.is_err(applied):
				return applied
			if not written.has(dest_bzn.get_file()):
				written.append(dest_bzn.get_file())
			regenerated.append(dest_bzn.get_file())
	else:
		var variants_v: Variant = manifest.get("variants")
		var variants: Array = variants_v if typeof(variants_v) == TYPE_ARRAY else [""]
		for variant in variants:
			var dest_c: String = out_dir.path_join(
				"%s%s" % [out_stem, _variant_bzn_suffix(str(variant))]
			)
			var src_c: String = _find_source_file(
				source_dir, source_stem, _variant_bzn_suffix(str(variant))
			)
			if (
				not src_c.is_empty()
				and FileAccess.file_exists(dest_c)
				and _same_bytes(dest_c, src_c)
			):
				identical.append(dest_c.get_file())

	# Everything else: already copied. Mark byte-identical vs residue.
	for src in residue_files:
		var dest_f: String = out_dir.path_join(_out_name(str(src), source_stem, out_stem))
		if not FileAccess.file_exists(dest_f):
			continue
		if regenerated.has(dest_f.get_file()):
			continue
		if _same_bytes(dest_f, str(src)) and not identical.has(dest_f.get_file()):
			identical.append(dest_f.get_file())

	# Derived-file note: we never invent a .lgt on an untouched save.
	var features := {}
	if FileAccess.file_exists(str(paths["features"])):
		var feat_v: Variant = _read_json(str(paths["features"]))
		if BzErrors.is_err(feat_v):
			return feat_v
		if typeof(feat_v) == TYPE_DICTIONARY:
			features = feat_v
	if not features.is_empty():
		var dest_feat: String = out_dir.path_join("features.json")
		var cp_f: Dictionary = _copy_source(str(paths["features"]), dest_feat)
		if BzErrors.is_err(cp_f):
			return cp_f
		if not written.has(dest_feat.get_file()):
			written.append(dest_feat.get_file())
	return {
		"ok": true,
		"files": _sorted_unique(written),
		"byte_identical": _sorted_unique(identical),
		"regenerated": _sorted_unique(regenerated),
		"warnings": warnings,
		"out": _abs(out_dir),
		"stem": out_stem,
		"features": features,
	}


static func _apply_objects(
	src_bzn: String,
	dest_bzn: String,
	records: Array,
	touched: Dictionary,
	source_dir: String,
	out_dir: String,
	out_stem: String,
	variant: String,
	warnings: Array
) -> Dictionary:
	var loaded: Dictionary = BzBzn.read_bzn(src_bzn)
	if not bool(loaded.get("ok", false)):
		if BzErrors.is_err(loaded):
			return loaded
		return BzErrors.err("value_error", "failed to read BZN: %s" % src_bzn, "", src_bzn)
	var bzn: BzBzn.BznFile = loaded.get("bznfile") as BzBzn.BznFile
	if bzn == null:
		return BzErrors.err("value_error", "BzBzn.read_bzn did not return a BznFile", "", src_bzn)
	var by_id := {}
	for rec_v in records:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		by_id[str(rec.get("id", ""))] = rec
	# Source objects were assigned obj-0001 in file order on open.
	var prefix: String = "obj" if variant.is_empty() else "obj%s" % variant.to_lower()
	for i in bzn.objects.size():
		var obj: BzBzn.GameObject = bzn.objects[i]
		var obj_id: String = "%s-%04d" % [prefix, i + 1]
		if touched.has(obj_id) and by_id.has(obj_id):
			BzObjects.apply_record_to_block(obj, by_id[obj_id])
	var new_ids: Array = []
	for obj_id in touched.keys():
		if str(obj_id).begins_with("new-"):
			new_ids.append(str(obj_id))
	var runtime: Array = []
	var next_seq: int = 1
	var next_addr: int = 1
	if not bzn.objects.is_empty():
		var max_seq: int = 0
		var max_addr: int = 0
		for o_v in bzn.objects:
			var o: BzBzn.GameObject = o_v
			var sn: Variant = o.seqno
			var seq_i: int = 0 if sn == null else int(sn)
			if seq_i > max_seq:
				max_seq = seq_i
			var ad: Variant = o.obj_addr
			var addr_i: int = 0 if ad == null else int(ad)
			if addr_i > max_addr:
				max_addr = addr_i
		next_seq = max_seq + 1
		next_addr = max_addr + 1
	for obj_id in new_ids:
		if not by_id.has(obj_id):
			continue
		var rec_n: Dictionary = by_id[obj_id]
		if (
			str(rec_n.get("placement_mode", "")) == "runtime"
			or rec_n.get("template_verified") == false
		):
			runtime.append(rec_n)
			continue
		var text: String = BzObjects.template_text_for(str(rec_n.get("prjid", "")), source_dir)
		if text.is_empty():
			runtime.append(rec_n)
			warnings.append(
				"%s: no verified same-class block; emitting as runtime spawn" % str(rec_n.get("prjid", ""))
			)
			continue
		var clone: BzBzn.GameObject = BzBzn.GameObject.from_template(text)
		BzObjects.apply_record_to_block(clone, rec_n)
		var label: String = str(rec_n.get("label", ""))
		if label.is_empty():
			label = "%s%d" % [str(rec_n.get("prjid", "")), next_seq]
		clone.set_identity(next_seq, next_addr, label)
		next_seq += 1
		next_addr += 1
		bzn.add_object(clone)
	if not runtime.is_empty():
		_append_runtime_spawns(out_dir, out_stem, variant, runtime, warnings)
	bzn.set_header("size [1]", bzn.objects.size())
	bzn.set_header("seq_count [1]", next_seq)
	var wr: Dictionary = BzBzn.write_bzn(dest_bzn, bzn)
	if typeof(wr) == TYPE_DICTIONARY and wr.get("ok") == false:
		return wr
	return {"ok": true}


static func _objects_dirty(dirty: Dictionary) -> bool:
	var objects: Variant = dirty.get("objects")
	if objects == null:
		return false
	if typeof(objects) == TYPE_BOOL:
		return bool(objects)
	if typeof(objects) == TYPE_DICTIONARY:
		for v in (objects as Dictionary).values():
			if _truthy(v):
				return true
		return false
	return _truthy(objects)


static func _touched_set(
	dirty_objects: Dictionary, variant: String, objects_field: Variant, records: Array
) -> Dictionary:
	var touched := {}
	if typeof(objects_field) == TYPE_BOOL and objects_field:
		# Python would call True.get(...) and crash; treat as "all listed ids".
		for rec_v in records:
			if typeof(rec_v) == TYPE_DICTIONARY:
				touched[str((rec_v as Dictionary).get("id", ""))] = true
		return touched
	var listed: Variant = dirty_objects.get(variant)
	if typeof(listed) == TYPE_ARRAY:
		for v in listed:
			if _truthy(v):
				touched[str(v)] = true
	return touched


static func _append_runtime_spawns(
	out_dir: String, stem: String, variant: String, records: Array, warnings: Array
) -> void:
	## Append host-guarded BuildObject calls to ``<stem>MAP.lua``.
	##
	## Unverified classes must not become invented BZN blocks. The BZP map
	## script hook is the documented runtime path.
	if records.is_empty():
		return
	var path: String = out_dir.path_join("%sMAP.lua" % stem)
	var existing: String = ""
	if FileAccess.file_exists(path):
		existing = FileAccess.get_file_as_string(path)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("")
	lines.append("-- bzmap editor: runtime spawns (unverified classes; host only)")
	lines.append("-- variant %s" % _py_repr(variant))
	lines.append("if IsHosting and IsHosting() then")
	for rec_v in records:
		var rec: Dictionary = rec_v
		var prjid_v: Variant = rec.get("prjid")
		var prjid: String = "unknown" if prjid_v == null or str(prjid_v) == "" else str(prjid_v)
		var x: float = float(rec.get("x", 0.0))
		var y: float = float(rec.get("y", 0.0))
		var z: float = float(rec.get("z", 0.0))
		var team: int = int(rec.get("team", 0)) if rec.get("team") != null else 0
		lines.append(
			'  do local h = BuildObject("%s", %d, SetVector(%.3f, %.3f, %.3f))'
			% [prjid, team, x, y, z]
		)
		lines.append("    if h and RemovePilot then RemovePilot(h) end")
		lines.append("  end")
	lines.append("end")
	var text: String = existing + _EOL.join(lines) + _EOL
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(text.to_utf8_buffer())
	f.close()
	warnings.append(
		"variant %s: %d unverified class(es) written as runtime spawns in %s"
		% [_py_repr(variant), records.size(), path.get_file()]
	)


static func _copy_source(src: String, dest: String) -> Dictionary:
	var parent: String = dest.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
	var err: Error = DirAccess.copy_absolute(src, dest)
	if err != OK:
		return BzErrors.err(
			"write_failed",
			"cannot copy %s to %s (%s)" % [src, dest, error_string(err)],
			"",
			src
		)
	return {"ok": true}


static func _out_name(src_path: String, source_stem: String, out_stem: String) -> String:
	## Rename a residue file onto ``out_stem`` keeping variant/suffix.
	var name: String = src_path.get_file()
	var lower: String = name.to_lower()
	var src_l: String = source_stem.to_lower()
	if lower.begins_with(src_l):
		return out_stem + name.substr(source_stem.length())
	return name


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


static func _same_bytes(a: String, b: String) -> bool:
	return FileAccess.get_file_as_bytes(a) == FileAccess.get_file_as_bytes(b)


static func _sorted_unique(items: Array) -> Array:
	var seen := {}
	var out: Array = []
	for v in items:
		var s: String = str(v)
		if seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	out.sort()
	return out


static func _truthy(v: Variant) -> bool:
	## Python-truthiness. Godot treats empty Array/Dictionary as true.
	if v == null:
		return false
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_ARRAY:
			return not (v as Array).is_empty()
		TYPE_DICTIONARY:
			return not (v as Dictionary).is_empty()
		TYPE_STRING:
			return not (v as String).is_empty()
		TYPE_INT, TYPE_FLOAT:
			return v != 0
		_:
			return true


static func _py_repr(s: String) -> String:
	## Python ``repr`` for simple strings (single quotes).
	return "'%s'" % s.replace("\\", "\\\\").replace("'", "\\'")


static func _abs(path: String) -> String:
	if path.is_absolute_path():
		return path.simplify_path()
	var cwd := DirAccess.open(".")
	if cwd == null:
		return ProjectSettings.globalize_path(path).simplify_path()
	return cwd.get_current_dir().path_join(path).simplify_path()


# -- private copies of BzSession helpers (BzSession.gd currently fails to
# compile on Godot 4.7.1: String.is_absolute() does not exist) ---------------

const _HEIGHT_MASK := 0x1FFF
const _FLAG_SHIFT := 13
const _ZONE_SIZE := 256


static func _session_paths(session_dir: String) -> Dictionary:
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


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return BzErrors.err("not_found", "no such file or directory: %s" % path, "", path)
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null and text.strip_edges() != "null":
		return BzErrors.err("invalid_json", "failed to parse JSON: %s" % path, "", path)
	return parsed


static func _find_source_file(source_dir: String, stem: String, suffix: String) -> String:
	var target: String = (stem + suffix).to_lower()
	for p in _list_files(source_dir):
		if str(p).get_file().to_lower() == target:
			return str(p)
	return ""


static func _variant_bzn_suffix(variant: String) -> String:
	return "%s.bzn" % variant if not variant.is_empty() else ".bzn"


static func _reconstruct_heightmap(paths: Dictionary, header: Dictionary) -> Variant:
	var zones_x: int = int(header.get("zonesX", 0))
	var zones_z: int = int(header.get("zonesZ", 0))
	var grid_x: int = zones_x * _ZONE_SIZE
	var grid_z: int = zones_z * _ZONE_SIZE
	var heights_v: Variant = _read_u16(str(paths.get("terrain", "")), grid_z * grid_x, "terrain")
	if BzErrors.is_err(heights_v):
		return heights_v
	var heights: PackedInt32Array = heights_v
	var flags := PackedByteArray()
	flags.resize(grid_z * grid_x)
	var flags_path: String = str(paths.get("hg2_flags", ""))
	if FileAccess.file_exists(flags_path):
		var raw: PackedByteArray = FileAccess.get_file_as_bytes(flags_path)
		if raw.size() != grid_z * grid_x:
			return BzErrors.err(
				"flags_size_mismatch",
				"hg2_flags.u8 has %d samples, expected %d" % [raw.size(), grid_z * grid_x],
				"",
				flags_path
			)
		flags = raw
	var words := PackedInt32Array()
	words.resize(heights.size())
	for i in heights.size():
		var fl: int = flags[i] if i < flags.size() else 0
		words[i] = ((fl << _FLAG_SHIFT) | (heights[i] & _HEIGHT_MASK)) & 0xFFFF
	return BzHg2.HeightMap.new(
		zones_x,
		zones_z,
		words,
		int(header.get("version", 1)),
		int(header.get("depth", 8)),
		int(header.get("unknownA", 10)),
		int(header.get("unknownB", 0))
	)


static func _read_materials_u16(path: String, grid_z: int, grid_x: int) -> Variant:
	var raw_v: Variant = _read_u16(path, grid_z * grid_x, "materials")
	if BzErrors.is_err(raw_v):
		return raw_v
	return BzMat.MaterialGrid.new(raw_v, grid_z, grid_x)


static func _read_u16(path: String, expected: int, kind: String) -> Variant:
	if not FileAccess.file_exists(path):
		return BzErrors.err("not_found", "no such file or directory: %s" % path, "", path)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var n: int = bytes.size() / 2
	if n != expected:
		var code: String = "terrain_size_mismatch" if kind == "terrain" else "materials_size_mismatch"
		return BzErrors.err(
			code,
			"%s has %d samples, expected %d" % [path.get_file(), n, expected],
			"",
			path
		)
	var out := PackedInt32Array()
	out.resize(n)
	for i in n:
		out[i] = bytes.decode_u16(i * 2)
	return out
