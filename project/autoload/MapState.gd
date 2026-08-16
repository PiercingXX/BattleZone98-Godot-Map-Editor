extends Node
## The open map. Mutated only through undoable commands once those exist.

const HeightFieldScript = preload("res://project/terrain/HeightField.gd")

signal session_changed()

var stem: String = ""
var width_m: int = 0
var depth_m: int = 0
var world: String = ""
var session_dir: String = ""
var source_path: String = ""
var manifest: Dictionary = {}
var dirty: Dictionary = {}
var objects: Dictionary = {}
var has_session: bool = false
var field = HeightFieldScript.new()


func session_root() -> String:
	var base := OS.get_user_data_dir().path_join("sessions")
	return base


func new_session_dir() -> String:
	var uuid := _uuid4()
	var path := session_root().path_join(uuid)
	DirAccess.make_dir_recursive_absolute(path)
	return path


func load_from_open(result: Dictionary) -> void:
	manifest = result.get("manifest", {})
	stem = str(manifest.get("stem", ""))
	width_m = int(manifest.get("width_m", 0))
	depth_m = int(manifest.get("depth_m", 0))
	world = str(manifest.get("world", ""))
	session_dir = str(result.get("session", ""))
	source_path = str(manifest.get("source_path", ""))
	has_session = not session_dir.is_empty()
	dirty = _read_json(session_dir.path_join("dirty.json"))
	objects = _read_json(session_dir.path_join("objects.json"))
	var gx := int(manifest.get("grid_x", 0))
	var gz := int(manifest.get("grid_z", 0))
	var r16 := session_dir.path_join("terrain.r16")
	if gx > 0 and gz > 0 and FileAccess.file_exists(r16):
		var err := field.load_r16(r16, gx, gz)
		if err != OK:
			push_error("failed to load terrain.r16: %s" % error_string(err))
	session_changed.emit()


func clear() -> void:
	stem = ""
	width_m = 0
	depth_m = 0
	world = ""
	session_dir = ""
	source_path = ""
	manifest = {}
	dirty = {}
	objects = {}
	field = HeightFieldScript.new()
	has_session = false
	session_changed.emit()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func _uuid4() -> String:
	var hex := "0123456789abcdef"
	var out := ""
	for i in range(32):
		out += hex[randi() % 16]
	return out
