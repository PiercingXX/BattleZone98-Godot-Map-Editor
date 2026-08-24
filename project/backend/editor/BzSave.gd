extends RefCounted
class_name BzSave
## ``bzmap editor save`` — session directory -> map file set.
##
## Port of ``backend/bzmap/editor/save.py``. Untouched inputs are copied from
## ``residue/source/`` byte for byte. Only domains marked in ``dirty.json``
## are re-encoded. Open→save with no edits is byte-identical for those files.
## `{stem}.act` is always written from the fog-recolored template when a `.trn`
## is present.

const _EOL := "\r\n"

## Verdicts from comparing the session heightfield against the residue one.
## UNKNOWN is not "same": it means no comparison could be made (no header, no
## residue .hg2, unreadable), and the caller must fall back to dirty.json.
enum { TERRAIN_UNKNOWN, TERRAIN_SAME, TERRAIN_DIFFERS }


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
	# on a map created flat the shipped heightmap is flat everywhere.
	#
	# The buffer is the truth in BOTH directions. A flag that says clean gets
	# checked before it is believed; so does a flag that says dirty, because
	# undo takes an edit back without clearing it. Believing a stale dirty flag
	# re-encodes a heightmap that did not change and — worse — deletes the
	# .lgt below for a lighting bake the geometry never needed.
	#
	# Only an inconclusive comparison leaves the flag in charge.
	var terrain_dirty: bool = _truthy(dirty.get("terrain"))
	var terrain_flag_missed: bool = false
	var compared: Dictionary = _compare_terrain_to_residue(paths, source_dir, source_stem)
	match int(compared.get("verdict", TERRAIN_UNKNOWN)):
		TERRAIN_DIFFERS:
			if not terrain_dirty:
				terrain_dirty = true
				terrain_flag_missed = true
		TERRAIN_SAME:
			terrain_dirty = false
	if terrain_dirty:
		# The comparison above already reconstructed the session heightmap
		# unless it could not look at all; reuse it rather than paying for a
		# second pass over a million samples.
		var heightmap: BzHg2.HeightMap = compared.get("session") as BzHg2.HeightMap
		if heightmap == null:
			var header_v: Variant = BzSession.read_json(str(paths["hg2_header"]))
			if BzErrors.is_err(header_v):
				return header_v
			if typeof(header_v) != TYPE_DICTIONARY:
				return BzErrors.err("invalid_json", "hg2_header.json is not an object", "", str(paths["hg2_header"]))
			var heightmap_v: Variant = BzSession.reconstruct_heightmap(paths, header_v)
			if BzErrors.is_err(heightmap_v):
				return heightmap_v
			heightmap = heightmap_v as BzHg2.HeightMap
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

	# World: sun clock, fog distances, fog-colour palette.
	var world_applied: Dictionary = _apply_world(
		paths, out_dir, out_stem, dirty, written, regenerated, warnings
	)
	if BzErrors.is_err(world_applied):
		return world_applied

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

	# Saving under a new stem renames the files but not what is inside them.
	_restem_identity(out_dir, written, source_stem, out_stem, regenerated, warnings)
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


