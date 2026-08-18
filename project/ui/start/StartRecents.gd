extends RefCounted
class_name StartRecents
## Pure recents + thumbnail resolution for the start overlay.


static func is_first_run() -> bool:
	return Settings.is_first_run()


static func resolve_entry(path: String) -> Dictionary:
	var cleaned := path.strip_edges().simplify_path()
	var stem := cleaned.get_file().get_basename()
	var dir := cleaned.get_base_dir()
	var thumb := ""
	if not dir.is_empty() and not stem.is_empty():
		thumb = MapGalleryEnum.resolve_thumb(dir, stem)
	return {
		"path": cleaned,
		"stem": stem,
		"dir": dir,
		"thumb_path": thumb,
		"caption": caption_for(stem, dir, thumb),
		"exists": not cleaned.is_empty() and FileAccess.file_exists(cleaned),
	}


static func caption_for(stem: String, dir: String, thumb_path: String = "") -> String:
	if not str(thumb_path).is_empty():
		return stem if not stem.is_empty() else dir
	return display_stem_dir(stem, dir)


static func display_stem_dir(stem: String, dir: String) -> String:
	if stem.is_empty():
		return dir
	if dir.is_empty():
		return stem
	return "%s  ·  %s" % [stem, dir]


static func entries_from_settings() -> Array:
	var out: Array = []
	for path in Settings.recent_maps:
		out.append(resolve_entry(str(path)))
	return out
