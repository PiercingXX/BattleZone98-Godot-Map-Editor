extends RefCounted
class_name BzPackage
## Port of assemble.py + install.py + package_cmd.py.
##
## Safety (install.py / docs/07): the only writes into a game tree are
## `<game_root>/mods/<test_id>/` and `<game_root>/modEnabled.dat`. Never the
## installed pack, workshop dir, or any other path under the install.

## Per-map suffixes that make up one map's entry in the flat pack (assemble.py).
const MAP_SUFFIXES: Array[String] = [
	".trn",
	".hg2",
	".mat",
	".lgt",
	".vxt",
	".bzn",
	".ini",
	".des",
	".odf",
	".lua",
	".png",
	".bmp",
	".mesh",
	".material",
	".dds",
]

const PREVIEW_SIZE: Vector2i = Vector2i(512, 512)
const MOD_ENABLED_NAME: String = "modEnabled.dat"


static func _abs(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	if path.is_absolute_path():
		return path.simplify_path()
	var cwd := DirAccess.open(".")
	if cwd == null:
		return path.simplify_path()
	return cwd.get_current_dir().path_join(path).simplify_path()


static func _ensure_dir(path: String) -> Dictionary:
	var err: Error = DirAccess.make_dir_recursive_absolute(path)
	if err != OK and not DirAccess.dir_exists_absolute(path):
		return BzErrors.err(
			"write_failed",
			"cannot create directory: %s" % path,
			"",
			path
		)
	return {"ok": true}


static func _copy_file(src: String, dest: String) -> Dictionary:
	var parent: String = dest.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	var err: Error = DirAccess.copy_absolute(src, dest)
	if err != OK:
		return BzErrors.err(
			"write_failed",
			"cannot copy %s to %s (%s)" % [src, dest, error_string(err)],
			"",
			src
		)
	return {"ok": true}


static func _is_map_suffix(name: String) -> bool:
	var ext: String = name.get_extension().to_lower()
	if ext.is_empty():
		return false
	return MAP_SUFFIXES.has("." + ext)


static func _map_files(source_dir: String) -> Array:
	## (basename, path) pairs, sorted by name like assemble.py _map_files.
	var pairs: Array = []
	var da := DirAccess.open(source_dir)
	if da == null:
		return pairs
	var names: Array = []
	for name in da.get_files():
		names.append(str(name))
	names.sort()
	for name2 in names:
		if _is_map_suffix(name2):
			pairs.append([name2, source_dir.path_join(name2)])
	return pairs


static func _write_preview(source_dir: String, dest_dir: String, preview: Variant) -> Dictionary:
	var dest: String = dest_dir.path_join("preview.png")
	if preview is Image:
		var img: Image = (preview as Image).duplicate()
		if img.get_width() != PREVIEW_SIZE.x or img.get_height() != PREVIEW_SIZE.y:
			img.resize(PREVIEW_SIZE.x, PREVIEW_SIZE.y, Image.INTERPOLATE_LANCZOS)
		var parent: String = dest.get_base_dir()
		if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
			DirAccess.make_dir_recursive_absolute(parent)
		var err: Error = img.save_png(dest)
		if err != OK:
			return BzErrors.err(
				"assemble_error",
				"cannot write preview.png (%s)" % error_string(err),
				"",
				dest
			)
		return {"ok": true}
	var staged: String = source_dir.path_join("preview.png")
	if FileAccess.file_exists(staged):
		return _copy_file(staged, dest)
	return BzErrors.err(
		"assemble_error",
		"no preview supplied: pass a PIL image or stage a preview.png in the source dir (%s)"
		% source_dir
	)


static func assemble_pack(
	source_dir: String, dest_dir: String, preview: Variant = null
) -> Dictionary:
	## Flatten recognized map files into dest_dir. Python returns dest_dir;
	## GDScript returns {ok, dest} (no exceptions).
	var made: Dictionary = _ensure_dir(dest_dir)
	if BzErrors.is_err(made):
		return made
	var copied: int = 0
	for pair in _map_files(source_dir):
		var cp: Dictionary = _copy_file(str(pair[1]), dest_dir.path_join(str(pair[0])))
		if BzErrors.is_err(cp):
			return cp
		copied += 1
	if copied == 0:
		return BzErrors.err(
			"assemble_error",
			"no map files found in staging dir: %s" % source_dir,
			"",
			source_dir
		)
	var prev: Dictionary = _write_preview(source_dir, dest_dir, preview)
	if BzErrors.is_err(prev):
		return prev
	return {"ok": true, "dest": _abs(dest_dir)}


static func mod_dir(game_root: String, test_id: String) -> String:
	## `<game_root>/mods/<test_id>` — not created.
	return String(game_root).path_join("mods").path_join(test_id)


static func _mods_destination(game_root: String, test_id: String) -> Dictionary:
	## Extra guard on top of Python's Path join: refuse a test_id that escapes
	## mods/. Python relies on construction alone.
	if test_id.is_empty() or test_id.contains("..") \
			or test_id.contains("/") or test_id.contains("\\"):
		return BzErrors.err(
			"unsafe_path",
			"test_id escapes mods/: %s" % test_id,
			"use a simple id without path separators"
		)
	var dest: String = _abs(mod_dir(game_root, test_id))
	var mods_root: String = _abs(String(game_root).path_join("mods"))
	if dest == mods_root or not dest.begins_with(mods_root):
		return BzErrors.err(
			"unsafe_path",
			"test_id escapes mods/: %s" % test_id,
			"use a simple id without path separators"
		)
	return {"ok": true, "dest": dest}


static func install_map(game_root: String, test_id: String, files: Array) -> Dictionary:
	## Copy files into <game_root>/mods/<test_id>/. Python returns the dir.
	var dest_info: Dictionary = _mods_destination(game_root, test_id)
	if BzErrors.is_err(dest_info):
		return dest_info
	var dest_dir: String = str(dest_info["dest"])
	var made: Dictionary = _ensure_dir(dest_dir)
	if BzErrors.is_err(made):
		return made
	for item in files:
		var source: String
		var name: String
		if item is Array or item is PackedStringArray:
			if item.size() < 1:
				continue
			source = str(item[0])
			name = str(item[1]) if item.size() > 1 else source.get_file()
		else:
			source = str(item)
			name = source.get_file()
		if not FileAccess.file_exists(source):
			return BzErrors.err(
				"install_error",
				"source file not found: %s" % source,
				"",
				source
			)
		var dest: String = dest_dir.path_join(name)
		# Keep the dest under dest_dir even if dest_name is odd.
		if not _abs(dest).begins_with(_abs(dest_dir)):
			return BzErrors.err(
				"unsafe_path",
				"destination name escapes the test-mod dir: %s" % name,
				"use a basename"
			)
		var cp: Dictionary = _copy_file(source, dest)
		if BzErrors.is_err(cp):
			return cp
	return {"ok": true, "dest": dest_dir}


static func snapshot_mod_enabled(game_root: String) -> Variant:
	## Raw modEnabled.dat bytes, or null if absent.
	var path: String = String(game_root).path_join(MOD_ENABLED_NAME)
	if not FileAccess.file_exists(path):
		return null
	return FileAccess.get_file_as_bytes(path)


static func restore_mod_enabled(game_root: String, snapshot: Variant) -> void:
	## Restore a snapshot_mod_enabled snapshot. null deletes the file.
	var path: String = String(game_root).path_join(MOD_ENABLED_NAME)
	if snapshot == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var bytes := PackedByteArray()
	if snapshot is PackedByteArray:
		bytes = snapshot
	elif snapshot is String:
		bytes = (snapshot as String).to_ascii_buffer()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(bytes)
	file.close()


static func set_mod_enabled(game_root: String, test_id: String) -> Variant:
	## Write modEnabled.dat selecting test_id. Returns the previous snapshot.
	var previous: Variant = snapshot_mod_enabled(game_root)
	var path: String = String(game_root).path_join(MOD_ENABLED_NAME)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return previous
	file.store_string(test_id)
	file.close()
	return previous


static func _decode_previous(previous: Variant) -> Variant:
	if previous == null:
		return null
	if previous is PackedByteArray:
		return (previous as PackedByteArray).get_string_from_ascii()
	return previous


static func _session_paths(session_dir: String) -> Dictionary:
	## Private copy of BzSession.session_paths. BzSession.gd does not compile
	## in Godot 4.7 (String.is_absolute); do not call it from this file.
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


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return BzErrors.err("not_found", "no such file or directory: %s" % path, "", path)
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null and text.strip_edges() != "null":
		return BzErrors.err("invalid_json", "failed to parse JSON: %s" % path, "", path)
	return parsed


static func _copy_residue_source(session_dir: String, out_dir: String, stem: String) -> Dictionary:
	## Private fallback when BzSave.save_session cannot run. Copies residue/source.
	var paths: Dictionary = _session_paths(session_dir)
	var source_dir: String = str(paths["source"])
	var made: Dictionary = _ensure_dir(out_dir)
	if BzErrors.is_err(made):
		return made
	var written: Array = []
	if DirAccess.dir_exists_absolute(source_dir):
		var da := DirAccess.open(source_dir)
		if da != null:
			var names: Array = []
			for name in da.get_files():
				names.append(str(name))
			names.sort()
			for name2 in names:
				var cp: Dictionary = _copy_file(
					source_dir.path_join(name2), out_dir.path_join(name2)
				)
				if BzErrors.is_err(cp):
					return cp
				written.append(name2)
	return {
		"ok": true,
		"files": written,
		"byte_identical": written.duplicate(),
		"regenerated": [],
		"warnings": [],
		"out": _abs(out_dir),
		"stem": stem,
	}


static func _script_has(path: String, method: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var script: GDScript = load(path) as GDScript
	return script != null and script.has_method(method)


static func _save_session(session_dir: String, out_dir: String, stem: String) -> Dictionary:
	## Prefer BzSave.save_session (package_cmd.py). Fallback: residue/source copy.
	## BzSave calls BzSession; skip both when BzSession does not compile
	## (Godot 4.7: String.is_absolute is not a method).
	var session_ok: bool = _script_has(
		"res://project/backend/editor/BzSession.gd", "session_paths"
	)
	var save_path: String = "res://project/backend/editor/BzSave.gd"
	if session_ok and _script_has(save_path, "save_session"):
		var script: GDScript = load(save_path) as GDScript
		var saved_v: Variant = script.call("save_session", session_dir, out_dir, stem)
		if typeof(saved_v) == TYPE_DICTIONARY:
			var saved: Dictionary = saved_v
			if saved.get("ok", false):
				return saved
			if BzErrors.is_err(saved):
				var code: String = str(saved.get("error", {}).get("code", ""))
				if code == "no_session" or code == "no_stem":
					return saved
				var fallback: Dictionary = _copy_residue_source(session_dir, out_dir, stem)
				if fallback.get("ok", false):
					var warns: Array = fallback.get("warnings", [])
					warns.append(
						"save_session: %s" % str(saved.get("error", {}).get("message", saved))
					)
					fallback["warnings"] = warns
					return fallback
				return saved
	return _copy_residue_source(session_dir, out_dir, stem)


static func package_session(
	session_dir: String,
	mode: String,
	game_root: String = "",
	test_id: String = "",
	out_dir: String = ""
) -> Dictionary:
	## mode is install or pack. Payload: docs/02 §3 package.
	var paths: Dictionary = _session_paths(session_dir)
	if not FileAccess.file_exists(str(paths["manifest"])):
		return BzErrors.err(
			"no_session",
			"no manifest.json in %s" % session_dir,
			"",
			session_dir
		)
	var manifest_v: Variant = _read_json(str(paths["manifest"]))
	if BzErrors.is_err(manifest_v):
		return manifest_v
	if typeof(manifest_v) != TYPE_DICTIONARY:
		return BzErrors.err("no_session", "manifest.json is not an object", "", str(paths["manifest"]))
	var manifest: Dictionary = manifest_v
	var stem: String = str(manifest.get("stem", ""))
	if stem.is_empty():
		stem = "map"
	var staging: String = OS.get_temp_dir().path_join(
		"bzmap-package-%d" % Time.get_ticks_usec()
	)
	var made: Dictionary = _ensure_dir(staging)
	if BzErrors.is_err(made):
		return made
	var saved: Dictionary = _save_session(session_dir, staging, stem)
	if BzErrors.is_err(saved):
		return saved
	var rendered: Dictionary = BzRender.render_session(session_dir, staging)
	if not rendered.get("ok", false):
		var warns: Array = saved.get("warnings", [])
		var err_v: Variant = rendered.get("error", rendered)
		var msg: String = str(err_v)
		if typeof(err_v) == TYPE_DICTIONARY:
			msg = str((err_v as Dictionary).get("message", err_v))
		warns.append("thumbnail skipped: %s" % msg)
		saved["warnings"] = warns
	if mode == "install":
		if game_root.is_empty():
			return BzErrors.err("no_game", "package --mode install needs --game-root")
		var tid: String = test_id if not test_id.is_empty() else "bzeditor-%s" % stem
		var files: Array = []
		var da := DirAccess.open(staging)
		if da != null:
			for name in da.get_files():
				files.append(staging.path_join(str(name)))
		var inst: Dictionary = install_map(game_root, tid, files)
		if BzErrors.is_err(inst):
			return inst
		var previous: Variant = set_mod_enabled(game_root, tid)
		return {
			"ok": true,
			"mode": "install",
			"dest": str(inst.get("dest", "")),
			"test_id": tid,
			"previous_mod": _decode_previous(previous),
			"files": saved.get("files", []),
		}
	if mode == "pack":
		if out_dir.is_empty():
			return BzErrors.err("no_out", "package --mode pack needs --out")
		var dest: Dictionary = assemble_pack(staging, out_dir)
		if BzErrors.is_err(dest):
			return dest
		return {
			"ok": true,
			"mode": "pack",
			"dest": str(dest.get("dest", _abs(out_dir))),
			"files": saved.get("files", []),
		}
	return BzErrors.err(
		"bad_mode",
		"unknown package mode '%s'" % mode,
		"use install or pack"
	)
