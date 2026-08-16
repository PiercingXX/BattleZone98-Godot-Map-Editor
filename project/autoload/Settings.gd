extends Node
## Persisted user prefs: backend path, game root, recent files.

const PATH := "user://settings.cfg"

var bzmap_home: String = ""
var python_path: String = ""
var game_root: String = ""
var last_map_dir: String = ""

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


func save() -> void:
	_cfg.set_value("paths", "bzmap_home", bzmap_home)
	_cfg.set_value("paths", "python_path", python_path)
	_cfg.set_value("paths", "game_root", game_root)
	_cfg.set_value("paths", "last_map_dir", last_map_dir)
	_cfg.save(PATH)
