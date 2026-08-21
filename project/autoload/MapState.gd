extends Node
## The open map. Mutated only through undoable commands.

const HeightFieldScript = preload("res://project/terrain/HeightField.gd")

signal session_changed()
signal objects_mutated()
signal materials_changed()
signal dirty_changed()
signal water_changed(level: float)
signal features_changed()
signal aipaths_changed()
signal mask_changed()
signal selection_changed()
## Y / xz pose only — markers should move in place, not rebuild.
signal object_poses_changed()

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
## Session sidecar: {paths:[...], variants:{"":{paths:[...]}}}. Residue is untouched.
var aipaths: Dictionary = {}
var selected_path_index: int = -1
var selected_point_index: int = -1
var has_session: bool = false
var field: HeightField = HeightFieldScript.new()
var materials: PackedInt32Array = PackedInt32Array()
var mat_grid_x: int = 0
var mat_grid_z: int = 0
var mat_texture: ImageTexture
var mat_image: Image
## stem → row-major u8 mask at heightmap resolution (0 = outside).
var masks: Dictionary = {}
var mask_texture: ImageTexture
var mask_image: Image
## View-only terrain selection at heightfield resolution (not persisted).
## Empty array = no selection = every cell editable (Photoshop semantics).
var terrain_selection: PackedByteArray = PackedByteArray()
var selection_texture: ImageTexture
var selection_image: Image
var _selection_count: int = 0
const SEL_REPLACE := "replace"
const SEL_ADD := "add"
const SEL_SUBTRACT := "subtract"
var active_variant: String = ""
var selected_ids: Array[String] = []
var next_new_id: int = 1
var _saved_generation: int = 0
var ceiling_hit: bool = false
var findings: Array = []
var findings_stale: bool = false
var asset_index: Dictionary = {}
var worlds: Array = []
var _objects_by_id: Dictionary = {}
var _variant_by_id: Dictionary = {}
var _indexed_objects: Variant = null
var _class_by_prjid: Dictionary = {}
var _indexed_assets: Variant = null
var _mat_gpu_dirty: bool = false
var _mask_gpu_dirty: bool = false
var _mask_gpu_stem: String = ""
var _selection_gpu_dirty: bool = false

## True when the undo-point generation differs from the last open/save.
## Assigning `true` bumps a non-undoable dirty; `false` snapshots the save point.
var unsaved: bool:
	get:
		return has_session and UndoStack.generation != _saved_generation
	set(value):
		if value:
			note_unsaved()
		else:
			mark_saved()


func mark_saved() -> void:
	_saved_generation = UndoStack.generation


func note_unsaved() -> void:
	if has_session and UndoStack.generation == _saved_generation:
		UndoStack.bump()


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
	_ensure_feature_groups()
	aipaths = _read_json(session_dir.path_join("aipaths.json"))
	if aipaths.is_empty():
		aipaths = _fallback_parse_aipaths()
	_ensure_aipaths_dirty_slot()
	clear_aipath_selection()
	masks.clear()
	mask_texture = null
	mask_image = null
	_reset_terrain_selection(true)
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
	_load_masks()
	var variants: Array = manifest.get("variants", [""])
	active_variant = str(variants[0]) if not variants.is_empty() else ""
	selected_ids.clear()
	next_new_id = 1
	ceiling_hit = bool(manifest.get("height_over_ceiling", false))
	findings.clear()
	findings_stale = false
	_saved_generation = 0
	UndoStack.clear()
	mark_saved()
	_rebuild_object_index()
	_rebuild_class_index()
	session_changed.emit()
	water_changed.emit(water_level())


func persist() -> void:
	if not has_session:
		return
	field.write_r16(session_dir.path_join("terrain.r16"))
	_write_materials()
	_write_json(session_dir.path_join("objects.json"), objects)
	_write_masks()
	_write_json(session_dir.path_join("features.json"), features)
	_write_json(session_dir.path_join("aipaths.json"), aipaths)
	_write_json(session_dir.path_join("dirty.json"), dirty)
	_write_json(session_dir.path_join("meta.json"), meta)


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
	aipaths = {}
	clear_aipath_selection()
	masks.clear()
	mask_texture = null
	mask_image = null
	_reset_terrain_selection(true)
	field = HeightFieldScript.new()
	materials = PackedInt32Array()
	has_session = false
	_saved_generation = 0
	_objects_by_id.clear()
	_variant_by_id.clear()
	_indexed_objects = objects
	_mat_gpu_dirty = false
	_mask_gpu_dirty = false
	_mask_gpu_stem = ""
	_selection_gpu_dirty = false
	session_changed.emit()


func mark_terrain_dirty() -> void:
	dirty["terrain"] = true
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
	_ensure_feature_groups()
	var before_n := _feature_array("water").size()
	if v < 0.0:
		features["water"] = []
	else:
		var waters: Array = _feature_array("water")
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
			if float(waters[0].get("level_m", -1.0)) != v:
				adopt_legacy_feature(waters[0])
			waters[0]["level_m"] = v
		features["water"] = waters
	_prune_orphaned_masks()
	dirty["features"] = true
	findings_stale = true
	dirty_changed.emit()
	water_changed.emit(v)
	if before_n != _feature_array("water").size():
		features_changed.emit()


func mark_materials_dirty() -> void:
	dirty["materials"] = true
	findings_stale = true
	dirty_changed.emit()
	materials_changed.emit()


func mark_features_dirty() -> void:
	# dirty.json has no masks slot; BzSave reads features.json + masks/<stem>.u8.
	dirty["features"] = true
	findings_stale = true
	dirty_changed.emit()
	mask_changed.emit()