## Compare the session heightfield against the .hg2 we opened, and say which of
## the three answers it is.
##
## Every failure to look — a session we cannot reconstruct, a residue we cannot
## read — is TERRAIN_UNKNOWN, never TERRAIN_SAME. "I could not check" must not
## read as "nothing changed", or an unreadable residue would silently suppress
## the re-encode that ships the user's edit.
##
## Consulted on every save now, not only when dirty.json claims clean: the flag
## can be wrong in either direction, and a stale dirty flag costs a needless
## re-encode and the .lgt. The cost is one heightmap reconstruction and one
## .hg2 read per save.
## Returns {"verdict": int, "session": HeightMap or null}. The heightmap is the
## reconstruction the comparison had to build anyway; the caller re-encodes from
## it instead of building a second one. It is null exactly when the verdict is
## TERRAIN_UNKNOWN and there was nothing to build.
static func _compare_terrain_to_residue(
	paths: Dictionary, source_dir: String, source_stem: String
) -> Dictionary:
	var unknown := {"verdict": TERRAIN_UNKNOWN, "session": null}
	var header_path: String = str(paths.get("hg2_header", ""))
	if not FileAccess.file_exists(header_path):
		return unknown
	var header_v: Variant = BzSession.read_json(header_path)
	if BzErrors.is_err(header_v) or typeof(header_v) != TYPE_DICTIONARY:
		return unknown
	var session_v: Variant = BzSession.reconstruct_heightmap(paths, header_v)
	if not (session_v is BzHg2.HeightMap):
		return unknown
	var session_hm := session_v as BzHg2.HeightMap
	var residue_path: String = BzSession.find_source_file(source_dir, source_stem, ".hg2")
	if residue_path.is_empty():
		return {"verdict": TERRAIN_UNKNOWN, "session": session_hm}
	var residue_v: Dictionary = BzHg2.read_hg2(residue_path)
	if not bool(residue_v.get("ok", false)):
		return {"verdict": TERRAIN_UNKNOWN, "session": session_hm}
	var residue_hm: BzHg2.HeightMap = residue_v.get("heightmap") as BzHg2.HeightMap
	if residue_hm == null:
		return {"verdict": TERRAIN_UNKNOWN, "session": session_hm}
	# Geometry only. The zone counts come along because a resize changes the
	# sample count, and unknownA/unknownB are carried from the residue header
	# on re-encode either way.
	if session_hm.data != residue_hm.data:
		return {"verdict": TERRAIN_DIFFERS, "session": session_hm}
	if session_hm.zonesX != residue_hm.zonesX or session_hm.zonesZ != residue_hm.zonesZ:
		return {"verdict": TERRAIN_DIFFERS, "session": session_hm}
	return {"verdict": TERRAIN_SAME, "session": session_hm}


## Point a renamed map's internal references at its own name.
##
## Pass 1 renames residue files onto ``out_stem`` but ships their bytes as-is,
## so a map saved under a new stem still names the OLD one inside: the .bzn's
## ``TerrainName`` and ``msn_filename``, and the .ini's ``missionName``. The
## renamed .trn is then the one file the .bzn does not ask for, and the engine
## refuses the mission with "Could not load terrain <oldstem>.trn". Saving a
## template under your own name — the normal way to start a map — produced a
## map that could never load.
##
## Only values that still equal ``source_stem`` are touched, so a display name
## the user has already customised survives. Object labels are left alone: they
## carry the old stem cosmetically but nothing resolves through them.
static func _restem_identity(
	out_dir: String,
	written: Array,
	source_stem: String,
	out_stem: String,
	regenerated: Array,
	warnings: Array
) -> void:
	if source_stem.is_empty() or out_stem.is_empty():
		return
	if source_stem.to_lower() == out_stem.to_lower():
		return
	var touched: Array = []
	for name_v in written:
		var name: String = str(name_v)
		var ext: String = name.get_extension().to_lower()
		var path: String = out_dir.path_join(name)
		if not FileAccess.file_exists(path):
			continue
		if ext == "bzn":
			if _restem_bzn(path, source_stem, out_stem):
				touched.append(name)
		elif ext == "ini":
			if _restem_ini(path, source_stem, out_stem):
				touched.append(name)
	if touched.is_empty():
		return
	touched.sort()
	for name2 in touched:
		if not regenerated.has(name2):
			regenerated.append(name2)
	warnings.append(
		"renamed %s to %s inside %s" % [source_stem, out_stem, ", ".join(PackedStringArray(touched))]
	)


