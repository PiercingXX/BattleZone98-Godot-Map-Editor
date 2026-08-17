extends Node3D
class_name ObjectMarkers
## Proxy boxes. Selection and a placement ghost.

var _box: BoxMesh
var _ghost: Node3D
var _by_id: Dictionary = {}
var _gltf_cache: Dictionary = {}


func _ready() -> void:
	_box = BoxMesh.new()
	_box.size = Vector3(8, 6, 8)


func rebuild(objects: Dictionary, field: HeightField) -> void:
	for child in get_children():
		if child == _ghost:
			continue
		child.queue_free()
	_by_id.clear()
	for variant in objects.keys():
		var records: Variant = objects[variant]
		if typeof(records) != TYPE_ARRAY:
			continue
		var ghosted := str(variant) != MapState.active_variant
		for rec in records:
			if typeof(rec) != TYPE_DICTIONARY:
				continue
			_place(rec, field, ghosted, str(variant))


func set_ghost(visible: bool, rec: Dictionary, field: HeightField, normal: Vector3) -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if not visible:
		return
	_ghost = _make_visual(rec, true)
	add_child(_ghost)
	var x := float(rec.get("x", 0.0))
	var z := float(rec.get("z", 0.0))
	var y := field.height_at(x, z) if field else float(rec.get("y", 0.0))
	_ghost.position = Vector3(x, y, z)
	if rec.get("up_convention", "upright") == "follow" and normal.length_squared() > 0.01:
		_ghost.look_at(_ghost.position + Vector3(normal.x, 0.0, normal.z) + Vector3(0.01, 0, 0), normal)
	else:
		_ghost.rotation = Vector3(0.0, deg_to_rad(float(rec.get("yaw_deg", 0.0))), 0.0)


func highlight(ids: Array) -> void:
	for id in _by_id.keys():
		var inst: Node3D = _by_id[id]
		if inst == null:
			continue
		_set_emission(inst, id in ids)


func _set_emission(node: Node, on: bool) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			mi.material_override = mat
		mat.emission_enabled = on
		mat.emission = Color(1.0, 0.85, 0.2)
		mat.emission_energy_multiplier = 0.6
	for child in node.get_children():
		_set_emission(child, on)


func pick(origin: Vector3, direction: Vector3) -> String:
	var best := ""
	var best_t := 1.0e9
	for id in _by_id.keys():
		var inst: Node3D = _by_id[id]
		if inst == null or not inst.visible:
			continue
		var rec := MapState.find_object(str(id))
		if rec.is_empty():
			continue
		if MapState.find_object_variant(str(id)) != MapState.active_variant:
			continue
		var size := _size_for(str(rec.get("prjid", "")))
		var center := inst.position
		var t := _ray_aabb(origin, direction, center, size)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = str(id)
	return best


func _place(rec: Dictionary, field: HeightField, ghost: bool, _variant: String) -> void:
	var inst := _make_visual(rec, ghost)
	var x := float(rec.get("x", 0.0))
	var z := float(rec.get("z", 0.0))
	var y := float(rec.get("y", 0.0))
	if field and field.grid_x > 0 and not bool(rec.get("pinned_y", false)):
		y = field.height_at(x, z)
	inst.position = Vector3(x, y, z)
	inst.rotation.y = deg_to_rad(float(rec.get("yaw_deg", 0.0)))
	add_child(inst)
	_by_id[str(rec.get("id", ""))] = inst


func _make_visual(rec: Dictionary, faded: bool) -> Node3D:
	var prjid := str(rec.get("prjid", ""))
	var loaded := _load_gltf(prjid)
	if loaded != null:
		if faded:
			_fade(loaded)
		return loaded
	var inst := MeshInstance3D.new()
	inst.mesh = _box
	var size := _size_for(prjid)
	inst.scale = Vector3(size.x / 8.0, size.y / 6.0, size.z / 8.0)
	inst.position.y = size.y * 0.5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _color_for(prjid)
	if faded:
		mat.albedo_color.a = 0.22
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inst.material_override = mat
	var wrap := Node3D.new()
	wrap.add_child(inst)
	return wrap


func _load_gltf(prjid: String) -> Node3D:
	var info := MapState.class_info(prjid)
	var path := str(info.get("mesh", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	if not _gltf_cache.has(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			return null
		var scene := doc.generate_scene(state)
		_gltf_cache[path] = scene
	var proto: Node = _gltf_cache[path]
	if proto == null:
		return null
	return proto.duplicate() as Node3D


func _fade(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.85, 1.0, 0.4)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
	for child in node.get_children():
		_fade(child)


func _size_for(prjid: String) -> Vector3:
	var info := MapState.class_info(prjid)
	if not info.is_empty():
		var fp: Array = info.get("footprint_m", [8, 8])
		var h := float(info.get("height_m", 6.0))
		return Vector3(maxf(float(fp[0]), 2.0), maxf(h, 1.0), maxf(float(fp[1]), 2.0))
	var p := prjid.to_lower()
	if p == "player":
		return Vector3(8, 5, 8)
	if p == "pspwn_1":
		return Vector3(5, 2, 5)
	if "geyser" in p or p == "eggeizr1":
		return Vector3(14, 8, 14)
	return Vector3(8, 6, 8)


func _color_for(prjid: String) -> Color:
	var p := prjid.to_lower()
	if p == "player":
		return Color(0.2, 0.85, 0.35)
	if p == "pspwn_1":
		return Color(0.95, 0.8, 0.2)
	if "geyser" in p or p == "eggeizr1":
		return Color(0.95, 0.45, 0.15)
	if p.begins_with("npscr") or p == "sscr_1":
		return Color(0.85, 0.7, 0.2)
	var info := MapState.class_info(prjid)
	match str(info.get("category", "")):
		"building":
			return Color(0.45, 0.5, 0.75)
		"craft":
			return Color(0.3, 0.65, 0.4)
		"environment":
			return Color(0.3, 0.55, 0.5)
	return Color(0.75, 0.75, 0.8)


func _ray_aabb(origin: Vector3, dir: Vector3, center: Vector3, size: Vector3) -> float:
	var minp := center - size * 0.5
	var maxp := center + size * 0.5
	var tmin := -1.0e9
	var tmax := 1.0e9
	for i in 3:
		var o := origin[i]
		var d := dir[i]
		var mn := minp[i]
		var mx := maxp[i]
		if absf(d) < 0.0000001:
			if o < mn or o > mx:
				return -1.0
			continue
		var t1 := (mn - o) / d
		var t2 := (mx - o) / d
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	return tmin if tmin >= 0.0 else tmax