func active_paths() -> Array:
	return BzOpen.paths_of(aipaths, active_variant)


func replace_variant_paths(variant: String, recs: Array) -> void:
	_ensure_aipaths_bundle()
	var by: Dictionary = aipaths.get("variants", {})
	by[variant] = {"paths": _dup_paths(recs)}
	aipaths["variants"] = by
	if variant == "":
		aipaths["paths"] = _dup_paths(recs)
	elif not aipaths.has("paths") or typeof(aipaths.get("paths", null)) != TYPE_ARRAY:
		aipaths["paths"] = _dup_paths(recs)
	mark_aipaths_dirty(variant)
	aipaths_changed.emit()


func mark_aipaths_dirty(variant: String = "") -> void:
	_ensure_aipaths_dirty_slot()
	var slot: Variant = dirty.get("aipaths")
	if typeof(slot) != TYPE_DICTIONARY:
		dirty["aipaths"] = {}
		slot = dirty["aipaths"]
	(slot as Dictionary)[variant] = true
	findings_stale = true
	dirty_changed.emit()


func clear_aipath_selection() -> void:
	selected_path_index = -1
	selected_point_index = -1
	aipaths_changed.emit()


func select_aipath(path_i: int, point_i: int = -1) -> void:
	selected_path_index = path_i
	selected_point_index = point_i
	aipaths_changed.emit()


func path_record(path_i: int, variant: String = "") -> Dictionary:
	var recs: Array = BzOpen.paths_of(aipaths, variant)
	if path_i < 0 or path_i >= recs.size():
		return {}
	if typeof(recs[path_i]) != TYPE_DICTIONARY:
		return {}
	return recs[path_i]


func alloc_path_name(variant: String = "") -> String:
	var recs: Array = BzOpen.paths_of(aipaths, variant)
	var used := {}
	for rec_v in recs:
		if typeof(rec_v) == TYPE_DICTIONARY:
			used[str((rec_v as Dictionary).get("name", "")).to_lower()] = true
	var i := 1
	while used.has("path_%d" % i):
		i += 1
	return "path_%d" % i


func default_new_path(variant: String = "", x: float = -1.0, z: float = -1.0) -> Dictionary:
	var recs: Array = BzOpen.paths_of(aipaths, variant)
	var cx := x
	var cz := z
	if cx < 0.0 or cz < 0.0:
		cx = float(width_m) * 0.5 if width_m > 0 else 640.0
		cz = float(depth_m) * 0.5 if depth_m > 0 else 640.0
	return {
		"name": alloc_path_name(variant),
		"points": [[cx, cz], [cx + 80.0, cz + 80.0]],
		"old_ptr": BzOpen.next_old_ptr(recs),
		"pathType": "00000000",
		"has_label": true,
		"size": 0,
		"pointCount": 2,
	}


func _fallback_parse_aipaths() -> Dictionary:
	if session_dir.is_empty():
		return {"paths": [], "variants": {}}
	var source: String = session_dir.path_join("residue").path_join("source")
	var variants: Array = manifest.get("variants", [""])
	if typeof(variants) != TYPE_ARRAY or variants.is_empty():
		variants = [""]
	return BzOpen.collect_session_aipaths(source, stem, variants)


func _ensure_aipaths_bundle() -> void:
	if typeof(aipaths.get("variants", null)) != TYPE_DICTIONARY:
		var by := {}
		var existing: Array = aipaths.get("paths", []) if typeof(aipaths.get("paths", null)) == TYPE_ARRAY else []
		by[active_variant] = {"paths": existing}
		aipaths["variants"] = by
		if not aipaths.has("paths"):
			aipaths["paths"] = existing
	if typeof(aipaths.get("paths", null)) != TYPE_ARRAY:
		aipaths["paths"] = []


func _ensure_aipaths_dirty_slot() -> void:
	if typeof(dirty.get("aipaths", null)) == TYPE_DICTIONARY:
		return
	var slot := {}
	var variants: Array = manifest.get("variants", [""])
	if typeof(variants) != TYPE_ARRAY or variants.is_empty():
		variants = [""]
	for v in variants:
		slot[str(v)] = false
	dirty["aipaths"] = slot


func _dup_paths(recs: Array) -> Array:
	var out: Array = []
	for rec_v in recs:
		if typeof(rec_v) == TYPE_DICTIONARY:
			out.append((rec_v as Dictionary).duplicate(true))
		else:
			out.append(rec_v)
	return out


func has_heightmap() -> bool:
	return field != null and field.grid_x > 0 and field.grid_z > 0


func load_features_and_masks() -> void:
	if session_dir.is_empty():
		return
	features = _read_json(session_dir.path_join("features.json"))
	if features.is_empty():
		features = {"water": [], "plants": []}
	_ensure_feature_groups()
	_load_masks()
	features_changed.emit()
	water_changed.emit(water_level())


func add_water_feature() -> Dictionary:
	var feat_stem := alloc_feature_stem("water")
	if feat_stem.is_empty():
		return {}
	var lvl := water_level()
	if lvl < 0.0:
		lvl = 100.0
	var rec := {
		"stem": feat_stem,
		"level_m": lvl,
		"mask": "masks/%s.u8" % feat_stem,
		"variant_scope": "all",
	}
	insert_feature("water", rec)
	return rec


func add_plant_feature() -> Dictionary:
	var feat_stem := alloc_feature_stem("plant")
	if feat_stem.is_empty():
		return {}
	var rec := {
		"stem": feat_stem,
		"mask": "masks/%s.u8" % feat_stem,
		"density": 260,
		"seed": 0,
	}
	insert_feature("plants", rec)
	return rec


