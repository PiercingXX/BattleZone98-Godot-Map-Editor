extends Node
## Persisted user prefs: backend path, game root, recent files.

const PATH := "user://settings.cfg"

var bzmap_home: String = ""
var python_path: String = ""
var game_root: String = ""
var last_map_dir: String = ""
var walk_mode: bool = false
var last_cache_fingerprint: String = ""

var _cfg := ConfigFile.new()


func _ready() -> void:
	_load()


func _load() -> void:
	if _cfg.load(PATH) != OK:
		return
	bzmap_home = _cfg.get_value("paths", "bzmap_home", "")
	python_path = _cfg.get_value("paths", "python_path", "")
	game_root = _cfg.get_value("paths", "game_root", "")
	last_map_dir = _cfg.get_value("paths", "last_map_dir", "")
	walk_mode = bool(_cfg.get_value("camera", "walk_mode", false))
	last_cache_fingerprint = str(_cfg.get_value("assets", "fingerprint", ""))


func save() -> void:
	_cfg.set_value("paths", "bzmap_home", bzmap_home)
	_cfg.set_value("paths", "python_path", python_path)
	_cfg.set_value("paths", "game_root", game_root)
	_cfg.set_value("paths", "last_map_dir", last_map_dir)
	_cfg.set_value("camera", "walk_mode", walk_mode)
	_cfg.set_value("assets", "fingerprint", last_cache_fingerprint)
	_cfg.save(PATH)
