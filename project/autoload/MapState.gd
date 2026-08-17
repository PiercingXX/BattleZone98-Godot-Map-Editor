extends Node
## The open map. Mutated only through undoable commands.

const HeightFieldScript = preload("res://project/terrain/HeightField.gd")

signal session_changed()
signal objects_mutated()
signal materials_changed()
signal dirty_changed()
signal water_changed(level: float)

var stem: String = ""
var width_m: int = 0
var depth_m: int = 0
var world: String = ""
var session_dir: String = ""
var source_path: String = ""
var manifest: Dictionary = {}
var dirty: Dictionary = {}
var objects: Dictionary = {}
var meta: Dictionary = {}
var features: Dictionary = {}
var has_session: bool = false
var field = HeightFieldScript.new()
var materials: PackedInt32Array = PackedInt32Array()
var mat_grid_x: int = 0
var mat_grid_z: int = 0
var mat_texture: ImageTexture
var mat_image: Image
var active_variant: String = ""
var selected_ids: Array[String] = []
var next_new_id: int = 1
var unsaved: bool = false
var ceiling_hit: bool = false
var findings: Array = []
var findings_stale: bool = false
var asset_index: Dictionary = {}
var worlds: Array = []


func session_root() -> String:
	return OS.get_user_data_dir().path_join("sessions")


func cache_dir() -> String:
	return OS.get_user_data_dir().path_join("cache").path_join("assets")


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
	meta = _read_json(session_dir.path_join("meta.json"))
	features = _read_json(session_dir.path_join("features.json"))
	if features.is_empty():
		features = {"water": [], "plants": []}
	var gx := int(manifest.get("grid_x", 0))
	var gz := int(manifest.get("grid_z", 0))
	var r16 := session_dir.path_join("terrain.r16")
	if gx > 0 and gz > 0 and FileAccess.file_exists(r16):
		var err := field.load_r16(r16, gx, gz)
		if err != OK:
			push_error("failed to load terrain.r16: %s" % error_string(err))
	mat_grid_x = int(manifest.get("mat_grid_x", 0))
	mat_grid_z = int(manifest.get("mat_grid_z", 0))
	_load_materials()
	var variants: Array = manifest.get("variants", [""])
	active_variant = str(variants[0]) if not variants.is_empty() else ""
	selected_ids.clear()
	next_new_id = 1
	unsaved = false
	ceiling_hit = bool(manifest.get("height_over_ceiling", false))
	findings.clear()
	findings_stale = false
	UndoStack.clear()
	session_changed.emit()
	water_changed.emit(water_level())


func persist() -> void:
	if not has_session:
		return
	field.write_r16(session_dir.path_join("terrain.r16"))
	_write_materials()
	_write_json(session_dir.path_join("objects.json"), objects)
	_write_json(session_dir.path_join("dirty.json"), dirty)
	_write_json(session_dir.path_join("meta.json"), meta)
	_write_json(session_dir.path_join("features.json"), features)


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
	meta = {}
	features = {}
	field = HeightFieldScript.new()
	materials = PackedInt32Array()
	has_session = false
	unsaved = false
	session_changed.emit()


func mark_terrain_dirty() -> void:
	dirty["terrain"] = true
	unsaved = true
	findings_stale = true
	dirty_changed.emit()


func water_level() -> float:
	var waters: Variant = features.get("water", [])
	if typeof(waters) != TYPE_ARRAY or waters.is_empty():
		return -1.0
	if typeof(waters[0]) != TYPE_DICTIONARY:
		return -1.0
	return float(waters[0].get("level_m", -1.0))


func set_water_level(v: float) -> void:
	if v < 0.0:
		features["water"] = []
	else:
		var waters: Array = []
		var existing: Variant = features.get("water", [])
		if typeof(existing) == TYPE_ARRAY:
			waters = existing
		if waters.is_empty() or typeof(waters[0]) != TYPE_DICTIONARY:
			var wstem := stem if not stem.is_empty() else "map"
			if wstem.length() > 7:
				wstem = wstem.substr(0, 7)
			waters = [{
				"stem": wstem + "w",
				"level_m": v,
				"variant_scope": "all",
			}]
		else:
			waters[0]["level_m"] = v
		features["water"] = waters
	dirty["features"] = true
	unsaved = true
	findings_stale = true
	dirty_changed.emit()
	water_changed.emit(v)


func mark_materials_dirty() -> void:
	dirty["materials"] = true
	unsaved = true
	findings_stale = true
	dirty_changed.emit()
	materials_changed.emit()


func touch_object(variant: String, object_id: String) -> void:
	if not dirty.has("objects") or typeof(dirty["objects"]) != TYPE_DICTIONARY:
		dirty["objects"] = {}
	var per: Dictionary = dirty["objects"]
	if not per.has(variant):
		per[variant] = []
	var ids: Array = per[variant]
	if object_id not in ids:
		ids.append(object_id)
	unsaved = true
	findings_stale = true
	dirty_changed.emit()


func find_object(object_id: String) -> Dictionary:
	for variant in objects.keys():
		var recs: Variant = objects[variant]
		if typeof(recs) != TYPE_ARRAY:
			continue
		for rec in recs:
			if typeof(rec) == TYPE_DICTIONARY and str(rec.get("id", "")) == object_id:
				return rec
	return {}