func insert_feature(group: String, rec: Dictionary, mask: PackedByteArray = PackedByteArray()) -> void:
	_ensure_feature_groups()
	if group != "water" and group != "plants":
		return
	var arr: Array = features[group]
	arr.append(rec.duplicate(true))
	var feat_stem := str(rec.get("stem", ""))
	if not feat_stem.is_empty():
		if mask.is_empty():
			create_mask(feat_stem)
		else:
			masks[feat_stem] = mask.duplicate()
			_bind_mask_path(feat_stem)
	mark_features_dirty()
	if group == "water":
		water_changed.emit(water_level())
	features_changed.emit()


func remove_feature(group: String, feat_stem: String) -> Dictionary:
	_ensure_feature_groups()
	var arr: Array = _feature_array(group)
	var removed := {}
	var kept: Array = []
	for rec in arr:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		if str(rec.get("stem", "")) == feat_stem:
			removed = (rec as Dictionary).duplicate(true)
			continue
		kept.append(rec)
	features[group] = kept
	var mask := PackedByteArray()
	if masks.has(feat_stem):
		mask = (masks[feat_stem] as PackedByteArray).duplicate()
		masks.erase(feat_stem)
	if ToolState.mask_stem == feat_stem:
		ToolState.clear_mask_target()
	mark_features_dirty()
	if group == "water":
		water_changed.emit(water_level())
	features_changed.emit()
	return {"record": removed, "mask": mask}


func apply_feature_edit(group: String, find_stem: String, new_rec: Dictionary, new_mask: PackedByteArray) -> void:
	_ensure_feature_groups()
	var arr: Array = _feature_array(group)
	var idx := _index_of_stem(arr, find_stem)
	if idx < 0:
		idx = _index_of_stem(arr, str(new_rec.get("stem", "")))
	if idx < 0:
		return
	var old_stem := str((arr[idx] as Dictionary).get("stem", ""))
	var rec := new_rec.duplicate(true)
	arr[idx] = rec
	var new_stem := str(rec.get("stem", ""))
	if old_stem != new_stem and masks.has(old_stem):
		masks.erase(old_stem)
	if not new_stem.is_empty():
		masks[new_stem] = new_mask.duplicate()
		_bind_mask_path(new_stem)
	if old_stem != new_stem and ToolState.mask_stem == old_stem:
		var kind := "plants" if group == "plants" else "water"
		ToolState.set_mask_target(kind, new_stem)
	mark_features_dirty()
	if group == "water":
		water_changed.emit(water_level())
	features_changed.emit()


## Editing a legacy (map-shipped) feature adopts it: the flag clears so
## the next save regenerates its mesh/material/odf and carrier with the
## editor's known-good pattern, replacing the shipped files.
func adopt_legacy_feature(rec: Dictionary) -> void:
	if typeof(rec) == TYPE_DICTIONARY and rec.has("legacy"):
		rec.erase("legacy")
		EditorFeedback.log(
			"%s: adopted — saving will regenerate this feature's mesh"
			% str(rec.get("stem", "feature"))
		)


func set_feature_field(group: String, feat_stem: String, key: String, value: Variant) -> void:
	var rec := find_feature(group, feat_stem)
	if rec.is_empty():
		return
	rec[key] = value
	adopt_legacy_feature(rec)
	mark_features_dirty()
	if group == "water" and key == "level_m" and _is_first_water(feat_stem):
		water_changed.emit(float(value))


func rename_feature(group: String, old_stem: String, new_stem: String) -> String:
	var err := validate_feature_stem(new_stem, old_stem)
	if not err.is_empty():
		return err
	var rec := find_feature(group, old_stem)
	if rec.is_empty():
		return "no such feature"
	rec["stem"] = new_stem
	if rec.has("mask") or masks.has(old_stem):
		rec["mask"] = "masks/%s.u8" % new_stem
	if masks.has(old_stem):
		masks[new_stem] = masks[old_stem]
		masks.erase(old_stem)
	if ToolState.mask_stem == old_stem:
		var kind := "plants" if group == "plants" else "water"
		ToolState.set_mask_target(kind, new_stem)
	mark_features_dirty()
	features_changed.emit()
	return ""


func find_feature(group: String, feat_stem: String) -> Dictionary:
	for rec in _feature_array(group):
		if typeof(rec) == TYPE_DICTIONARY and str(rec.get("stem", "")) == feat_stem:
			return rec
	return {}


func find_feature_group(feat_stem: String) -> String:
	if not find_feature("water", feat_stem).is_empty():
		return "water"
	if not find_feature("plants", feat_stem).is_empty():
		return "plants"
	return ""


func create_mask(feat_stem: String) -> PackedByteArray:
	return ensure_mask(feat_stem)


func ensure_mask(feat_stem: String) -> PackedByteArray:
	if feat_stem.is_empty():
		return PackedByteArray()
	if masks.has(feat_stem) and masks[feat_stem] is PackedByteArray:
		var existing: PackedByteArray = masks[feat_stem]
		var n := _mask_cell_count()
		if n <= 0 or existing.size() == n:
			_bind_mask_path(feat_stem)
			return existing
	var bytes := PackedByteArray()
	var n2 := _mask_cell_count()
	if n2 > 0:
		bytes.resize(n2)
		bytes.fill(0)
	masks[feat_stem] = bytes
	_bind_mask_path(feat_stem)
	return bytes


func get_mask(feat_stem: String) -> PackedByteArray:
	if masks.has(feat_stem) and masks[feat_stem] is PackedByteArray:
		return masks[feat_stem]
	return PackedByteArray()


