extends Node
## Persisted user prefs: backend path, game root, recent files.

const PATH := "user://settings.cfg"
const RECENT_MAX := 8

var game_root: String = ""
var last_map_dir: String = ""
var last_save_dir: String = ""
var walk_mode: bool = false
var last_cache_fingerprint: String = ""
## Last successfully opened map paths, most recent first, at most RECENT_MAX.
var recent_maps: Array[String] = []

var _cfg := ConfigFile.new()


func _ready() -> void:
	_load()


func _load() -> void:
	if _cfg.load(PATH) != OK:
		return
	game_root = _cfg.get_value("paths", "game_root", "")
	last_map_dir = _cfg.get_value("paths", "last_map_dir", "")
	last_save_dir = _cfg.get_value("paths", "last_save_dir", "")
	walk_mode = bool(_cfg.get_value("camera", "walk_mode", false))
	last_cache_fingerprint = str(_cfg.get_value("assets", "fingerprint", ""))
	recent_maps = _coerce_recent(_cfg.get_value("paths", "recent_maps", PackedStringArray()))


## Remember a successfully opened map. Deduped, most recent first, capped.
func record_recent_map(path: String) -> void:
	var cleaned := _norm_map_path(path)
	if cleaned.is_empty():
		return
	var next: Array[String] = [cleaned]
	for existing in recent_maps:
		if _same_map_path(existing, cleaned):
			continue
		next.append(existing)
		if next.size() >= RECENT_MAX:
			break
	recent_maps = next


func save() -> void:
	_prune_missing_recents()
	_cfg.set_value("paths", "game_root", game_root)
	_cfg.set_value("paths", "last_map_dir", last_map_dir)
	_cfg.set_value("paths", "last_save_dir", last_save_dir)
	_cfg.set_value("paths", "recent_maps", PackedStringArray(recent_maps))
	_cfg.set_value("camera", "walk_mode", walk_mode)
	_cfg.set_value("assets", "fingerprint", last_cache_fingerprint)
	_cfg.save(PATH)


func _prune_missing_recents() -> void:
	var kept: Array[String] = []
	for path in recent_maps:
		if FileAccess.file_exists(path):
			kept.append(path)
	recent_maps = kept


func _coerce_recent(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is PackedStringArray:
		for path in raw:
			var cleaned := _norm_map_path(str(path))
			if cleaned.is_empty():
				continue
			var dup := false
			for existing in out:
				if _same_map_path(existing, cleaned):
					dup = true
					break
			if dup:
				continue
			out.append(cleaned)
			if out.size() >= RECENT_MAX:
				break
	elif raw is Array:
		for path in raw:
			var cleaned := _norm_map_path(str(path))
			if cleaned.is_empty():
				continue
			var dup := false
			for existing in out:
				if _same_map_path(existing, cleaned):
					dup = true
					break
			if dup:
				continue
			out.append(cleaned)
			if out.size() >= RECENT_MAX:
				break
	return out


func _norm_map_path(path: String) -> String:
	return path.strip_edges().simplify_path()


func _same_map_path(a: String, b: String) -> bool:
	if OS.get_name() == "Windows":
		return a.to_lower() == b.to_lower()
	return a == b
