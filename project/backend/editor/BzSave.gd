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
	var paths: Dictionary = BzSession.session_paths(session_dir)
	if not FileAccess.file_exists(str(paths["manifest"])):
		return BzErrors.err(
			"no_session",
			"no manifest.json in %s" % session_dir,
			"open or new a map first",
			session_dir
		)
	var manifest_v: Variant = BzSession.read_json(str(paths["manifest"]))
	if BzErrors.is_err(manifest_v):
		return manifest_v
	if typeof(manifest_v) != TYPE_DICTIONARY:
		return BzErrors.err("invalid_json", "manifest.json is not an object", "", str(paths["manifest"]))
	var manifest: Dictionary = manifest_v
	var dirty := {}
	if FileAccess.file_exists(str(paths["dirty"])):
		var dirty_v: Variant = BzSession.read_json(str(paths["dirty"]))
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
	var dropped: Array = []
	var warnings: Array = []

	# Pass 1: copy or skip every residue file. We'll overwrite dirty domains.
	for src in residue_files:
		var dest: String = out_dir.path_join(_out_name(str(src), source_stem, out_stem))
		var cp: Dictionary = _copy_source(str(src), dest)
		if BzErrors.is_err(cp):
			return cp
		written.append(dest.get_file())

	# Terrain
	#
	# dirty.json is a hint, and here a hint that fails open ships the wrong map
	# in silence. BzRender.render_session draws the .BMP from terrain.r16 while
	# the else-branch below copies the residue .hg2 byte for byte, so an edit
	# the flag missed leaves a correct-looking thumbnail sitting on top of
	# pre-edit terrain — no error, no warning, every expected file present, and
	# on a map created flat the shipped heightmap is flat everywhere. The buffer
	# is the truth, so when the flag says clean, check it before believing it.
	var terrain_dirty: bool = _truthy(dirty.get("terrain"))
	var terrain_flag_missed: bool = false
	if not terrain_dirty and _terrain_differs_from_residue(paths, source_dir, source_stem):
		terrain_dirty = true
		terrain_flag_missed = true
	if terrain_dirty:
		var header_v: Variant = BzSession.read_json(str(paths["hg2_header"]))
		if BzErrors.is_err(header_v):
			return header_v
		if typeof(header_v) != TYPE_DICTIONARY:
			return BzErrors.err("invalid_json", "hg2_header.json is not an object", "", str(paths["hg2_header"]))
		var heightmap_v: Variant = BzSession.reconstruct_heightmap(paths, header_v)
		if BzErrors.is_err(heightmap_v):
			return heightmap_v
		var heightmap: BzHg2.HeightMap = heightmap_v as BzHg2.HeightMap
		if heightmap == null:
			return BzErrors.err("value_error", "reconstruct_heightmap did not return a HeightMap")
		var dest_hg2: String = _dest_path(out_dir, "%s.hg2" % out_stem)
		var wr: Dictionary = heightmap.write(dest_hg2)
		if typeof(wr) == TYPE_DICTIONARY and wr.get("ok") == false:
			return wr
		if not written.has(dest_hg2.get_file()):
			written.append(dest_hg2.get_file())
		regenerated.append(dest_hg2.get_file())
		warnings.append("terrain re-encoded from terrain.r16")
		if terrain_flag_missed:
			warnings.append(
				"terrain.r16 does not match the residue heightmap but dirty.json "
				+ "did not flag terrain; re-encoded from the session buffer"
			)
		# F3 §3: after a terrain edit the reference editor deletes the .lgt so
		# the game re-bakes lighting on next load. The .LGT layout is unresolved
		# (BzLgt is copy-only), so a bake is impossible here — shipping the
		# residue lightmap would light the OLD geometry. Untouched saves keep
		# their .lgt byte-identical; only a dirty-terrain save drops it.
		for src_lgt in residue_files:
			var dest_name: String = _out_name(str(src_lgt), source_stem, out_stem)
			if dest_name.get_extension().to_lower() != "lgt":
				continue
			var dest_lgt: String = out_dir.path_join(dest_name)
			if FileAccess.file_exists(dest_lgt):
				DirAccess.remove_absolute(dest_lgt)
			written.erase(dest_name)
			dropped.append(dest_name)
			warnings.append(
				"%s dropped after terrain edit; the game re-bakes lighting on next load"
				% dest_name
			)
	else:
		var dest_hg2_c: String = _dest_path(out_dir, "%s.hg2" % out_stem)
		var src_hg2: String = BzSession.find_source_file(source_dir, source_stem, ".hg2")
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
		var raw_v: Variant = BzSession.read_materials_u16(str(paths["materials"]), mat_z, mat_x)
		if BzErrors.is_err(raw_v):
			return raw_v
		var grid: BzMat.MaterialGrid = raw_v as BzMat.MaterialGrid
		if grid == null:
			return BzErrors.err("value_error", "materials.u16 did not yield a MaterialGrid")
		var dest_mat: String = _dest_path(out_dir, "%s.mat" % out_stem)
		var wr_mat: Dictionary = grid.write(dest_mat)
		if typeof(wr_mat) == TYPE_DICTIONARY and wr_mat.get("ok") == false:
			return wr_mat
		if not written.has(dest_mat.get_file()):
			written.append(dest_mat.get_file())
		regenerated.append(dest_mat.get_file())
	else:
		var dest_mat_c: String = _dest_path(out_dir, "%s.mat" % out_stem)
		var src_mat: String = BzSession.find_source_file(source_dir, source_stem, ".mat")
		if (
			not src_mat.is_empty()
			and FileAccess.file_exists(dest_mat_c)
			and _same_bytes(dest_mat_c, src_mat)
		):
			identical.append(dest_mat_c.get_file())

	# Objects
	if _objects_dirty(dirty):
		var objects_v: Variant = BzSession.read_json(str(paths["objects"]))
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
			var dest_bzn: String = _dest_path(
				out_dir, "%s%s" % [out_stem, BzSession.variant_bzn_suffix(str(variant))]
			)
			var src_bzn: String = BzSession.find_source_file(
				source_dir, source_stem, BzSession.variant_bzn_suffix(str(variant))
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
			var dest_c: String = _dest_path(
				out_dir, "%s%s" % [out_stem, BzSession.variant_bzn_suffix(str(variant))]
			)
			var src_c: String = BzSession.find_source_file(
				source_dir, source_stem, BzSession.variant_bzn_suffix(str(variant))
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
		var feat_v: Variant = BzSession.read_json(str(paths["features"]))
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

	# Mesh generation + managed carriers. No-op when water/plants are empty so
	# open→save with no features stays byte-identical.
	var feat_entries: Array = BzMeshGen.collect_entries(features)
	if not feat_entries.is_empty():
		var applied: Dictionary = _apply_features(
			paths, source_dir, source_stem, out_dir, out_stem,
			features, feat_entries, written, regenerated, identical, warnings
		)
		if BzErrors.is_err(applied):
			return applied

	# AiPaths: re-emit only dirty variants. Untouched tails stay residue bytes.
	var aip_applied: Dictionary = _apply_dirty_aipaths(
		session_dir, source_dir, source_stem, out_dir, out_stem,
		manifest, dirty, written, regenerated, identical, warnings
	)
	if BzErrors.is_err(aip_applied):
		return aip_applied
	return {
		"ok": true,
		"files": _sorted_unique(written),
		"byte_identical": _sorted_unique(identical),
		"regenerated": _sorted_unique(regenerated),
		"dropped": _sorted_unique(dropped),
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


static func _apply_dirty_aipaths(
	session_dir: String,
	source_dir: String,
	source_stem: String,
	out_dir: String,
	out_stem: String,
	manifest: Dictionary,
	dirty: Dictionary,
	written: Array,
	regenerated: Array,
	identical: Array,
	warnings: Array
) -> Dictionary:
	var flagged: Dictionary = _aipaths_dirty_variants(dirty, manifest)
	if flagged.is_empty():
		return {"ok": true}
	var aip_path: String = session_dir.path_join("aipaths.json")
	var data := {}
	if FileAccess.file_exists(aip_path):
		var loaded: Variant = BzSession.read_json(aip_path)
		if BzErrors.is_err(loaded):
			return loaded
		if typeof(loaded) == TYPE_DICTIONARY:
			data = loaded
	for variant in flagged.keys():
		if not bool(flagged[variant]):
			continue
		var dest_bzn: String = _dest_path(
			out_dir, "%s%s" % [out_stem, BzSession.variant_bzn_suffix(str(variant))]
		)
		if not FileAccess.file_exists(dest_bzn):
			var src_bzn: String = BzSession.find_source_file(
				source_dir, source_stem, BzSession.variant_bzn_suffix(str(variant))
			)
			if src_bzn.is_empty():
				warnings.append(
					"no residue BZN for AiPaths variant %s; skipped" % _py_repr(str(variant))
				)
				continue
			var cp: Dictionary = _copy_source(src_bzn, dest_bzn)
			if BzErrors.is_err(cp):
				return cp
		var recs: Array = BzOpen.paths_of(data, str(variant))
		var problems: PackedStringArray = BzOpen.aipaths_invariants(recs)
		if not problems.is_empty():
			warnings.append("AiPaths %s: %s" % [str(variant), ", ".join(problems)])
		var raw: PackedByteArray = FileAccess.get_file_as_bytes(dest_bzn)
		var text: String = raw.get_string_from_utf8()
		var spliced: String = BzOpen.splice_aipaths_text(text, recs)
		var wr: Dictionary = _write_text_bytes(dest_bzn, spliced)
		if BzErrors.is_err(wr):
			return wr
		if not written.has(dest_bzn.get_file()):
			written.append(dest_bzn.get_file())
		if not regenerated.has(dest_bzn.get_file()):
			regenerated.append(dest_bzn.get_file())
		var ident_i: int = identical.find(dest_bzn.get_file())
		if ident_i >= 0:
			identical.remove_at(ident_i)
	return {"ok": true}


static func _aipaths_dirty_variants(dirty: Dictionary, manifest: Dictionary) -> Dictionary:
	var field: Variant = dirty.get("aipaths", null)
	if field == null:
		return {}
	var out := {}
	if typeof(field) == TYPE_BOOL:
		if not field:
			return {}
		var variants_v: Variant = manifest.get("variants", [""])
		var variants: Array = variants_v if typeof(variants_v) == TYPE_ARRAY else [""]
		for v in variants:
			out[str(v)] = true
		return out
	if typeof(field) != TYPE_DICTIONARY:
		return {}
	for k in (field as Dictionary).keys():
		if _truthy((field as Dictionary)[k]):
			out[str(k)] = true
	return out


static func _write_text_bytes(path: String, text: String) -> Dictionary:
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
	file.store_buffer(text.to_utf8_buffer())
	file.close()
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
	var path: String = _dest_path(out_dir, "%sMAP.lua" % stem)
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


## True when the session heightfield no longer matches the .hg2 we opened.
##
## Only consulted when dirty.json claims terrain is clean, so the cost lands on
## the save that would otherwise ship stale terrain, not on every save. A
## session we cannot reconstruct or a residue we cannot read answers false:
## this is a safety net over the flag, and the flag already says clean.
static func _terrain_differs_from_residue(
	paths: Dictionary, source_dir: String, source_stem: String
) -> bool:
	var header_path: String = str(paths.get("hg2_header", ""))
	if not FileAccess.file_exists(header_path):
		return false
	var header_v: Variant = BzSession.read_json(header_path)
	if BzErrors.is_err(header_v) or typeof(header_v) != TYPE_DICTIONARY:
		return false
	var session_v: Variant = BzSession.reconstruct_heightmap(paths, header_v)
	if not (session_v is BzHg2.HeightMap):
		return false
	var residue_path: String = BzSession.find_source_file(source_dir, source_stem, ".hg2")
	if residue_path.is_empty():
		return false
	var residue_v: Dictionary = BzHg2.read_hg2(residue_path)
	if not bool(residue_v.get("ok", false)):
		return false
	var residue_hm: BzHg2.HeightMap = residue_v.get("heightmap") as BzHg2.HeightMap
	if residue_hm == null:
		return false
	return (session_v as BzHg2.HeightMap).data != residue_hm.data


static func _out_name(src_path: String, source_stem: String, out_stem: String) -> String:
	## Rename a residue file onto ``out_stem`` keeping variant/suffix.
	var name: String = src_path.get_file()
	var lower: String = name.to_lower()
	var src_l: String = source_stem.to_lower()
	if lower.begins_with(src_l):
		return out_stem + name.substr(source_stem.length())
	return name


static func _dest_path(out_dir: String, name: String) -> String:
	## Destination for a regenerated file, reusing any out_dir entry that
	## differs only in case.
	##
	## Pass 1 copies each residue file under its own name, and shipped file
	## sets are mixed case (``xxPier02.HG2`` next to ``xxPier02.trn``).
	## Building a regenerated name from a hardcoded lowercase suffix targets
	## a DIFFERENT path than the copy on a case-sensitive filesystem: the
	## stale original ships next to the edit as ``.HG2`` + ``.hg2`` and the
	## game may load either. On Windows the two names are one file, so which
	## bytes survive depends on write order and the engine's write-to-temp
	## -then-rename. Either way the edit can vanish with no error.
	var target: String = name.to_lower()
	var da := DirAccess.open(out_dir)
	if da != null:
		for existing in da.get_files():
			if str(existing).to_lower() == target:
				return out_dir.path_join(str(existing))
	return out_dir.path_join(name)


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


# -- feature meshes + managed carriers ---------------------------------------

# Corpus water-carrier basis (desrten1 / thecaven): a -90 deg yaw whose
# det-1 handedness pairs with meshgen's transposed verts. Written verbatim.
const _CARRIER_RIGHT_X := "7.54979e-008"
const _CARRIER_RIGHT_Z := "-1"
const _CARRIER_FRONT_X := "1"
const _CARRIER_FRONT_Z := "7.54979e-008"


static func _apply_features(
	paths: Dictionary,
	source_dir: String,
	source_stem: String,
	out_dir: String,
	out_stem: String,
	features: Dictionary,
	feat_entries: Array,
	written: Array,
	regenerated: Array,
	identical: Array,
	warnings: Array
) -> Dictionary:
	var chk: Dictionary = BzMeshGen.validate_feature_stems(feat_entries, out_stem)
	if BzErrors.is_err(chk):
		return chk
	var heightmap: BzHg2.HeightMap = _load_feature_heightmap(paths, source_dir, source_stem)
	if heightmap == null:
		warnings.append("features present but no heightmap; skipped mesh generation")
		return {"ok": true}
	var gen: Dictionary = BzMeshGen.generate_features(
		str(paths["root"]), out_dir, out_stem, heightmap, features
	)
	if BzErrors.is_err(gen):
		return gen
	for w in gen.get("warnings", []):
		warnings.append(w)
	for fname in gen.get("files", []):
		if not written.has(fname):
			written.append(fname)
		if not regenerated.has(fname):
			regenerated.append(fname)
	var generated: Array = gen.get("generated", [])
	var feature_stems := {}
	for e in feat_entries:
		var st: String = str((e as Dictionary).get("stem", "")).strip_edges().to_lower()
		if not st.is_empty():
			feature_stems[st] = true
	if generated.is_empty() and feature_stems.is_empty():
		return {"ok": true}
	var dest_variants: Array = _dest_bzn_variants(out_dir, out_stem)
	for variant in dest_variants:
		var dest_bzn: String = _dest_path(
			out_dir, "%s%s" % [out_stem, BzSession.variant_bzn_suffix(str(variant))]
		)
		if not FileAccess.file_exists(dest_bzn):
			continue
		var inj: Dictionary = _inject_feature_carriers(
			dest_bzn, generated, feature_stems, str(variant), source_dir, warnings
		)
		if BzErrors.is_err(inj):
			return inj
		if not bool(inj.get("changed", false)):
			continue
		if not written.has(dest_bzn.get_file()):
			written.append(dest_bzn.get_file())
		if not regenerated.has(dest_bzn.get_file()):
			regenerated.append(dest_bzn.get_file())
		var ident_i: int = identical.find(dest_bzn.get_file())
		if ident_i >= 0:
			identical.remove_at(ident_i)
	return {"ok": true}


static func _load_feature_heightmap(
	paths: Dictionary, source_dir: String, source_stem: String
) -> BzHg2.HeightMap:
	var header_path: String = str(paths.get("hg2_header", ""))
	var terrain_path: String = str(paths.get("terrain", ""))
	if FileAccess.file_exists(header_path) and FileAccess.file_exists(terrain_path):
		var header_v: Variant = BzSession.read_json(header_path)
		if not BzErrors.is_err(header_v) and typeof(header_v) == TYPE_DICTIONARY:
			var hm_v: Variant = BzSession.reconstruct_heightmap(paths, header_v)
			if not BzErrors.is_err(hm_v):
				var hm: BzHg2.HeightMap = hm_v as BzHg2.HeightMap
				if hm != null:
					return hm
	var src_hg2: String = BzSession.find_source_file(source_dir, source_stem, ".hg2")
	if src_hg2.is_empty():
		return null
	var rd: Dictionary = BzHg2.read_hg2(src_hg2)
	if not bool(rd.get("ok", false)):
		return null
	return rd.get("heightmap") as BzHg2.HeightMap


static func _dest_bzn_variants(out_dir: String, out_stem: String) -> Array:
	var found: Array = []
	for suffix in ["", "_S", "_ST", "_SW", "_MS"]:
		var path: String = _dest_path(out_dir, "%s%s.bzn" % [out_stem, suffix])
		if FileAccess.file_exists(path):
			found.append(suffix)
	return found


static func _scope_includes(scope: String, variant: String) -> bool:
	var s: String = scope.strip_edges()
	if s.is_empty() or s.to_lower() == "all":
		return true
	if not s.begins_with("_") and s != "":
		s = "_" + s
	return s == variant


static func _inject_feature_carriers(
	dest_bzn: String,
	generated: Array,
	feature_stems: Dictionary,
	variant: String,
	source_dir: String,
	warnings: Array
) -> Dictionary:
	var loaded: Dictionary = BzBzn.read_bzn(dest_bzn)
	if not bool(loaded.get("ok", false)):
		if BzErrors.is_err(loaded):
			return loaded
		return BzErrors.err("value_error", "failed to read BZN: %s" % dest_bzn, "", dest_bzn)
	var bzn: BzBzn.BznFile = loaded.get("bznfile") as BzBzn.BznFile
	if bzn == null:
		return BzErrors.err("value_error", "BzBzn.read_bzn did not return a BznFile", "", dest_bzn)

	var mission: Dictionary = _strip_mission_records(bzn)
	var kept: Array = []
	var stripped := 0
	for obj_v in bzn.objects:
		var obj: BzBzn.GameObject = obj_v
		var prj: String = "" if obj.prjid == null else str(obj.prjid).to_lower()
		if feature_stems.has(prj):
			stripped += 1
			continue
		kept.append(obj)
	bzn.objects = kept

	var to_add: Array = []
	for g_v in generated:
		if typeof(g_v) != TYPE_DICTIONARY:
			continue
		var g: Dictionary = g_v
		if _scope_includes(str(g.get("variant_scope", "all")), variant):
			to_add.append(g)
	if stripped == 0 and to_add.is_empty():
		return {"ok": true, "changed": false}

	var next_seq: int = 1
	var max_seq: int = 0
	for o_v in bzn.objects:
		var sn: Variant = (o_v as BzBzn.GameObject).seqno
		var seq_i: int = 0 if sn == null else int(sn)
		if seq_i > max_seq:
			max_seq = seq_i
	next_seq = max_seq + 1
	if bzn.objects.is_empty():
		next_seq = 1

	var template_text: String = BzObjects.template_text_for("eggeizr1", source_dir)
	if template_text.is_empty():
		template_text = BzTemplates.template("eggeizr1")
	if template_text.is_empty():
		return BzErrors.err(
			"no_template",
			"no verified building block to clone for feature carriers",
			"need BzTemplates eggeizr1 or a same-class residue object"
		)

	for g2 in to_add:
		var stem: String = str((g2 as Dictionary).get("stem", ""))
		var kind: String = str((g2 as Dictionary).get("kind", "water"))
		var carrier: BzBzn.GameObject = _make_feature_carrier(
			template_text, stem, kind, next_seq, bzn.objects.size() + 1
		)
		if carrier == null:
			warnings.append("%s: failed to clone carrier" % stem)
			continue
		bzn.add_object(carrier)
		next_seq += 1

	_reassign_obj_addrs(bzn)
	bzn.set_header("size [1]", bzn.objects.size())
	var seqs_max: int = 0
	var have_seq := false
	for o2 in bzn.objects:
		var sn2: Variant = (o2 as BzBzn.GameObject).seqno
		if sn2 == null:
			continue
		have_seq = true
		if int(sn2) > seqs_max:
			seqs_max = int(sn2)
	if have_seq:
		bzn.set_header("seq_count [1]", seqs_max + 1)
	if bool(mission.get("present", false)):
		_append_mission_record(bzn, str(mission.get("name", "MultSTMission")))
	var wr: Dictionary = BzBzn.write_bzn(dest_bzn, bzn)
	if typeof(wr) == TYPE_DICTIONARY and wr.get("ok") == false:
		return wr
	return {"ok": true, "changed": true}


static func _make_feature_carrier(
	template_text: String, stem: String, kind: String, seqno: int, addr: int
) -> BzBzn.GameObject:
	## Clone the 70-field building template (AGENTS rule 5) and mutate identity,
	## origin, and the corpus carrier basis. Do not re-type a craft block.
	var obj: BzBzn.GameObject = BzBzn.GameObject.from_template(template_text)
	_set_next_value(obj, "PrjID [1]", stem)
	var y: float = -1.0 if kind == "plants" else 0.0
	obj.set_position(0.0, y, 0.0)
	_set_next_value(obj, "right_x [1]", _CARRIER_RIGHT_X)
	_set_next_value(obj, "right_y [1]", "0")
	_set_next_value(obj, "right_z [1]", _CARRIER_RIGHT_Z)
	_set_next_value(obj, "up_x [1]", "0")
	_set_next_value(obj, "up_y [1]", "1")
	_set_next_value(obj, "up_z [1]", "0")
	_set_next_value(obj, "front_x [1]", _CARRIER_FRONT_X)
	_set_next_value(obj, "front_y [1]", "0")
	_set_next_value(obj, "front_z [1]", _CARRIER_FRONT_Z)
	obj.set_team(0)
	obj.set_is_user(false)
	_set_next_value(obj, "isVisible [1]", "1")
	_set_next_value(obj, "seen [1]", "1")
	_set_next_value(obj, "curHealth [1]", "9999999")
	_set_next_value(obj, "maxHealth [1]", "9999999")
	obj.set_identity(seqno, addr, "%s%d" % [stem, seqno])
	return obj


static func _set_next_value(obj: BzBzn.GameObject, key: String, value: String) -> void:
	var lines: PackedStringArray = obj.lines
	var idx: int = BzBzn._value_line_index(lines, key)
	if idx < 0:
		return
	var line: String = lines[idx]
	if line.contains("="):
		var eq: int = line.find("=")
		lines[idx] = line.substr(0, eq + 1) + " " + value
	else:
		lines[idx] = value
	obj.lines = lines


static func _reassign_obj_addrs(bzn: BzBzn.BznFile) -> void:
	for i in bzn.objects.size():
		var obj: BzBzn.GameObject = bzn.objects[i]
		var lines: PackedStringArray = obj.lines
		var aidx: int = BzBzn._value_line_index(lines, "obj_addr")
		if aidx >= 0:
			lines[aidx] = "obj_addr = %08x" % (i + 1)
			obj.lines = lines


static func _strip_mission_records(bzn: BzBzn.BznFile) -> Dictionary:
	var found := {"present": false, "name": "MultSTMission"}
	for obj_v in bzn.objects:
		var obj: BzBzn.GameObject = obj_v
		var lines: PackedStringArray = obj.lines
		while lines.size() > 0 and lines[lines.size() - 1].strip_edges().is_empty():
			lines.resize(lines.size() - 1)
		if lines.size() < 2:
			obj.lines = lines
			continue
		var last: String = lines[lines.size() - 1].strip_edges()
		var prev: String = lines[lines.size() - 2].strip_edges()
		if last.begins_with("sObject =") and prev.begins_with("name ="):
			found["present"] = true
			var nm: String = prev.substr(prev.find("=") + 1).strip_edges()
			if not nm.is_empty():
				found["name"] = nm
			lines.resize(lines.size() - 2)
		obj.lines = lines
	return found


static func _append_mission_record(bzn: BzBzn.BznFile, mission_name: String) -> void:
	if bzn.objects.is_empty():
		return
	var last: BzBzn.GameObject = bzn.objects[bzn.objects.size() - 1]
	var lines: PackedStringArray = last.lines
	lines.append("name = %s" % mission_name)
	lines.append("sObject = %08X" % (bzn.objects.size() + 1))
	last.lines = lines

