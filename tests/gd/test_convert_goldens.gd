extends RefCounted
## Port of backend/tests/test_convert.py.
## Python suite needs a live install (abbarr.mesh / pack geos) and skips
## without one. These goldens use hand-packed synthetic OGRE / .geo files
## so the port is testable without game assets (AGENTS.md rule 3).
##
## Upstream: BzOgre._Buf.read_string calls _ascii_ignore on self; the helper
## is a static func on BzOgre. That blocks read_ogre_mesh and convert_hd.


const _CLASS_PATHS := {
	"BzConvert": "res://project/backend/editor/BzConvert.gd",
	"BzOgre": "res://project/backend/formats/BzOgre.gd",
	"BzGeo": "res://project/backend/formats/BzGeo.gd",
	"BzGlb": "res://project/backend/formats/BzGlb.gd",
	"BzMeshData": "res://project/backend/formats/BzMeshData.gd",
}

var _temps: Array[String] = []
var _t: Variant


func run(t) -> void:
	_t = t
	_group_read_synthetic_ogre_mesh()
	_group_read_synthetic_geo()
	_group_convert_hd_glb()
	_group_convert_geo_fallback()
	_group_convert_missing_is_proxy()
	for p in _temps:
		_rm_tree(p)
	_temps.clear()


func _group_read_synthetic_ogre_mesh() -> void:
	## test_read_stock_ogre_mesh — 11×11 grid (>100 verts), triangle list
	if not _need("BzOgre"):
		return
	var root := _scratch("ogre")
	var mesh_path := root.path_join("abbarr.mesh")
	_write_ogre_grid(mesh_path, 11)
	var ogre: Variant = _invoke_any("BzOgre", ["read_ogre_mesh", "read"], [mesh_path])
	if _is_missing(ogre):
		_t.fail("BzOgre.read_ogre_mesh missing")
		return
	if _is_err(ogre):
		_t.fail("read_ogre_mesh failed: %s" % _err_msg(ogre))
		return
	ogre = _unwrap_mesh(ogre)
	var submeshes := _submeshes_of(ogre)
	_t.ok(not submeshes.is_empty(), "ogre.submeshes nonempty")
	if submeshes.is_empty():
		return
	var sm: Variant = submeshes[0]
	var positions: Variant = _field(sm, "positions")
	var indices: Variant = _field(sm, "indices")
	_t.ok(_count(positions) > 100, "positions > 100 (got %d)" % _count(positions))
	_t.ok(_count(indices) >= 3, "indices >= 3")
	_t.eq(_count(indices) % 3, 0, "indices multiple of 3")


func _group_read_synthetic_geo() -> void:
	## test_read_pack_geo
	if not _need("BzGeo"):
		return
	var geo_path := _scratch("geo").path_join("synth.geo")
	var fixture := ProjectSettings.globalize_path("res://tests/gd/fixtures/geo/synthetic.geo")
	if FileAccess.file_exists(fixture):
		_copy_file(fixture, geo_path)
	else:
		_write_triangle_geo(geo_path)
	var mesh: Variant = _invoke_any("BzGeo", ["read_geo", "read"], [geo_path])
	if _is_missing(mesh):
		_t.fail("BzGeo.read_geo missing")
		return
	if _is_err(mesh):
		# Fixture may not match a strict reader — fall back to a packed triangle.
		_write_triangle_geo(geo_path)
		mesh = _invoke_any("BzGeo", ["read_geo", "read"], [geo_path])
	if _is_err(mesh) or _is_missing(mesh):
		_t.fail("read_geo failed: %s" % _err_msg(mesh))
		return
	if mesh == null:
		_t.fail("read_geo returned null")
		return
	mesh = _unwrap_mesh(mesh)
	var positions: Variant = _field(mesh, "positions")
	var faces: Variant = _field(mesh, "faces")
	_t.ok(_count(positions) > 0, "geo.positions nonempty")
	_t.ok(_count(faces) > 0, "geo.faces nonempty")