func paint_mask_rect(feat_stem: String, x0: int, z0: int, w: int, d: int, value: int) -> void:
	var n := maxi(0, w) * maxi(0, d)
	var vals := PackedByteArray()
	vals.resize(n)
	vals.fill(value & 0xFF)
	write_mask_rect(feat_stem, x0, z0, w, d, vals)


func write_mask_rect(feat_stem: String, x0: int, z0: int, w: int, d: int, values: PackedByteArray) -> void:
	if feat_stem.is_empty() or not has_heightmap():
		return
	var owner_group := find_feature_group(feat_stem)
	if not owner_group.is_empty():
		adopt_legacy_feature(find_feature(owner_group, feat_stem))
	var mask := ensure_mask(feat_stem)
	var gx := field.grid_x
	var gz := field.grid_z
	var n := gx * gz
	if mask.size() != n:
		mask.resize(n)
		masks[feat_stem] = mask
	var i := 0
	for z in range(z0, z0 + d):
		for x in range(x0, x0 + w):
			if i >= values.size():
				break
			if x >= 0 and z >= 0 and x < gx and z < gz:
				mask[z * gx + x] = values[i]
			i += 1
	upload_mask(feat_stem)
	flush_mask()
	mark_features_dirty()


func upload_mask(feat_stem: String) -> void:
	if not has_heightmap() or feat_stem.is_empty():
		return
	_mask_gpu_stem = feat_stem
	_mask_gpu_dirty = true


func flush_mask() -> int:
	if not _mask_gpu_dirty:
		return 0
	_mask_gpu_dirty = false
	if not has_heightmap() or _mask_gpu_stem.is_empty():
		return 0
	var mask := ensure_mask(_mask_gpu_stem)
	var gx := field.grid_x
	var gz := field.grid_z
	var n := gx * gz
	if mask.size() != n:
		mask.resize(n)
		masks[_mask_gpu_stem] = mask
	mask_image = Image.create_from_data(gx, gz, false, Image.FORMAT_R8, mask)
	if mask_texture == null or mask_texture.get_width() != gx or mask_texture.get_height() != gz:
		mask_texture = ImageTexture.create_from_image(mask_image)
	else:
		mask_texture.update(mask_image)
	return n


func alloc_feature_stem(prefix: String) -> String:
	var used := _used_stems()
	var pref := prefix
	if pref.is_empty():
		pref = "feat"
	if pref.length() > 7:
		pref = pref.substr(0, 7)
	var max_digits := 8 - pref.length()
	if max_digits < 1:
		return ""
	var cap := 1
	for _i in max_digits:
		cap *= 10
	cap -= 1
	for i in range(1, cap + 1):
		var cand := "%s%d" % [pref, i]
		if cand.length() > 8:
			continue
		if not used.has(cand.to_lower()):
			return cand
	return ""


func validate_feature_stem(feat_stem: String, ignore_stem: String = "") -> String:
	var cleaned := feat_stem.strip_edges()
	if cleaned.is_empty() or not _stem_alnum_ok(cleaned):
		return "stem must be 1–8 alphanumeric characters"
	if cleaned.length() > 8:
		return "stem is %d characters; the engine truncates above 8" % cleaned.length()
	var key := cleaned.to_lower()
	if not stem.is_empty() and key == stem.to_lower():
		return "feature stem collides with the map stem"
	var ignore := ignore_stem.strip_edges().to_lower()
	for rec in _iter_features():
		var other := str(rec.get("stem", "")).to_lower()
		if other.is_empty() or other == ignore:
			continue
		if other == key:
			return "feature stem '%s' is already used" % cleaned
	return ""


func _feature_array(group: String) -> Array:
	var raw: Variant = features.get(group, [])
	if typeof(raw) != TYPE_ARRAY:
		return []
	return raw


func _iter_features() -> Array:
	var out: Array = []
	for rec in _feature_array("water"):
		if typeof(rec) == TYPE_DICTIONARY:
			out.append(rec)
	for rec in _feature_array("plants"):
		if typeof(rec) == TYPE_DICTIONARY:
			out.append(rec)
	return out


func _used_stems() -> Dictionary:
	var used := {}
	if not stem.is_empty():
		used[stem.to_lower()] = true
	for rec in _iter_features():
		var s := str(rec.get("stem", "")).to_lower()
		if not s.is_empty():
			used[s] = true
	return used


func _index_of_stem(arr: Array, feat_stem: String) -> int:
	for i in arr.size():
		var rec: Variant = arr[i]
		if typeof(rec) == TYPE_DICTIONARY and str(rec.get("stem", "")) == feat_stem:
			return i
	return -1


func _is_first_water(feat_stem: String) -> bool:
	var waters := _feature_array("water")
	if waters.is_empty() or typeof(waters[0]) != TYPE_DICTIONARY:
		return false
	return str(waters[0].get("stem", "")) == feat_stem


func _mask_cell_count() -> int:
	if field == null:
		return 0
	return field.grid_x * field.grid_z


func _ensure_feature_groups() -> void:
	if typeof(features.get("water", null)) != TYPE_ARRAY:
		features["water"] = []
	if typeof(features.get("plants", null)) != TYPE_ARRAY:
		features["plants"] = []


func _bind_mask_path(feat_stem: String) -> void:
	var rec := find_feature("water", feat_stem)
	if rec.is_empty():
		rec = find_feature("plants", feat_stem)
	if rec.is_empty():
		return
	if str(rec.get("mask", "")).is_empty():
		rec["mask"] = "masks/%s.u8" % feat_stem