func find_object_variant(object_id: String) -> String:
	for variant in objects.keys():
		var recs: Variant = objects[variant]
		if typeof(recs) != TYPE_ARRAY:
			continue
		for rec in recs:
			if typeof(rec) == TYPE_DICTIONARY and str(rec.get("id", "")) == object_id:
				return str(variant)
	return active_variant


func add_object_record(variant: String, rec: Dictionary) -> void:
	if not objects.has(variant):
		objects[variant] = []
	objects[variant].append(rec)
	touch_object(variant, str(rec.get("id", "")))
	objects_changed()


func remove_object_record(variant: String, object_id: String) -> void:
	if not objects.has(variant):
		return
	var recs: Array = objects[variant]
	var kept: Array = []
	for rec in recs:
		if typeof(rec) == TYPE_DICTIONARY and str(rec.get("id", "")) == object_id:
			continue
		kept.append(rec)
	objects[variant] = kept
	touch_object(variant, object_id)
	if object_id in selected_ids:
		selected_ids.erase(object_id)
	objects_changed()


func objects_changed() -> void:
	objects_mutated.emit()


func alloc_id() -> String:
	var id := "new-%04d" % next_new_id
	next_new_id += 1
	return id


func player_in_variant(variant: String) -> bool:
	var recs: Variant = objects.get(variant, [])
	if typeof(recs) != TYPE_ARRAY:
		return false
	for rec in recs:
		if typeof(rec) == TYPE_DICTIONARY and bool(rec.get("required", false)):
			return true
		if typeof(rec) == TYPE_DICTIONARY and str(rec.get("prjid", "")).to_lower() == "player":
			return true
	return false


func class_info(prjid: String) -> Dictionary:
	var classes: Array = asset_index.get("classes", [])
	for rec in classes:
		if typeof(rec) == TYPE_DICTIONARY and str(rec.get("prjid", "")).to_lower() == prjid.to_lower():
			return rec
	return {}


func resnap_objects(x0: int, z0: int, w: int, d: int) -> void:
	var x_min := float(x0) * HeightField.CELL_M
	var z_min := float(z0) * HeightField.CELL_M
	var x_max := float(x0 + w) * HeightField.CELL_M
	var z_max := float(z0 + d) * HeightField.CELL_M
	for variant in objects.keys():
		var recs: Variant = objects[variant]
		if typeof(recs) != TYPE_ARRAY:
			continue
		for rec in recs:
			if typeof(rec) != TYPE_DICTIONARY:
				continue
			if bool(rec.get("pinned_y", false)) or bool(rec.get("managed", false)):
				continue
			var x := float(rec.get("x", 0.0))
			var z := float(rec.get("z", 0.0))
			if x < x_min or x > x_max or z < z_min or z > z_max:
				continue
			rec["y"] = field.height_at(x, z)
			touch_object(str(variant), str(rec.get("id", "")))
	objects_changed()


func set_material(tx: int, tz: int, mat_id: int) -> void:
	if tx < 0 or tz < 0 or tx >= mat_grid_x or tz >= mat_grid_z:
		return
	# Solid tile: mat_a = mat_b = mat_id, rest zero. Matches encode_entry.
	var word := ((mat_id & 0xF) << 12) | ((mat_id & 0xF) << 8)
	materials[tz * mat_grid_x + tx] = word


func write_materials_rect(x0: int, z0: int, w: int, d: int, values: PackedInt32Array) -> void:
	var i := 0
	for z in range(z0, z0 + d):
		for x in range(x0, x0 + w):
			if x >= 0 and z >= 0 and x < mat_grid_x and z < mat_grid_z:
				materials[z * mat_grid_x + x] = values[i]
			i += 1
	upload_materials()


func upload_materials() -> void:
	if mat_grid_x < 1 or mat_grid_z < 1:
		return
	# Full tile word per cell (F2 §2): R = byte0 (orientation<<4 | variant),
	# G = byte1 (base<<4 | transition). The shader decodes the word and draws
	# the same atlas tile the game would.
	var bytes := PackedByteArray()
	bytes.resize(mat_grid_x * mat_grid_z * 2)
	for i in materials.size():
		bytes[i * 2] = materials[i] & 0xFF
		bytes[i * 2 + 1] = (materials[i] >> 8) & 0xFF
	mat_image = Image.create_from_data(mat_grid_x, mat_grid_z, false, Image.FORMAT_RG8, bytes)
	if mat_texture == null:
		mat_texture = ImageTexture.create_from_image(mat_image)
	else:
		mat_texture.update(mat_image)
	materials_changed.emit()


func material_at(x_m: float, z_m: float) -> int:
	if mat_grid_x < 1:
		return 0
	var tx := clampi(int(floor(x_m / 20.0)), 0, mat_grid_x - 1)
	var tz := clampi(int(floor(z_m / 20.0)), 0, mat_grid_z - 1)
	return (materials[tz * mat_grid_x + tx] >> 12) & 0xF


func _load_materials() -> void:
	materials = PackedInt32Array()
	var path := session_dir.path_join("materials.u16")
	if mat_grid_x < 1 or mat_grid_z < 1 or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var n := mat_grid_x * mat_grid_z
	materials.resize(n)
	for i in n:
		materials[i] = file.get_16()
	upload_materials()


func _write_materials() -> void:
	if mat_grid_x < 1:
		return
	var path := session_dir.path_join("materials.u16")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	for i in materials.size():
		file.store_16(materials[i] & 0xFFFF)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "  "))


func _uuid4() -> String:
	var hex := "0123456789abcdef"
	var out := ""
	for i in range(32):
		out += hex[randi() % 16]
	return out
