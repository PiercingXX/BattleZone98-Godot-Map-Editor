extends RefCounted
class_name MapGalleryEnum
## Pure map-gallery scan: source dirs → one entry per .trn, with thumb path.
##
## Entry keys: stem, path (.trn to open), thumb_path ("" if none), source, kind.
## kind is addon | workshop | template. source is the label (addon / pack name /
## template). Binary BZNs are not filtered — a .trn is enough.


static func collect_sources(game_root: String, templates_root: String, workshop_items: Array) -> Array:
	var out: Array = []
	if not game_root.is_empty():
		var addon := game_root.path_join("addon")
		if DirAccess.dir_exists_absolute(addon):
			out.append({
				"path": addon,
				"source": "addon",
				"kind": "addon",
			})
	for item in workshop_items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var pack_path := str(item.get("path", "")).strip_edges()
		if pack_path.is_empty() or not DirAccess.dir_exists_absolute(pack_path):
			continue
		var pack_name := str(item.get("name", "")).strip_edges()
		if pack_name.is_empty():
			pack_name = str(item.get("id", "")).strip_edges()
		if pack_name.is_empty():
			pack_name = pack_path.get_file()
		out.append({
			"path": pack_path,
			"source": pack_name,
			"kind": "workshop",
		})
	if not templates_root.is_empty() and DirAccess.dir_exists_absolute(templates_root):
		out.append({
			"path": templates_root,
			"source": "template",
			"kind": "template",
		})
	return out


static func workshop_items_from_discover(result: Variant) -> Array:
	var out: Array = []
	if typeof(result) != TYPE_DICTIONARY:
		return out
	if BzErrors.is_err(result):
		return out
	var installs: Variant = (result as Dictionary).get("installs", [])
	if typeof(installs) != TYPE_ARRAY:
		return out
	for item in installs:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if str(item.get("kind", "")) != "workshop_item":
			continue
		out.append(item)
	return out


static func resolve_thumb(directory: String, stem: String) -> String:
	if directory.is_empty() or stem.is_empty():
		return ""
	var da := DirAccess.open(directory)
	if da == null:
		return ""
	da.include_hidden = false
	da.include_navigational = false
	var want := stem.to_lower()
	var png := ""
	var bmp := ""
	for fname in da.get_files():
		var name := String(fname)
		var ext := name.get_extension().to_lower()
		if ext != "png" and ext != "bmp":
			continue
		if name.get_basename().to_lower() != want:
			continue
		var full := directory.path_join(name)
		if ext == "png" and png.is_empty():
			png = full
		elif ext == "bmp" and bmp.is_empty():
			bmp = full
	if not png.is_empty():
		return png
	return bmp


static func scan_dir(dir_path: String, source: String, kind: String) -> Dictionary:
	var entries: Array = []
	var subdirs: PackedStringArray = []
	if dir_path.is_empty():
		return {"entries": entries, "subdirs": subdirs}
	var da := DirAccess.open(dir_path)
	if da == null:
		return {"entries": entries, "subdirs": subdirs}
	da.include_hidden = false
	da.include_navigational = false
	var png_of := {}
	var bmp_of := {}
	var trns: Array = []
	for fname in da.get_files():
		var name := String(fname)
		var ext := name.get_extension().to_lower()
		var stem := name.get_basename()
		var full := dir_path.path_join(name)
		if ext == "trn":
			trns.append({"stem": stem, "path": full})
		elif ext == "png":
			var key := stem.to_lower()
			if not png_of.has(key):
				png_of[key] = full
		elif ext == "bmp":
			var key := stem.to_lower()
			if not bmp_of.has(key):
				bmp_of[key] = full
	for rec in trns:
		var stem := str(rec.get("stem", ""))
		var key := stem.to_lower()
		var thumb := ""
		if png_of.has(key):
			thumb = str(png_of[key])
		elif bmp_of.has(key):
			thumb = str(bmp_of[key])
		entries.append({
			"stem": stem,
			"path": str(rec.get("path", "")),
			"thumb_path": thumb,
			"source": source,
			"kind": kind,
		})
	for dname in da.get_directories():
		subdirs.append(dir_path.path_join(String(dname)))
	return {"entries": entries, "subdirs": subdirs}


static func scan_sources(sources: Array, max_depth: int = 10, max_dirs: int = 4000) -> Array:
	var entries: Array = []
	var queue: Array = []
	var seen := {}
	for src in sources:
		if typeof(src) != TYPE_DICTIONARY:
			continue
		var p := str(src.get("path", "")).strip_edges()
		if p.is_empty():
			continue
		var key := dir_key(p)
		if seen.has(key):
			continue
		seen[key] = true
		queue.append({
			"path": p,
			"source": str(src.get("source", "")),
			"kind": str(src.get("kind", "")),
			"depth": 0,
		})
	while not queue.is_empty() and seen.size() <= max_dirs:
		var job: Dictionary = queue.pop_front()
		var result := scan_dir(str(job.get("path", "")), str(job.get("source", "")), str(job.get("kind", "")))
		for e in result.get("entries", []):
			entries.append(e)
		var depth := int(job.get("depth", 0))
		if depth >= max_depth:
			continue
		for sub in result.get("subdirs", []):
			var sub_path := str(sub)
			var key := dir_key(sub_path)
			if seen.has(key):
				continue
			if seen.size() >= max_dirs:
				break
			seen[key] = true
			queue.append({
				"path": sub_path,
				"source": str(job.get("source", "")),
				"kind": str(job.get("kind", "")),
				"depth": depth + 1,
			})
	return entries


static func filter_by_stem(entries: Array, query: String) -> Array:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return entries.duplicate()
	var out: Array = []
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("stem", "")).to_lower().contains(q):
			out.append(e)
	return out


static func sort_entries(entries: Array) -> void:
	entries.sort_custom(_entry_less)


static func dir_key(path: String) -> String:
	var p := path.replace("\\", "/").simplify_path()
	if OS.get_name() == "Windows":
		return p.to_lower()
	return p


static func _entry_less(a: Variant, b: Variant) -> bool:
	var sa := str((a as Dictionary).get("stem", "")).to_lower()
	var sb := str((b as Dictionary).get("stem", "")).to_lower()
	if sa != sb:
		return sa < sb
	var ka := str((a as Dictionary).get("kind", ""))
	var kb := str((b as Dictionary).get("kind", ""))
	if ka != kb:
		return ka < kb
	var oa := str((a as Dictionary).get("source", "")).to_lower()
	var ob := str((b as Dictionary).get("source", "")).to_lower()
	if oa != ob:
		return oa < ob
	return str((a as Dictionary).get("path", "")) < str((b as Dictionary).get("path", ""))