func _prune_orphaned_masks() -> void:
	var keep := {}
	for rec in _iter_features():
		var s := str(rec.get("stem", ""))
		if not s.is_empty():
			keep[s] = true
	var drop: Array = []
	for key in masks.keys():
		if not keep.has(str(key)):
			drop.append(key)
	for key in drop:
		masks.erase(key)


func _load_masks() -> void:
	masks.clear()
	var n := _mask_cell_count()
	if n <= 0 or session_dir.is_empty():
		return
	for rec in _iter_features():
		var feat_stem := str(rec.get("stem", ""))
		var rel := str(rec.get("mask", "")).strip_edges()
		if feat_stem.is_empty() or rel.is_empty():
			continue
		var path := rel if rel.is_absolute_path() else session_dir.path_join(rel)
		if not FileAccess.file_exists(path):
			continue
		var raw := FileAccess.get_file_as_bytes(path)
		if raw.size() != n:
			continue
		masks[feat_stem] = raw


func _write_masks() -> void:
	if session_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(session_dir.path_join("masks"))
	for rec in _iter_features():
		var feat_stem := str(rec.get("stem", ""))
		if feat_stem.is_empty() or not masks.has(feat_stem):
			continue
		var rel := str(rec.get("mask", "")).strip_edges()
		if rel.is_empty():
			rel = "masks/%s.u8" % feat_stem
			rec["mask"] = rel
		var path := rel if rel.is_absolute_path() else session_dir.path_join(rel)
		var parent := path.get_base_dir()
		if not parent.is_empty():
			DirAccess.make_dir_recursive_absolute(parent)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			continue
		var data: PackedByteArray = masks[feat_stem]
		file.store_buffer(data)