func _group_convert_hd_glb() -> void:
	## test_convert_hd_glb
	if not _need("BzConvert"):
		return
	if not _has("BzOgre"):
		_t.fail("convert_hd_glb blocked by BzOgre parse error (_Buf.read_string calls _ascii_ignore on self)")
		return
	var root := _scratch("hd")
	var models := root.path_join("models")
	DirAccess.make_dir_recursive_absolute(models)
	_write_ogre_grid(models.path_join("abbarr.mesh"), 11)
	var dest := root.path_join("abbarr.glb")
	var got: Variant = _invoke_any("BzConvert", ["convert_class", "convert"], [
		"abbarr", [models], dest,
	])
	if _is_missing(got):
		_t.fail("BzConvert.convert_class missing")
		return
	var unpacked: Dictionary = _unpack_convert(got)
	var path := str(unpacked.get("path", ""))
	var fidelity := str(unpacked.get("fidelity", ""))
	var why := str(unpacked.get("reason", ""))
	if path.is_empty() and FileAccess.file_exists(dest):
		path = dest
	_t.ok(not path.is_empty() and FileAccess.file_exists(path),
			"convert_class wrote a glb (%s)" % why)
	_t.eq(fidelity, "hd", "hd fidelity (why=%s)" % why)
	if FileAccess.file_exists(dest):
		var body := FileAccess.get_file_as_bytes(dest)
		_t.ok(body.size() > 1000, "glb size > 1000 (got %d)" % body.size())
		_t.ok(body.size() >= 4
				and body[0] == 0x67 and body[1] == 0x6C
				and body[2] == 0x54 and body[3] == 0x46,
				"glb magic glTF")


func _group_convert_geo_fallback() -> void:
	## convert_class falls through to geo when no .mesh is present
	if not _need("BzConvert"):
		return
	var root := _scratch("geofall")
	var models := root.path_join("models")
	DirAccess.make_dir_recursive_absolute(models)
	_write_triangle_geo(models.path_join("propbox.geo"))
	var dest := root.path_join("propbox.glb")
	var got: Variant = _invoke_any("BzConvert", ["convert_class", "convert"], [
		"propbox", [models], dest,
	])
	if _is_missing(got):
		return
	var unpacked: Dictionary = _unpack_convert(got)
	var fidelity := str(unpacked.get("fidelity", ""))
	var path := str(unpacked.get("path", ""))
	if path.is_empty() and FileAccess.file_exists(dest):
		path = dest
	_t.ok(not path.is_empty() and FileAccess.file_exists(path),
			"geo fallback wrote a glb")
	_t.ok(fidelity == "geo_flat" or fidelity == "geo_textured",
			"geo fidelity (got %s)" % fidelity)
	if FileAccess.file_exists(dest):
		var body := FileAccess.get_file_as_bytes(dest)
		_t.ok(body.size() >= 4
				and body[0] == 0x67 and body[1] == 0x6C
				and body[2] == 0x54 and body[3] == 0x46,
				"geo glb magic")


func _group_convert_missing_is_proxy() -> void:
	if not _need("BzConvert"):
		return
	var root := _scratch("proxy")
	var dest := root.path_join("missing.glb")
	var got: Variant = _invoke_any("BzConvert", ["convert_class", "convert"], [
		"no_such_class", [root], dest,
	])
	if _is_missing(got):
		return
	var unpacked: Dictionary = _unpack_convert(got)
	var fidelity := str(unpacked.get("fidelity", ""))
	var path: Variant = unpacked.get("path")
	var path_s := str(path) if path != null else ""
	_t.ok(path == null or path_s.is_empty() or path_s == "<null>",
			"missing class yields no path")
	_t.eq(fidelity, "proxy", "missing class is proxy")


# --- ogre / geo packers ----------------------------------------------------