static func _restem_bzn(path: String, source_stem: String, out_stem: String) -> bool:
	var loaded: Dictionary = BzBzn.read_bzn(path)
	if not bool(loaded.get("ok", false)):
		return false
	var bzn: BzBzn.BznFile = loaded.get("bznfile") as BzBzn.BznFile
	if bzn == null:
		return false
	var changed: bool = false
	var terrain: String = str(bzn.header_value("TerrainName", ""))
	if terrain.to_lower() == source_stem.to_lower():
		bzn.set_header("TerrainName", out_stem)
		changed = true
	var msn: String = str(bzn.header_value("msn_filename", ""))
	var msn_stem: String = msn.get_basename()
	if msn_stem.to_lower().begins_with(source_stem.to_lower()):
		bzn.set_header(
			"msn_filename",
			"%s%s.bzn" % [out_stem, msn_stem.substr(source_stem.length())]
		)
		changed = true
	if not changed:
		return false
	var wr: Dictionary = BzBzn.write_bzn(path, bzn)
	return bool(wr.get("ok", true))


static func _restem_ini(path: String, source_stem: String, out_stem: String) -> bool:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return false
	var re := RegEx.new()
	if re.compile('(missionName\\s*=\\s*")([^"]*)(")') != OK:
		return false
	var m: RegExMatch = re.search(text)
	if m == null or m.get_string(2).to_lower() != source_stem.to_lower():
		return false
	var updated: String = (
		text.substr(0, m.get_start(2)) + out_stem + text.substr(m.get_end(2))
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(updated)
	file.close()
	return true


## Write the map's sun clock and fog into its own `.trn`. Fog colour is the
## 256-entry `.act` named by `[Color] Palette` (F6 §3) — there is no `FogColor`
## key. `{stem}.act` is always a recolored copy of the shipped template when a
## `.trn` is present. `[Color] Palette` is retargeted at that file on every
## save. Sun/fog distance keys still wait on dirty.trn.
static func _apply_world(
	paths: Dictionary,
	out_dir: String,
	out_stem: String,
	dirty: Dictionary,
	written: Array,
	regenerated: Array,
	warnings: Array
) -> Dictionary:
	var dest_trn: String = _dest_path(out_dir, "%s.trn" % out_stem)
	var trn_dirty: bool = _truthy(dirty.get("trn"))
	if not FileAccess.file_exists(dest_trn):
		if trn_dirty:
			warnings.append("no .trn in the saved map; sun and fog were not written")
		return {"ok": true}
	var loaded: Dictionary = _session_world(paths)
	if BzErrors.is_err(loaded):
		return loaded
	var world: Dictionary = loaded.get("world", {})
	var act: Dictionary = _write_fog_act(
		world, out_dir, out_stem, written, regenerated, warnings, trn_dirty
	)
	if BzErrors.is_err(act):
		return act
	var cfg = BzTrn.read_trn(dest_trn)
	if cfg == null:
		warnings.append("could not parse %s; sun and fog were not written" % dest_trn.get_file())
		return {"ok": true}
	var touched: bool = false
	if trn_dirty and not world.is_empty():
		cfg.ensure_section("NormalView")
		var fog: Vector2 = WorldLighting.clamp_fog(
			float(world.get("fog_start_m", WorldLighting.FOG_START_DEFAULT)),
			float(world.get("fog_end_m", WorldLighting.FOG_END_DEFAULT))
		)
		_set_trn(cfg, "NormalView", "Time", str(int(world.get("time", WorldLighting.TIME_DEFAULT))))
		_set_trn(cfg, "NormalView", "FogStart", str(int(round(fog.x))))
		_set_trn(cfg, "NormalView", "FogEnd", str(int(round(fog.y))))
		_set_trn(cfg, "NormalView", "FogBreak", str(int(round(
			float(world.get("fog_break_m", WorldLighting.FOG_BREAK_DEFAULT))
		))))
		# VisibilityRange is FogEnd + 50 by definition — the engine culls there, so
		# a smaller value pops terrain in front of the fog wall.
		_set_trn(cfg, "NormalView", "VisibilityRange", str(int(round(
			WorldLighting.visibility_range(fog.y)
		))))
		touched = true
	var dest_act: String = str(act.get("path", ""))
	if dest_act.is_empty():
		dest_act = _dest_path(out_dir, "%s.act" % out_stem)
	if FileAccess.file_exists(dest_act):
		var want: String = dest_act.get_file()
		var have: String = _current_palette_file(cfg)
		if have.to_lower() != want.to_lower():
			cfg.ensure_section("Color")
			_set_trn(cfg, "Color", "Palette", want)
			touched = true
	if not touched:
		return {"ok": true}
	cfg.write(dest_trn)
	if not written.has(dest_trn.get_file()):
		written.append(dest_trn.get_file())
	if not regenerated.has(dest_trn.get_file()):
		regenerated.append(dest_trn.get_file())
	return {"ok": true}


static func _session_world(paths: Dictionary) -> Dictionary:
	var world := {}
	var meta_path: String = str(paths.get("meta", ""))
	if meta_path.is_empty() or not FileAccess.file_exists(meta_path):
		return {"ok": true, "world": world}
	var meta_v: Variant = BzSession.read_json(meta_path)
	if BzErrors.is_err(meta_v):
		return meta_v
	if typeof(meta_v) == TYPE_DICTIONARY:
		var world_v: Variant = (meta_v as Dictionary).get("world")
		if typeof(world_v) == TYPE_DICTIONARY:
			world = world_v
	return {"ok": true, "world": world}


static func _world_fog_color(world: Dictionary) -> Color:
	var raw: String = str(world.get("fog_color", "")).strip_edges()
	if raw.is_empty():
		raw = str(WorldLighting.defaults().get("fog_color", "#8a97a8"))
	return Color(raw)


## Duplicate the shipped template.act, paint every entry the fog colour, and
## write `{out_stem}.act` next to the map. Does not invent a ramp.
static func _write_fog_act(
	world: Dictionary,
	out_dir: String,
	out_stem: String,
	written: Array,
	regenerated: Array,
	warnings: Array,
	mark_regenerated: bool
) -> Dictionary:
	var template: String = BzAct.template_path()
	if template.is_empty() or not FileAccess.file_exists(template):
		warnings.append("fog colour not written: template.act not found")
		return {"ok": true}
	var read: Dictionary = BzAct.read(template)
	if not bool(read.get("ok", false)):
		warnings.append("fog colour not written: %s" % template.get_file())
		return {"ok": true}
	var dest_act: String = _dest_path(out_dir, "%s.act" % out_stem)
	var wrote: Dictionary = BzAct.write(
		dest_act, BzAct.with_all_fog(read["palette"], _world_fog_color(world))
	)
	if BzErrors.is_err(wrote):
		return wrote
	var name: String = dest_act.get_file()
	if not written.has(name):
		written.append(name)
	if mark_regenerated and not regenerated.has(name):
		regenerated.append(name)
	return {"ok": true, "path": dest_act}


static func _current_palette_file(cfg) -> String:
	if cfg == null or cfg.section("Color") == null:
		return ""
	var raw: String = str(cfg.get_value("Color", "Palette", "")).strip_edges()
	if raw.is_empty():
		for existing in (cfg.section("Color") as BzTrn.Section).keys():
			if str(existing).to_lower() == "palette":
				raw = str(cfg.get_value("Color", str(existing), "")).strip_edges()
				break
	return raw.get_file()


static func _set_trn(cfg, section_name: String, key: String, value: String) -> void:
	## Reuse the file's own spelling of the key. F3 §2: only the FIRST
	## occurrence counts, so appending `FogEnd` to a file that already says
	## `fogend` would write a line the engine never reads.
	var sec: Variant = cfg.section(section_name)
	if sec != null:
		var needle: String = key.to_lower()
		for existing in (sec as BzTrn.Section).keys():
			if str(existing).to_lower() == needle:
				cfg.set_value(section_name, str(existing), value)
				return
	cfg.set_value(section_name, key, value)


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