func _stem_alnum_ok(s: String) -> bool:
	if s.is_empty():
		return false
	for i in s.length():
		var c: int = s.unicode_at(i)
		var is_az := (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
		var is_d := c >= 48 and c <= 57
		if not is_az and not is_d:
			return false
	return true


func touch_object(variant: String, object_id: String) -> void:
	if not dirty.has("objects") or typeof(dirty["objects"]) != TYPE_DICTIONARY:
		dirty["objects"] = {}
	var per: Dictionary = dirty["objects"]
	if not per.has(variant):
		per[variant] = []
	var ids: Array = per[variant]
	if object_id not in ids:
		ids.append(object_id)
	findings_stale = true
	dirty_changed.emit()


func find_object(object_id: String) -> Dictionary:
	if object_id.is_empty():
		return {}
	_ensure_object_index()
	var rec: Variant = _objects_by_id.get(object_id, null)
	if typeof(rec) == TYPE_DICTIONARY:
		return rec
	return {}


func find_object_variant(object_id: String) -> String:
	if object_id.is_empty():
		return active_variant
	_ensure_object_index()
	if _variant_by_id.has(object_id):
		return str(_variant_by_id[object_id])
	return active_variant


func add_object_record(variant: String, rec: Dictionary) -> void:
	if not objects.has(variant):
		objects[variant] = []
	objects[variant].append(rec)
	var oid := str(rec.get("id", ""))
	_objects_by_id[oid] = rec
	_variant_by_id[oid] = str(variant)
	touch_object(variant, oid)
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
	_objects_by_id.erase(object_id)
	_variant_by_id.erase(object_id)
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
	if prjid.is_empty():
		return {}
	_ensure_class_index()
	var rec: Variant = _class_by_prjid.get(prjid.to_lower(), null)
	if typeof(rec) == TYPE_DICTIONARY:
		return rec
	_rebuild_class_index()
	rec = _class_by_prjid.get(prjid.to_lower(), null)
	if typeof(rec) == TYPE_DICTIONARY:
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
	object_poses_changed.emit()


func set_material(tx: int, tz: int, mat_id: int) -> void:
	if tx < 0 or tz < 0 or tx >= mat_grid_x or tz >= mat_grid_z:
		return
	# Solid tile: mat_a = mat_b = mat_id, rest zero. Matches encode_entry.
	var word := ((mat_id & 0xF) << 12) | ((mat_id & 0xF) << 8)
	materials[tz * mat_grid_x + tx] = word


## F2 §5: recode a rect (plus a 1-tile halo) as solids / caps / diagonals
## from each cell's base nibble and its four orthogonal neighbours.
func rematch_materials_rect(x0: int, z0: int, w: int, d: int) -> void:
	if mat_grid_x < 1 or mat_grid_z < 1 or materials.is_empty():
		return
	var gx := mat_grid_x
	var gz := mat_grid_z
	var fill := PackedByteArray()
	fill.resize(gx * gz)
	var nfill := mini(fill.size(), materials.size())
	for i in nfill:
		fill[i] = (materials[i] >> 12) & 0xF
	var xa := clampi(x0, 0, gx - 1)
	var za := clampi(z0, 0, gz - 1)
	var xb := clampi(x0 + w - 1, 0, gx - 1)
	var zb := clampi(z0 + d - 1, 0, gz - 1)
	if xb < xa or zb < za:
		return
	for z in range(za, zb + 1):
		for x in range(xa, xb + 1):
			var self_m: int = fill[z * gx + x]
			var nn: int = fill[(z - 1) * gx + x] if z > 0 else self_m
			var ee: int = fill[z * gx + x + 1] if x + 1 < gx else self_m
			var ss: int = fill[(z + 1) * gx + x] if z + 1 < gz else self_m
			var ww: int = fill[z * gx + x - 1] if x > 0 else self_m
			materials[z * gx + x] = BzMat.autotile_neighbors(self_m, nn, ee, ss, ww)
	upload_materials()


func write_materials_rect(x0: int, z0: int, w: int, d: int, values: PackedInt32Array) -> void:
	var i := 0
	for z in range(z0, z0 + d):
		for x in range(x0, x0 + w):
			if x >= 0 and z >= 0 and x < mat_grid_x and z < mat_grid_z:
				materials[z * mat_grid_x + x] = values[i]
			i += 1
	upload_materials()
	flush_materials()


func upload_materials() -> void:
	if mat_grid_x < 1 or mat_grid_z < 1:
		return
	_mat_gpu_dirty = true


func flush_materials() -> int:
	if not _mat_gpu_dirty:
		return 0
	_mat_gpu_dirty = false
	if mat_grid_x < 1 or mat_grid_z < 1:
		return 0
	# Full tile word per cell (F2 §2): R = byte0 (orientation<<4 | variant),
	# G = byte1 (base<<4 | transition). The shader decodes the word and draws
	# the same atlas tile the game would.
	var n := mat_grid_x * mat_grid_z
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var count := mini(n, materials.size())
	for i in count:
		bytes[i * 2] = materials[i] & 0xFF
		bytes[i * 2 + 1] = (materials[i] >> 8) & 0xFF
	mat_image = Image.create_from_data(mat_grid_x, mat_grid_z, false, Image.FORMAT_RG8, bytes)
	if mat_texture == null or mat_texture.get_width() != mat_grid_x or mat_texture.get_height() != mat_grid_z:
		mat_texture = ImageTexture.create_from_image(mat_image)
	else:
		mat_texture.update(mat_image)
	return n * 2


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
	var buf := file.get_buffer(n * 2)
	materials.resize(n)
	var got := mini(n, int(buf.size() / 2))
	for i in got:
		materials[i] = buf.decode_u16(i * 2)
	upload_materials()
	flush_materials()


func _write_materials() -> void:
	if mat_grid_x < 1:
		return
	var path := session_dir.path_join("materials.u16")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	var n := materials.size()
	var buf := PackedByteArray()
	buf.resize(n * 2)
	for i in n:
		buf.encode_u16(i * 2, materials[i] & 0xFFFF)
	file.store_buffer(buf)


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
	file.store_string(JSON.stringify(data))


## True when no terrain selection is active (every cell is editable).
func selection_empty() -> bool:
	return terrain_selection.is_empty() or _selection_count <= 0


func clear_selection() -> void:
	if terrain_selection.is_empty() and _selection_count == 0:
		return
	_reset_terrain_selection(true)


func selection_cell_count() -> int:
	if terrain_selection.is_empty():
		return 0
	return _selection_count


func selection_area_m2() -> float:
	var cell := HeightField.CELL_M
	return float(selection_cell_count()) * cell * cell


## 1.0 when empty (PS: no selection = all editable). Else mask/255 at the cell.
func selection_factor(x: int, z: int) -> float:
	if terrain_selection.is_empty() or field == null:
		return 1.0
	var gx := field.grid_x
	var gz := field.grid_z
	if gx < 1 or gz < 1 or terrain_selection.size() != gx * gz:
		return 1.0
	if x < 0 or z < 0 or x >= gx or z >= gz:
		return 0.0
	return float(terrain_selection[z * gx + x]) / 255.0


func selection_factor_world(x_m: float, z_m: float) -> float:
	if terrain_selection.is_empty() or field == null:
		return 1.0
	var cell := HeightField.CELL_M
	return selection_factor(int(floor(x_m / cell)), int(floor(z_m / cell)))


func select_all_terrain() -> void:
	if not has_heightmap():
		return
	var n := field.grid_x * field.grid_z
	terrain_selection.resize(n)
	terrain_selection.fill(255)
	_selection_count = n
	upload_terrain_selection()
	selection_changed.emit()


func invert_terrain_selection() -> void:
	if not has_heightmap():
		return
	if selection_empty():
		select_all_terrain()
		return
	var n := field.grid_x * field.grid_z
	if terrain_selection.size() != n:
		select_all_terrain()
		return
	var count := 0
	for i in n:
		var v := 255 - int(terrain_selection[i])
		terrain_selection[i] = v
		if v > 0:
			count += 1
	if count == 0:
		_reset_terrain_selection(true)
		return
	_selection_count = count
	upload_terrain_selection()
	selection_changed.emit()


func feather_terrain_selection(radius_m: float) -> void:
	if selection_empty() or not has_heightmap():
		return
	var r := maxi(1, int(round(radius_m / HeightField.CELL_M)))
	var gx := field.grid_x
	var gz := field.grid_z
	var n := gx * gz
	if terrain_selection.size() != n:
		return
	var tmp := PackedInt32Array()
	tmp.resize(n)
	var k := 2 * r + 1
	for z in gz:
		for x in gx:
			var acc := 0
			for dx in range(-r, r + 1):
				var xx := clampi(x + dx, 0, gx - 1)
				acc += int(terrain_selection[z * gx + xx])
			tmp[z * gx + x] = acc
	var count := 0
	for x in gx:
		for z in gz:
			var acc := 0
			for dz in range(-r, r + 1):
				var zz := clampi(z + dz, 0, gz - 1)
				acc += tmp[zz * gx + x]
			var v := int(round(float(acc) / float(k * k)))
			v = clampi(v, 0, 255)
			terrain_selection[z * gx + x] = v
			if v > 0:
				count += 1
	if count == 0:
		_reset_terrain_selection(true)
		return
	_selection_count = count
	upload_terrain_selection()
	selection_changed.emit()


func grow_terrain_selection(cells: int) -> void:
	_morph_terrain_selection(maxi(0, cells), true)


func shrink_terrain_selection(cells: int) -> void:
	_morph_terrain_selection(maxi(0, cells), false)


func stamp_terrain_selection(
	cx_m: float,
	cz_m: float,
	radius_m: float,
	falloff: float,
	shape: String,
	mode: String
) -> void:
	if not has_heightmap():
		return
	if mode == SEL_SUBTRACT and selection_empty():
		return
	var gx := field.grid_x
	var gz := field.grid_z
	var cell := HeightField.CELL_M
	var r_cells := int(ceil(radius_m / cell))
	var cx := int(floor(cx_m / cell))
	var cz := int(floor(cz_m / cell))
	var x0 := maxi(0, cx - r_cells)
	var z0 := maxi(0, cz - r_cells)
	var x1 := mini(gx - 1, cx + r_cells)
	var z1 := mini(gz - 1, cz + r_cells)
	if x1 < x0 or z1 < z0:
		return
	if terrain_selection.is_empty():
		if mode == SEL_SUBTRACT:
			return
		terrain_selection.resize(gx * gz)
		terrain_selection.fill(0)
		_selection_count = 0
	var n := gx * gz
	if terrain_selection.size() != n:
		terrain_selection.resize(n)
		terrain_selection.fill(0)
		_selection_count = 0
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := (float(x) + 0.5) * cell
			var wz := (float(z) + 0.5) * cell
			var w := SculptTool.brush_weight(cx_m, cz_m, wx, wz, radius_m, falloff, shape)
			if w <= 0.0:
				continue
			var idx := z * gx + x
			var add_v := int(round(w * 255.0))
			var old_v := int(terrain_selection[idx])
			var new_v := _combine_sel(old_v, add_v, mode)
			if new_v == old_v:
				continue
			terrain_selection[idx] = new_v
			if old_v <= 0 and new_v > 0:
				_selection_count += 1
			elif old_v > 0 and new_v <= 0:
				_selection_count -= 1
	if _selection_count <= 0:
		_reset_terrain_selection(true)
		return
	_selection_gpu_dirty = true


func rect_terrain_selection(x0: int, z0: int, x1: int, z1: int, mode: String) -> void:
	if not has_heightmap():
		return
	if mode == SEL_SUBTRACT and selection_empty():
		return
	var gx := field.grid_x
	var gz := field.grid_z
	var xa := clampi(mini(x0, x1), 0, gx - 1)
	var xb := clampi(maxi(x0, x1), 0, gx - 1)
	var za := clampi(mini(z0, z1), 0, gz - 1)
	var zb := clampi(maxi(z0, z1), 0, gz - 1)
	var src := PackedByteArray()
	src.resize(gx * gz)
	src.fill(0)
	for z in range(za, zb + 1):
		for x in range(xa, xb + 1):
			src[z * gx + x] = 255
	_merge_selection(src, mode)


func wand_terrain_selection(sx: int, sz: int, tolerance_m: float, mode: String) -> void:
	if not has_heightmap():
		return
	if mode == SEL_SUBTRACT and selection_empty():
		return
	var gx := field.grid_x
	var gz := field.grid_z
	sx = clampi(sx, 0, gx - 1)
	sz = clampi(sz, 0, gz - 1)
	var src := flood_fill_height(field, sx, sz, tolerance_m)
	_merge_selection(src, mode)


func select_terrain_by_material(mat_id: int, mode: String = SEL_REPLACE) -> void:
	if not has_heightmap() or mat_grid_x < 1 or mat_grid_z < 1:
		return
	if mode == SEL_SUBTRACT and selection_empty():
		return
	var gx := field.grid_x
	var gz := field.grid_z
	var src := PackedByteArray()
	src.resize(gx * gz)
	src.fill(0)
	var want := mat_id & 0xF
	var cell := HeightField.CELL_M
	for z in gz:
		for x in gx:
			var xm := (float(x) + 0.5) * cell
			var zm := (float(z) + 0.5) * cell
			if material_at(xm, zm) == want:
				src[z * gx + x] = 255
	_merge_selection(src, mode)


## Iterative 4-connected flood. Matching cells are 255. Safe on 1024×1024.
static func flood_fill_height(field: HeightField, sx: int, sz: int, tolerance_m: float) -> PackedByteArray:
	var out := PackedByteArray()
	if field == null or field.grid_x < 1 or field.grid_z < 1:
		return out
	var gx := field.grid_x
	var gz := field.grid_z
	var n := gx * gz
	out.resize(n)
	out.fill(0)
	sx = clampi(sx, 0, gx - 1)
	sz = clampi(sz, 0, gz - 1)
	var seed_h := field.height_m(sx, sz)
	var tol := maxf(0.0, tolerance_m)
	var seen := PackedByteArray()
	seen.resize(n)
	seen.fill(0)
	var q := PackedInt32Array()
	q.resize(n)
	var head := 0
	var tail := 0
	var start := sz * gx + sx
	q[tail] = start
	tail += 1
	seen[start] = 1
	var dxs := PackedInt32Array([-1, 1, 0, 0])
	var dzs := PackedInt32Array([0, 0, -1, 1])
	while head < tail:
		var idx: int = q[head]
		head += 1
		var x := idx % gx
		var z := int(idx / gx)
		if absf(field.height_m(x, z) - seed_h) > tol:
			continue
		out[idx] = 255
		for i in 4:
			var nx := x + dxs[i]
			var nz := z + dzs[i]
			if nx < 0 or nz < 0 or nx >= gx or nz >= gz:
				continue
			var nidx := nz * gx + nx
			if seen[nidx] != 0:
				continue
			seen[nidx] = 1
			q[tail] = nidx
			tail += 1
	return out


func upload_terrain_selection() -> void:
	_selection_gpu_dirty = true
	flush_terrain_selection()


func flush_terrain_selection() -> int:
	if not _selection_gpu_dirty:
		return 0
	_selection_gpu_dirty = false
	if not has_heightmap() or terrain_selection.is_empty() or _selection_count <= 0:
		selection_image = null
		selection_texture = null
		return 0
	var gx := field.grid_x
	var gz := field.grid_z
	var n := gx * gz
	if terrain_selection.size() != n:
		return 0
	selection_image = Image.create_from_data(gx, gz, false, Image.FORMAT_R8, terrain_selection)
	if selection_texture == null or selection_texture.get_width() != gx or selection_texture.get_height() != gz:
		selection_texture = ImageTexture.create_from_image(selection_image)
	else:
		selection_texture.update(selection_image)
	selection_changed.emit()
	return n


func _reset_terrain_selection(emit_change: bool) -> void:
	var had := not terrain_selection.is_empty() or _selection_count > 0
	terrain_selection = PackedByteArray()
	selection_texture = null
	selection_image = null
	_selection_count = 0
	_selection_gpu_dirty = false
	if emit_change and had:
		selection_changed.emit()


func _merge_selection(src: PackedByteArray, mode: String) -> void:
	if not has_heightmap():
		return
	var gx := field.grid_x
	var gz := field.grid_z
	var n := gx * gz
	if src.size() != n:
		return
	if mode == SEL_SUBTRACT and selection_empty():
		return
	if mode == SEL_REPLACE or terrain_selection.is_empty():
		if mode == SEL_SUBTRACT:
			return
		terrain_selection = src.duplicate()
	else:
		if terrain_selection.size() != n:
			terrain_selection.resize(n)
			terrain_selection.fill(0)
		for i in n:
			terrain_selection[i] = _combine_sel(int(terrain_selection[i]), int(src[i]), mode)
	_recount_and_commit()


func _combine_sel(old_v: int, new_v: int, mode: String) -> int:
	match mode:
		SEL_ADD:
			return maxi(old_v, new_v)
		SEL_SUBTRACT:
			return clampi(old_v - new_v, 0, 255)
		_:
			return clampi(new_v, 0, 255)


func _morph_terrain_selection(cells: int, dilate: bool) -> void:
	if cells < 1 or selection_empty() or not has_heightmap():
		return
	var gx := field.grid_x
	var gz := field.grid_z
	var n := gx * gz
	if terrain_selection.size() != n:
		return
	var tmp := PackedByteArray()
	tmp.resize(n)
	for z in gz:
		for x in gx:
			var acc := 0 if dilate else 255
			for dx in range(-cells, cells + 1):
				var xx := clampi(x + dx, 0, gx - 1)
				var v := int(terrain_selection[z * gx + xx])
				acc = maxi(acc, v) if dilate else mini(acc, v)
			tmp[z * gx + x] = acc
	var count := 0
	for x in gx:
		for z in gz:
			var acc := 0 if dilate else 255
			for dz in range(-cells, cells + 1):
				var zz := clampi(z + dz, 0, gz - 1)
				var v := int(tmp[zz * gx + x])
				acc = maxi(acc, v) if dilate else mini(acc, v)
			terrain_selection[z * gx + x] = acc
			if acc > 0:
				count += 1
	if count == 0:
		_reset_terrain_selection(true)
		return
	_selection_count = count
	upload_terrain_selection()
	selection_changed.emit()


func _recount_and_commit() -> void:
	var count := 0
	for i in terrain_selection.size():
		if terrain_selection[i] > 0:
			count += 1
	if count == 0:
		_reset_terrain_selection(true)
		return
	_selection_count = count
	upload_terrain_selection()
	selection_changed.emit()


func rebuild_lookups() -> void:
	_rebuild_object_index()
	_rebuild_class_index()


func flush_gpu() -> int:
	var n := 0
	if field != null:
		n += field.flush_upload()
	n += flush_materials()
	n += flush_mask()
	n += flush_terrain_selection()
	return n


func _ensure_object_index() -> void:
	if is_same(objects, _indexed_objects):
		return
	_rebuild_object_index()


func _rebuild_object_index() -> void:
	_objects_by_id.clear()
	_variant_by_id.clear()
	for variant in objects.keys():
		var recs: Variant = objects[variant]
		if typeof(recs) != TYPE_ARRAY:
			continue
		var vname := str(variant)
		for rec in recs:
			if typeof(rec) != TYPE_DICTIONARY:
				continue
			var oid := str(rec.get("id", ""))
			if oid.is_empty():
				continue
			_objects_by_id[oid] = rec
			_variant_by_id[oid] = vname
	_indexed_objects = objects


func _ensure_class_index() -> void:
	if is_same(asset_index, _indexed_assets):
		return
	_rebuild_class_index()


func _rebuild_class_index() -> void:
	_class_by_prjid.clear()
	var classes: Variant = asset_index.get("classes", [])
	if typeof(classes) != TYPE_ARRAY:
		_indexed_assets = asset_index
		return
	for rec in classes:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var key := str(rec.get("prjid", "")).to_lower()
		if key.is_empty():
			continue
		_class_by_prjid[key] = rec
	_indexed_assets = asset_index


func _uuid4() -> String:
	var hex := "0123456789abcdef"
	var out := ""
	for i in range(32):
		out += hex[randi() % 16]
	return out