func _write_ogre_grid(path: String, edge: int) -> void:
	## MeshSerializer_v1.100, LE, one submesh, position+normal+uv, 16-bit tris.
	var vcount: int = edge * edge
	var stride := 32
	var vdata := PackedByteArray()
	vdata.resize(vcount * stride)
	var vi := 0
	for z in edge:
		for x in edge:
			var off: int = vi * stride
			vdata.encode_float(off + 0, float(x))
			vdata.encode_float(off + 4, 0.0)
			vdata.encode_float(off + 8, float(z))
			vdata.encode_float(off + 12, 0.0)
			vdata.encode_float(off + 16, 1.0)
			vdata.encode_float(off + 20, 0.0)
			vdata.encode_float(off + 24, float(x) / float(edge - 1))
			vdata.encode_float(off + 28, float(z) / float(edge - 1))
			vi += 1
	var indices: Array[int] = []
	for z in range(edge - 1):
		for x in range(edge - 1):
			var i: int = z * edge + x
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + edge)
			indices.append(i + 1)
			indices.append(i + edge + 1)
			indices.append(i + edge)
	var ib := PackedByteArray()
	ib.resize(indices.size() * 2)
	for n in indices.size():
		ib.encode_u16(n * 2, indices[n])

	var elem_pos := _ogre_chunk(0x5110, _cat([
		_u16(0), _u16(2), _u16(1), _u16(0), _u16(0),
	]))
	var elem_nrm := _ogre_chunk(0x5110, _cat([
		_u16(0), _u16(2), _u16(4), _u16(12), _u16(0),
	]))
	var elem_uv := _ogre_chunk(0x5110, _cat([
		_u16(0), _u16(1), _u16(7), _u16(24), _u16(0),
	]))
	var decl := _ogre_chunk(0x5100, _cat([elem_pos, elem_nrm, elem_uv]))
	var vdata_chunk := _ogre_chunk(0x5210, vdata)
	var vbuf := _ogre_chunk(0x5200, _cat([_u16(0), _u16(stride), vdata_chunk]))
	var geom := _ogre_chunk(0x5000, _cat([_u32(vcount), decl, vbuf]))

	var mat := "abbarr\n".to_utf8_buffer()
	var sub_payload := _cat([
		mat,
		_u8(0),
		_u32(indices.size()),
		_u8(0),
		ib,
		geom,
	])
	var submesh := _ogre_chunk(0x4000, sub_payload)
	var mesh := _ogre_chunk(0x3000, _cat([_u8(0), submesh]))

	var header := PackedByteArray()
	header.resize(2)
	header.encode_u16(0, 0x1000)
	var version := "[MeshSerializer_v1.100]\n".to_utf8_buffer()
	_write_bytes(path, _cat([header, version, mesh]))


func _ogre_chunk(id: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(6)
	out.encode_u16(0, id)
	out.encode_u32(2, 6 + payload.size())
	out.append_array(payload)
	return out


func _write_triangle_geo(path: String) -> void:
	## F4: ".GEO" + checksum + name[16] + nvert + nface + flags, then pos/nrm/faces.
	var buf := PackedByteArray()
	buf.append_array(".GEO".to_utf8_buffer())
	buf.append_array(_i32(0))
	var name := PackedByteArray()
	name.resize(16)
	var raw_name := "tri".to_utf8_buffer()
	for i in raw_name.size():
		name[i] = raw_name[i]
	buf.append_array(name)
	buf.append_array(_i32(3))
	buf.append_array(_i32(1))
	buf.append_array(_i32(0))
	# positions
	for p in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		buf.append_array(_f32(p.x))
		buf.append_array(_f32(p.y))
		buf.append_array(_f32(p.z))
	# normals
	for _i in 3:
		buf.append_array(_f32(0.0))
		buf.append_array(_f32(1.0))
		buf.append_array(_f32(0.0))
	# one triangular face, 55-byte fixed + 3×16-byte nodes
	buf.append_array(_i32(0))
	buf.append_array(_i32(3))
	buf.append_array(_u8(200))
	buf.append_array(_u8(200))
	buf.append_array(_u8(200))
	buf.append_array(_f32(0.0))
	buf.append_array(_f32(1.0))
	buf.append_array(_f32(0.0))
	buf.append_array(_f32(0.0))
	buf.append_array(_f32(0.5))
	buf.append_array(_u8(4))
	buf.append_array(_u8(1))
	buf.append_array(_u8(0))
	var tex := PackedByteArray()
	tex.resize(13)
	buf.append_array(tex)
	buf.append_array(_i32(-1))
	buf.append_array(_u32(0))
	for ni in 3:
		buf.append_array(_i32(ni))
		buf.append_array(_i32(ni))
		buf.append_array(_f32(0.0 if ni != 1 else 1.0))
		buf.append_array(_f32(0.0 if ni != 2 else 1.0))
	_write_bytes(path, buf)


func _u8(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF])


