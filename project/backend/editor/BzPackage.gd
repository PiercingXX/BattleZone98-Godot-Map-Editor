extends RefCounted
class_name BzPackage
## Port of assemble.py + install.py + package_cmd.py.
##
## Safety (install.py / docs/07): the only writes into a game tree are
## `<game_root>/mods/<test_id>/`, `<game_root>/modEnabled.dat`, and
## `<game_root>/addon/` (mode "addon"). Never the installed pack, the
## workshop dir, or any other path under the install.
##
## The generator repo's live harness (its docs/17 + containers/FINDINGS.md)
## proved that hand-editing modEnabled.dat does NOT activate a mod, and that
## the reliable way to make the engine load an authored map is copying the
## map file set — plus the pack's shared lua modules (RequireFix.lua,
## SBPNavLogic.lua) when the map script requires them — into
## `<install>/addon/`. Mode "addon" implements that verified route; the
## "install" test-mod mode is kept for parity with the Python reference.

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


static func _save_session(session_dir: String, out_dir: String, stem: String) -> Dictionary:
	## BzSave.save_session is the only way a package may stage a map.
	##
	## package_cmd.py fell back to copying residue/source when the save
	## errored, so pack/install still produced a map directory. That is a
	## silent revert: the staged .hg2/.mat/.bzn are the pre-edit bytes while
	## BzRender still draws the thumbnail from the live session buffers, so
	## the .BMP shows the sculpt and the shipped terrain does not. On the
	## addon route it writes that stale map straight into the game install.
	## A package that cannot encode the session must fail loudly instead
	## (AGENTS.md rule 2).
	return BzSave.save_session(session_dir, out_dir, stem)


static func package_session(
	session_dir: String,
	mode: String,
	game_root: String = "",
	test_id: String = "",
	out_dir: String = ""
) -> Dictionary:
	## mode is install or pack. Payload: docs/02 §3 package.
	var paths: Dictionary = BzSession.session_paths(session_dir)
	if not FileAccess.file_exists(str(paths["manifest"])):
		return BzErrors.err(
			"no_session",
			"no manifest.json in %s" % session_dir,
			"",
			session_dir
		)
	var manifest_v: Variant = BzSession.read_json(str(paths["manifest"]))
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
	if mode == "addon":
		if game_root.is_empty():
			return BzErrors.err("no_game", "package --mode addon needs --game-root")
		var addon: String = _abs(game_root).path_join("addon")
		var mk_addon: Dictionary = _ensure_dir(addon)
		if BzErrors.is_err(mk_addon):
			return mk_addon
		var copied: Array = []
		var da2 := DirAccess.open(staging)
		if da2 != null:
			for name2 in da2.get_files():
				if str(name2) == "features.json":
					continue
				var cres: Dictionary = _copy_file(
					staging.path_join(str(name2)), addon.path_join(str(name2))
				)
				if BzErrors.is_err(cres):
					return cres
				copied.append(str(name2))
		var shared: Array = _copy_shared_lua(staging, addon)
		var custom: Array = _copy_custom_assets(session_dir, addon)
		return {
			"ok": true,
			"mode": "addon",
			"dest": addon,
			"files": copied,
			"shared_lua": shared,
			"custom_assets": custom,
			"warnings": saved.get("warnings", []),
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
		"use install, addon, or pack"
	)


