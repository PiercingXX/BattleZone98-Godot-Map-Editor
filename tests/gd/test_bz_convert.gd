extends RefCounted
## BzConvert: casefold/resolve/material parse + geo/proxy convert paths.
## Mesh/geo binaries are built in-test (those suffixes are gitignored).


func run(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz_convert_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)

	_test_index_resolve_material(t, tmp)
	_test_convert_proxy_and_geo(t, tmp)

	_rm_rf(tmp)


func _test_index_resolve_material(t, tmp: String) -> void:
	var root: String = tmp.path_join("assets")
	var sub: String = root.path_join("sub")
	DirAccess.make_dir_recursive_absolute(sub)
	_write_bytes(root.path_join("Foo.MESH"), PackedByteArray([1]))
	_write_bytes(root.path_join("Baz.PNG"), PackedByteArray([2]))
	_write_text(sub.path_join("bar.material"), "set_texture_alias DiffuseMap \"tex_d.png\"\n")
	_write_text(sub.path_join("tex2.material"), "texture \"hello.dds\"\n")
	_write_text(sub.path_join("plain.material"), "ambient 1 1 1\n")

	var idx: Dictionary = BzConvert.casefold_index([root, tmp.path_join("missing")])
	t.ok(idx.has("foo.mesh"), "casefold filename key")
	t.ok(idx.has("bar.material"))
	t.ok(idx.has("baz.png"))
	t.eq(str(idx["foo.mesh"]).get_file(), "Foo.MESH")

	t.eq(str(BzConvert.resolve(idx, "foo", [".mesh"])).get_file(), "Foo.MESH")
	t.eq(str(BzConvert.resolve(idx, "FOO.MESH", [".mesh"])).get_file(), "Foo.MESH")
	t.eq(BzConvert.resolve(idx, "nope", [".mesh"]), null)

	t.eq(BzConvert.parse_material_diffuse(sub.path_join("bar.material")), "tex_d.png")
	t.eq(BzConvert.parse_material_diffuse(sub.path_join("tex2.material")), "hello.dds")
	t.eq(BzConvert.parse_material_diffuse(sub.path_join("plain.material")), null)
	t.eq(BzConvert.parse_material_diffuse(tmp.path_join("nope.material")), null)


func _test_convert_proxy_and_geo(t, tmp: String) -> void:
	var dest: String = tmp.path_join("out").path_join("unknown.glb")
	var proxy: Array = BzConvert.convert_class("unknown", [tmp.path_join("empty")], dest)
	t.eq(proxy[0], null, "no assets → no glb")
	t.eq(proxy[1], "proxy")
	t.ok(str(proxy[2]).contains("no .mesh"), "hd reason")
	t.ok(str(proxy[2]).contains("no sdf/vdf/geo"), "geo reason")
	t.ok(DirAccess.dir_exists_absolute(dest.get_base_dir()), "dest parent created")

	var assets: String = tmp.path_join("geo_root")
	DirAccess.make_dir_recursive_absolute(assets)
	_write_bytes(assets.path_join("tri.geo"), _triangle_geo())
	var geo_dest: String = tmp.path_join("out").path_join("tri.glb")
	var geo: Array = BzConvert.convert_geo_file(assets.path_join("tri.geo"), {}, geo_dest)
	t.ok(geo[0] != null, "convert_geo_file wrote a path")
	t.eq(geo[1], "geo_flat")
	t.ok(FileAccess.file_exists(geo_dest))
	var magic: PackedByteArray = FileAccess.get_file_as_bytes(geo_dest).slice(0, 4)
	t.eq(magic.get_string_from_ascii(), "glTF")

	var via_class: Array = BzConvert.convert_class("tri", [assets], tmp.path_join("out").path_join("tri2.glb"))
	t.ok(via_class[0] != null, "convert_class finds standalone geo")
	t.eq(via_class[1], "geo_flat")
	t.eq(via_class[2], "")

	var hd_miss: Array = BzConvert.convert_hd("tri", BzConvert.casefold_index([assets]), geo_dest)
	t.eq(hd_miss[0], null)
	t.eq(hd_miss[1], "no .mesh")

	var bwd_miss: Array = BzConvert.convert_bwd2("nope", {}, geo_dest)
	t.eq(bwd_miss[0], null)
	t.eq(bwd_miss[1], "no sdf/vdf/geo")


func _triangle_geo() -> PackedByteArray:
	var data := PackedByteArray()
	data.append_array(PackedByteArray([0x2E, 0x47, 0x45, 0x4F]))
	data.append_array(_s32(0))
	var name16 := PackedByteArray()
	name16.resize(16)
	name16[0] = 0x74
	name16[1] = 0x72
	name16[2] = 0x69
	data.append_array(name16)
	data.append_array(_s32(3))
	data.append_array(_s32(1))
	data.append_array(_s32(0))
	data.append_array(_f3(0, 0, 0))
	data.append_array(_f3(1, 0, 0))
	data.append_array(_f3(0, 1, 0))
	data.append_array(_f3(0, 0, 1))
	data.append_array(_f3(0, 0, 1))
	data.append_array(_f3(0, 0, 1))
	data.append_array(_pack_face(0, 3, 10, 20, 30, "", [
		[0, 0, 0.0, 0.0],
		[1, 1, 1.0, 0.0],
		[2, 2, 0.0, 1.0],
	]))
	return data


func _pack_face(index: int, node_count: int, cr: int, cg: int, cb: int, tex: String, nodes: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(_s32(index))
	b.append_array(_s32(node_count))
	b.append(cr)
	b.append(cg)
	b.append(cb)
	b.append_array(_f3(0, 0, 1))
	b.append_array(_f32(0.0))
	b.append_array(_f32(0.0))
	b.append(4)
	b.append(1)
	b.append(0)
	var tex13 := PackedByteArray()
	tex13.resize(13)
	var tb: PackedByteArray = tex.to_ascii_buffer()
	for i in mini(tb.size(), 12):
		tex13[i] = tb[i]
	b.append_array(tex13)
	b.append_array(_s32(-1))
	b.append_array(_s32(0))
	for n in nodes:
		b.append_array(_s32(int(n[0])))
		b.append_array(_s32(int(n[1])))
		b.append_array(_f32(float(n[2])))
		b.append_array(_f32(float(n[3])))
	return b


func _s32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_s32(0, v)
	return b


func _f32(v: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_float(0, v)
	return b


func _f3(x: float, y: float, z: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(12)
	b.encode_float(0, x)
	b.encode_float(4, y)
	b.encode_float(8, z)
	return b


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


func _write_bytes(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(data)
	file.close()


func _rm_rf(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.include_hidden = true
	da.include_navigational = false
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		var child: String = path.path_join(fn)
		if da.current_is_dir():
			_rm_rf(child)
		else:
			DirAccess.remove_absolute(child)
		fn = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)