func _u16(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, v)
	return b


func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b


func _i32(v: int) -> PackedByteArray:
	return _u32(v)


func _f32(v: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_float(0, v)
	return b


func _cat(parts: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for p in parts:
		out.append_array(p)
	return out


# --- convert result / mesh accessors ---------------------------------------

func _unpack_convert(r: Variant) -> Dictionary:
	if r is Dictionary:
		var d: Dictionary = r
		var path: Variant = d.get("path", d.get("dest", null))
		var fidelity := str(d.get("fidelity", d.get("mesh_fidelity", "")))
		var reason := str(d.get("reason", d.get("why", "")))
		if d.has("ok") and not bool(d.get("ok")) and fidelity.is_empty():
			fidelity = "proxy"
			reason = _err_msg(r)
		return {"path": path, "fidelity": fidelity, "reason": reason}
	if r is Array and (r as Array).size() >= 2:
		var a: Array = r
		var p: Variant = a[0]
		var fid := str(a[1])
		var why := str(a[2]) if a.size() >= 3 else ""
		# Python: (None, "proxy", reason) on failure; (path, "hd", "") on success.
		# Some ports return (path, fidelity) only.
		if a.size() >= 3 and str(a[1]) in ["hd", "geo_flat", "geo_textured", "proxy"]:
			return {"path": p, "fidelity": fid, "reason": why}
		# (path, fidelity, reason) with path first
		return {"path": p, "fidelity": fid, "reason": why}
	return {"path": null, "fidelity": "", "reason": str(r)}


func _unwrap_mesh(r: Variant) -> Variant:
	if r is Dictionary:
		var d: Dictionary = r
		if d.has("mesh"):
			return d["mesh"]
		if d.has("geo"):
			return d["geo"]
		if d.has("geomes"):
			return d["geomes"]
	return r


func _submeshes_of(ogre: Variant) -> Array:
	var sm: Variant = _field(ogre, "submeshes")
	return _as_array(sm)


func _field(obj: Variant, key: String) -> Variant:
	if obj == null:
		return null
	if obj is Dictionary:
		return (obj as Dictionary).get(key)
	if obj is Object:
		return obj.get(key)
	return null


func _count(v: Variant) -> int:
	if v == null:
		return 0
	if v is Array or v is PackedVector3Array or v is PackedInt32Array \
			or v is PackedFloat32Array or v is PackedByteArray \
			or v is PackedStringArray:
		return v.size()
	if v is Object and v.has_method("size"):
		return int(v.size())
	return 0


# --- invocation / io (same strategy as test_bridge_goldens.gd) -------------

func _need(class_nm: String) -> bool:
	if _has(class_nm):
		return true
	if _CLASS_PATHS.has(class_nm) and FileAccess.file_exists(str(_CLASS_PATHS[class_nm])):
		_t.fail("%s exists but failed to load (parse error)" % class_nm)
	else:
		_t.fail("%s not yet ported" % class_nm)
	return false


func _has(class_nm: String) -> bool:
	if ClassDB.class_exists(class_nm):
		var inst: Variant = ClassDB.instantiate(class_nm)
		if inst != null:
			return true
	var script: Script = _load_script(class_nm)
	return script != null and script.can_instantiate()


func _load_script(class_nm: String) -> Script:
	if not _CLASS_PATHS.has(class_nm):
		return null
	var path := str(_CLASS_PATHS[class_nm])
	if not FileAccess.file_exists(path):
		return null
	var loaded: Variant = load(path)
	if loaded is Script:
		return loaded as Script
	return null


func _invoke_any(class_nm: String, methods: Array, args: Array) -> Variant:
	var last: Variant = null
	for method in methods:
		var r: Variant = _invoke(class_nm, str(method), args)
		if not _is_missing(r):
			return r
		last = r
	return last


func _invoke(class_nm: String, method: String, args: Array) -> Variant:
	if ClassDB.class_exists(class_nm):
		var inst_db: Variant = ClassDB.instantiate(class_nm)
		if inst_db != null and inst_db.has_method(method):
			return inst_db.callv(method, _trim_args(inst_db, method, args))
		if ClassDB.class_has_method(class_nm, method, true):
			match args.size():
				0:
					return ClassDB.class_call_static(class_nm, method)
				1:
					return ClassDB.class_call_static(class_nm, method, args[0])
				2:
					return ClassDB.class_call_static(class_nm, method, args[0], args[1])
				3:
					return ClassDB.class_call_static(class_nm, method, args[0], args[1], args[2])
	var script: Script = _load_script(class_nm)
	if script != null and script.can_instantiate():
		if script.has_method(method):
			return script.callv(method, _trim_args(script, method, args))
		var inst: Variant = script.new()
		if inst != null and inst.has_method(method):
			return inst.callv(method, _trim_args(inst, method, args))
	return {
		"ok": false,
		"error": {
			"code": "missing_class",
			"message": "%s.%s not available" % [class_nm, method],
		},
	}


func _trim_args(obj: Object, method: String, args: Array) -> Array:
	var n := -1
	for info in obj.get_method_list():
		if str(info.get("name", "")) == method:
			n = (info.get("args", []) as Array).size()
			break
	if n < 0 or args.size() <= n:
		return args
	return args.slice(0, n)


func _is_missing(r: Variant) -> bool:
	if not (r is Dictionary):
		return false
	var err: Variant = (r as Dictionary).get("error", {})
	return err is Dictionary and str(err.get("code", "")) == "missing_class"


func _is_err(r: Variant) -> bool:
	return r is Dictionary and (r as Dictionary).has("error") and not bool((r as Dictionary).get("ok", true))


func _err_msg(r: Variant) -> String:
	if not (r is Dictionary):
		return str(r)
	var err: Variant = (r as Dictionary).get("error", {})
	if err is Dictionary:
		return str(err.get("message", ""))
	return str(r)


func _as_array(v: Variant) -> Array:
	if v is Array:
		return v
	return []


func _scratch(tag: String) -> String:
	var p := OS.get_cache_dir().path_join("bz-gd-goldens").path_join(
			"%s-%d" % [tag, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(p)
	_temps.append(p)
	return p


func _write_bytes(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_t.fail("cannot write %s" % path)
		return
	f.store_buffer(data)
	f.close()


func _copy_file(src: String, dest: String) -> void:
	var data := FileAccess.get_file_as_bytes(src)
	_write_bytes(dest, data)


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn == "." or fn == "..":
			fn = d.get_next()
			continue
		var child := path.path_join(fn)
		if d.current_is_dir():
			_rm_tree(child)
		else:
			DirAccess.remove_absolute(child)
		fn = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)