## Copy the pack's shared lua modules into ``dest_dir`` when a staged map
## script requires them. The engine reports a missing require only as a
## modal dialog, never in the log, so bundling proactively is the only
## reliable option. Returns the copied file names.
static func _copy_shared_lua(staging: String, dest_dir: String) -> Array:
	var regex := RegEx.new()
	if regex.compile("require\\s*[\\(\\s]\\s*[\"']([^\"']+)[\"']") != OK:
		return []
	var queue: Array = []
	var seen := {}
	var da := DirAccess.open(staging)
	if da == null:
		return []
	for name in da.get_files():
		if str(name).to_lower().ends_with(".lua"):
			for m in regex.search_all(FileAccess.get_file_as_string(staging.path_join(str(name)))):
				var req := m.get_string(1)
				if not seen.has(req):
					seen[req] = true
					queue.append(req)
	if queue.is_empty():
		return []
	# The verified recipe (generator docs/17): RequireFix pulls SBPNavLogic
	# in turn, so ship both whenever anything is required at all.
	for forced in ["RequireFix", "SBPNavLogic"]:
		if not seen.has(forced):
			seen[forced] = true
			queue.append(forced)
	var copied: Array = []
	var roots: Array = []
	var disc: Dictionary = BzDiscover.discover()
	for item in disc.get("installs", []):
		if typeof(item) == TYPE_DICTIONARY and item.get("kind") == "workshop_item":
			roots.append(str(item.get("path", "")))
	# Transitive closure: each copied module may require further modules.
	while not queue.is_empty():
		var req2: String = str(queue.pop_front())
		var fname := "%s.lua" % req2
		if FileAccess.file_exists(dest_dir.path_join(fname)) \
				or FileAccess.file_exists(staging.path_join(fname)):
			continue
		for root in roots:
			var src := _find_file_ci(str(root), fname)
			if not src.is_empty():
				var res: Dictionary = _copy_file(src, dest_dir.path_join(fname))
				if res.get("ok", false):
					copied.append(fname)
					for m2 in regex.search_all(FileAccess.get_file_as_string(src)):
						var sub := m2.get_string(1)
						if not seen.has(sub):
							seen[sub] = true
							queue.append(sub)
				break
	return copied


## Copy map-private object assets (odf/mesh/material/textures) that ship
## beside the source map into ``dest_dir``. The engine aborts the mission
## load on the first GameObject whose .odf it cannot find, and workshop
## maps commonly define custom classes next to the map set. Chases
## references transitively: a copied odf/material/ini may name further
## files (meshes, textures, weapon odfs) that also live in the source dir.
static func _copy_custom_assets(session_dir: String, dest_dir: String) -> Array:
	var paths: Dictionary = BzSession.session_paths(session_dir)
	var manifest_v: Variant = BzSession.read_json(str(paths["manifest"]))
	if typeof(manifest_v) != TYPE_DICTIONARY:
		return []
	var source_path := str((manifest_v as Dictionary).get("source_path", ""))
	if source_path.is_empty():
		return []
	var src_dir := source_path.get_base_dir()
	var da := DirAccess.open(src_dir)
	if da == null:
		return []
	var names: Array = []
	var by_stem: Dictionary = {}
	for name in da.get_files():
		var n := str(name)
		names.append(n)
		var stem := n.get_basename().to_lower()
		var lst: Array = by_stem.get(stem, [])
		lst.append(n)
		by_stem[stem] = lst
	var queue: Array = []
	var seen := {}
	var objects_v: Variant = BzSession.read_json(str(paths["objects"]))
	if typeof(objects_v) == TYPE_DICTIONARY:
		for variant in (objects_v as Dictionary):
			var recs: Variant = (objects_v as Dictionary)[variant]
			if typeof(recs) != TYPE_ARRAY:
				continue
			for rec in recs:
				if typeof(rec) != TYPE_DICTIONARY:
					continue
				var prjid := str((rec as Dictionary).get("prjid", "")).to_lower()
				if not prjid.is_empty() and not seen.has(prjid) and by_stem.has(prjid):
					seen[prjid] = true
					queue.append(prjid)
	var copied: Array = []
	while not queue.is_empty():
		var stem2: String = str(queue.pop_front())
		for fname in by_stem.get(stem2, []):
			var f := str(fname)
			var dest := dest_dir.path_join(f)
			if FileAccess.file_exists(dest):
				continue
			var res: Dictionary = _copy_file(src_dir.path_join(f), dest)
			if not res.get("ok", false):
				continue
			copied.append(f)
			var ext := f.get_extension().to_lower()
			if ext == "odf" or ext == "material" or ext == "ini":
				var text := FileAccess.get_file_as_string(
					src_dir.path_join(f)
				).to_lower()
				for other in names:
					var o := str(other)
					var ostem := o.get_basename().to_lower()
					if seen.has(ostem):
						continue
					# Full filename match, or a bare stem mention (odfs
					# often name geometry without an extension). Short
					# stems over-match, so require 4+ characters there.
					if text.contains(o.to_lower()) \
							or (ostem.length() >= 4 and text.contains(ostem)):
						seen[ostem] = true
						queue.append(ostem)
	return copied


static func _find_file_ci(dir: String, fname: String) -> String:
	var da := DirAccess.open(dir)
	if da == null:
		return ""
	var want := fname.to_lower()
	for name in da.get_files():
		if str(name).to_lower() == want:
			return dir.path_join(str(name))
	return ""
