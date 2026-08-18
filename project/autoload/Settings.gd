extends Node
## Persisted user prefs: backend path, game root, recent files.

const PATH := "user://settings.cfg"
const RECENT_MAX := 8

var game_root: String = ""
var last_map_dir: String = ""
var last_save_dir: String = ""
var walk_mode: bool = false
var last_cache_fingerprint: String = ""
## Keyboard scheme id: "godot" (number-row tools) or "gimp". Default godot.
var keymap_scheme: String = "godot"
## Last successfully opened map paths, most recent first, at most RECENT_MAX.
var recent_maps: Array[String] = []
## Viewport filters. Hidden categories are view-only (objects still save).
var view_geysers: bool = true
var view_scrap: bool = true
var view_spawns: bool = true
var view_buildings: bool = true
var view_units: bool = true
var view_props: bool = true
var view_water: bool = true
var view_plants: bool = true
var view_sky: bool = false

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
	keymap_scheme = _coerce_scheme(str(_cfg.get_value("input", "keymap_scheme", "godot")))
	recent_maps = _coerce_recent(_cfg.get_value("paths", "recent_maps", PackedStringArray()))
	view_geysers = bool(_cfg.get_value("view", "geysers", true))
	view_scrap = bool(_cfg.get_value("view", "scrap", true))
	view_spawns = bool(_cfg.get_value("view", "spawns", true))
	view_buildings = bool(_cfg.get_value("view", "buildings", true))
	view_units = bool(_cfg.get_value("view", "units", true))
	view_props = bool(_cfg.get_value("view", "props", true))
	view_water = bool(_cfg.get_value("view", "water", true))
	view_plants = bool(_cfg.get_value("view", "plants", true))
	view_sky = bool(_cfg.get_value("view", "sky", false))


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
	keymap_scheme = _coerce_scheme(keymap_scheme)
	_cfg.set_value("input", "keymap_scheme", keymap_scheme)
	_cfg.set_value("view", "geysers", view_geysers)
	_cfg.set_value("view", "scrap", view_scrap)
	_cfg.set_value("view", "spawns", view_spawns)
	_cfg.set_value("view", "buildings", view_buildings)
	_cfg.set_value("view", "units", view_units)
	_cfg.set_value("view", "props", view_props)
	_cfg.set_value("view", "water", view_water)
	_cfg.set_value("view", "plants", view_plants)
	_cfg.set_value("view", "sky", view_sky)
	_cfg.save(PATH)


func view_flag(key: String) -> bool:
	match key:
		"geysers":
			return view_geysers
		"scrap":
			return view_scrap
		"spawns":
			return view_spawns
		"buildings":
			return view_buildings
		"units":
			return view_units
		"props":
			return view_props
		"water":
			return view_water
		"plants":
			return view_plants
		"sky":
			return view_sky
		_:
			return true


func view_group_visible(group: String) -> bool:
	return view_flag(group)


func set_view_group(group: String, on: bool) -> void:
	match group:
		"geysers":
			view_geysers = on
		"scrap":
			view_scrap = on
		"spawns":
			view_spawns = on
		"buildings":
			view_buildings = on
		"units":
			view_units = on
		"props":
			view_props = on
		"water":
			view_water = on
		"plants":
			view_plants = on
		"sky":
			view_sky = on


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


func _coerce_scheme(name: String) -> String:
	var cleaned := name.strip_edges().to_lower()
	if cleaned == "gimp":
		return "gimp"
	return "godot"


func _norm_map_path(path: String) -> String:
	return path.strip_edges().simplify_path()


func _same_map_path(a: String, b: String) -> bool:
	if OS.get_name() == "Windows":
		return a.to_lower() == b.to_lower()
	return a == b
