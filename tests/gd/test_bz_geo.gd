extends RefCounted
## BzGeo — parse / primitives / write→parse.
## Synthetic bytes are hand-packed here (same struct layouts as bzmap.formats.geo).
## `*.geo` is gitignored, so fixtures are not loaded from disk.


func run(t) -> void:
	_parse_synthetic(t)
	_oeg_magic(t)
	_uv_split(t)
	_bad_index_skipped(t)
	_errors(t)
	_write_parse_roundtrip(t)
	_primitives_default_normal_and_degenerate(t)


func _parse_synthetic(t) -> void:
	var mesh = BzGeo.read_geo(_write_tmp("synthetic.geo", _synthetic_geo(false)))
	t.ok(mesh != null, "synthetic.geo parses")
	if mesh == null:
		return
	# name field is b"tri\xe9..." — non-ASCII 0xE9 discarded (F8 §6 / Python ascii ignore)
	t.eq(mesh.name, "tri", "non-ASCII dropped from name")
	t.eq(mesh.flags, 0xABCD)
	t.eq(mesh.checksum, 0x12345678)
	t.eq(mesh.positions.size(), 4)
	t.eq(mesh.normals.size(), 4)
	# 3 faces on disk; node_count=2 face is dropped (Python: if node_count >= 3)
	t.eq(mesh.faces.size(), 2, "degenerate 2-node face skipped")
	_v3(t, mesh.positions[0], 0.0, 0.0, 0.0, "pos0")
	_v3(t, mesh.positions[2], 1.0, 1.0, 0.0, "pos2")
	_v3(t, mesh.normals[3], 0.0, 1.0, 0.0, "nrm3")

	var f0 = mesh.faces[0]
	t.eq(f0.colour, [10, 20, 30])
	t.eq(f0.texture_name, "Rock")
	t.eq(f0.nodes.size(), 3)
	# stored v=0.25 → parsed 0.75; stored v=0.75 → parsed 0.25 (F4 §5)
	_node(t, f0.nodes[0], 0, 0, 0.0, 0.75, "f0n0")
	_node(t, f0.nodes[1], 1, 1, 1.0, 0.75, "f0n1")
	_node(t, f0.nodes[2], 2, 2, 1.0, 0.25, "f0n2")

	var f1 = mesh.faces[1]
	t.eq(f1.colour, [255, 128, 0])
	t.eq(f1.texture_name, "")
	t.eq(f1.nodes.size(), 4, "n-gon face kept")
	_node(t, f1.nodes[0], 0, 0, 0.0, 1.0, "f1n0")
	_node(t, f1.nodes[3], 3, 3, 0.0, 0.0, "f1n3")

	var prims: Array = BzGeo.geo_to_primitives(mesh)
	t.eq(prims.size(), 2, "two material groups")
	t.eq(prims[0]["texture"], "Rock")
	t.eq(prims[0]["colour"], [10, 20, 30])
	t.eq(prims[0]["verts"].size(), 3)
	t.eq(prims[0]["indices"], [0, 1, 2])
	_v2(t, prims[0]["uvs"][0], 0.0, 0.75, "rock uv0")
	t.eq(prims[1]["texture"], "")
	t.eq(prims[1]["colour"], [255, 128, 0])
	t.eq(prims[1]["verts"].size(), 4)
	t.eq(prims[1]["indices"], [0, 1, 2, 0, 2, 3], "quad fans to 2 tris")
	_v3(t, prims[1]["norms"][3], 0.0, 1.0, 0.0, "quad nrm3")


func _oeg_magic(t) -> void:
	var mesh = BzGeo.read_geo(_write_tmp("oeg.geo", _synthetic_geo(true)))
	t.ok(mesh != null, "OEG. magic accepted (Python extra vs F4)")
	if mesh != null:
		t.eq(mesh.name, "tri")
		t.eq(mesh.faces.size(), 2)


func _uv_split(t) -> void:
	var data := PackedByteArray()
	data.append_array(_pack_header(_magic_geo(), 0, "uvsplit", 3, 2, 0))
	for p in [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]]:
		data.append_array(_f3(p[0], p[1], p[2]))
	for _i in 3:
		data.append_array(_f3(0.0, 0.0, 1.0))
	data.append_array(_pack_face(0, 3, 255, 255, 255, "atlas", [
		[0, 0, 0.0, 0.0], [1, 1, 1.0, 0.0], [2, 2, 0.0, 1.0],
	]))
	data.append_array(_pack_face(1, 3, 255, 255, 255, "atlas", [
		[0, 0, 0.0, 1.0], [1, 1, 1.0, 1.0], [2, 2, 0.0, 0.0],
	]))
	var mesh = BzGeo.read_geo(_write_tmp("uv_split.geo", data))
	t.ok(mesh != null, "uv_split.geo parses")
	if mesh == null:
		return
	var prims: Array = BzGeo.geo_to_primitives(mesh)
	t.eq(prims.size(), 1)
	# two faces share 3 positions but disagree on UV → 6 unique verts
	t.eq(prims[0]["verts"].size(), 6, "split on (pos, nrm, uv)")
	t.eq(prims[0]["indices"], [0, 1, 2, 3, 4, 5])
	_v2(t, prims[0]["uvs"][0], 0.0, 1.0, "split uv0")
	_v2(t, prims[0]["uvs"][3], 0.0, 0.0, "split uv3")


func _bad_index_skipped(t) -> void:
	var data := PackedByteArray()
	data.append_array(_pack_header(_magic_geo(), 0, "badidx", 1, 1, 0))
	data.append_array(_f3(0, 0, 0))
	data.append_array(_f3(0, 1, 0))
	data.append_array(_pack_face(0, 3, 1, 1, 1, "x", [
		[5, 0, 0.0, 0.0], [0, 0, 1.0, 0.0], [0, 0, 0.0, 1.0],
	]))
	var mesh = BzGeo.read_geo(_write_tmp("bad_index.geo", data))
	t.ok(mesh != null)
	if mesh == null:
		return
	t.eq(mesh.faces.size(), 1, "face record is kept")
	t.eq(BzGeo.geo_to_primitives(mesh).size(), 0, "bad pos index drops the face")


func _errors(t) -> void:
	var short := PackedByteArray()
	short.append_array(_magic_geo())
	short.resize(14)
	t.eq(BzGeo.read_geo(_write_tmp("short.geo", short)), null, "short header")

	var bad := _pack_header(PackedByteArray([0x4E, 0x4F, 0x50, 0x45]), 0, "x", 0, 0, 0)
	t.eq(BzGeo.read_geo(_write_tmp("bad_magic.geo", bad)), null, "bad magic")
	t.eq(BzGeo.read_geo(OS.get_temp_dir().path_join("bzgeo_missing_no_such.geo")), null, "missing file")

	var neg := _pack_header(_magic_geo(), 0, "neg", -1, 0, 0)
	t.eq(BzGeo.read_geo(_write_tmp("neg.geo", neg)), null, "negative vertex count")

	var hdr := _pack_header(_magic_geo(), 0, "truncv", 2, 0, 0)
	t.eq(BzGeo.read_geo(_write_tmp("trunc_verts.geo", hdr)), null, "truncated vertex data")

	var one_vert := _pack_header(_magic_geo(), 0, "truncf", 1, 1, 0)
	one_vert.append_array(_f3(0, 0, 0))
	one_vert.append_array(_f3(0, 1, 0))
	t.eq(BzGeo.read_geo(_write_tmp("trunc_face.geo", one_vert)), null, "truncated face")


func _write_parse_roundtrip(t) -> void:
	# Hand-pack a 3-vert, 1-face mesh (no module writer — geo.py is read-only).
	var data := PackedByteArray()
	data.append_array(_pack_header(_magic_geo(), 42, "round", 3, 1, 7))
	data.append_array(_f3(0, 0, 0))
	data.append_array(_f3(2, 0, 0))
	data.append_array(_f3(0, 2, 0))
	data.append_array(_f3(0, 0, 1))
	data.append_array(_f3(0, 0, 1))
	data.append_array(_f3(0, 0, 1))
	data.append_array(_pack_face(0, 3, 1, 2, 3, "tex", [
		[0, 0, 0.0, 0.0],
		[1, 1, 1.0, 0.0],
		[2, 2, 0.0, 1.0],
	]))
	t.eq(data.size(), 36 + 24 * 3 + 55 + 16 * 3, "stride arithmetic")
	var mesh = BzGeo.read_geo(_write_tmp("roundtrip.geo", data))
	t.ok(mesh != null, "write→parse")
	if mesh == null:
		return
	t.eq(mesh.name, "round")
	t.eq(mesh.checksum, 42)
	t.eq(mesh.flags, 7)
	t.eq(mesh.faces.size(), 1)
	t.eq(mesh.faces[0].texture_name, "tex")
	t.eq(mesh.faces[0].colour, [1, 2, 3])
	_node(t, mesh.faces[0].nodes[0], 0, 0, 0.0, 1.0, "rt n0")
	_node(t, mesh.faces[0].nodes[2], 2, 2, 0.0, 0.0, "rt n2")
	var prims: Array = BzGeo.geo_to_primitives(mesh)
	t.eq(prims.size(), 1)
	t.eq(prims[0]["indices"], [0, 1, 2])


func _primitives_default_normal_and_degenerate(t) -> void:
	var data := PackedByteArray()
	data.append_array(_pack_header(_magic_geo(), 0, "degen", 2, 1, 0))
	data.append_array(_f3(0, 0, 0))
	data.append_array(_f3(1, 0, 0))
	data.append_array(_f3(0, 0, 1))
	data.append_array(_f3(0, 0, 1))
	data.append_array(_pack_face(0, 3, 9, 9, 9, "", [
		[0, 99, 0.0, 0.0],
		[0, 99, 0.0, 0.0],
		[1, 99, 1.0, 0.0],
	]))
	var mesh = BzGeo.read_geo(_write_tmp("degen.geo", data))
	t.ok(mesh != null)
	if mesh == null:
		return
	var prims: Array = BzGeo.geo_to_primitives(mesh)
	t.eq(prims.size(), 0, "degenerate fan produces no triangles")

	var data2 := PackedByteArray()
	data2.append_array(_pack_header(_magic_geo(), 0, "dnrm", 3, 1, 0))
	data2.append_array(_f3(0, 0, 0))
	data2.append_array(_f3(1, 0, 0))
	data2.append_array(_f3(0, 1, 0))
	data2.append_array(_f3(1, 0, 0))
	data2.append_array(_f3(1, 0, 0))
	data2.append_array(_f3(1, 0, 0))
	data2.append_array(_pack_face(0, 3, 4, 5, 6, "n", [
		[0, -1, 0.0, 0.0],
		[1, -1, 1.0, 0.0],
		[2, -1, 0.0, 1.0],
	]))
	var mesh2 = BzGeo.read_geo(_write_tmp("dnrm.geo", data2))
	var prims2: Array = BzGeo.geo_to_primitives(mesh2)
	t.eq(prims2.size(), 1)
	_v3(t, prims2[0]["norms"][0], 0.0, 1.0, 0.0, "default nrm")
	t.eq(prims2[0]["indices"], [0, 1, 2])


func _synthetic_geo(oeg: bool) -> PackedByteArray:
	var name16 := PackedByteArray()
	name16.resize(16)
	name16[0] = 0x74
	name16[1] = 0x72
	name16[2] = 0x69
	name16[3] = 0xE9
	var data := PackedByteArray()
	data.append_array(_magic_oeg() if oeg else _magic_geo())
	data.append_array(_s32(0x12345678))
	data.append_array(name16)
	data.append_array(_s32(4))
	data.append_array(_s32(3))
	data.append_array(_s32(0xABCD))
	for p in [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 1.0, 0.0], [0.0, 1.0, 0.0]]:
		data.append_array(_f3(p[0], p[1], p[2]))
	for n in [[0.0, 0.0, 1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 1.0], [0.0, 1.0, 0.0]]:
		data.append_array(_f3(n[0], n[1], n[2]))
	data.append_array(_pack_face(0, 3, 10, 20, 30, "Rock", [
		[0, 0, 0.0, 0.25], [1, 1, 1.0, 0.25], [2, 2, 1.0, 0.75],
	]))
	data.append_array(_pack_face(1, 4, 255, 128, 0, "", [
		[0, 0, 0.0, 0.0], [1, 1, 1.0, 0.0], [2, 2, 1.0, 1.0], [3, 3, 0.0, 1.0],
	]))
	data.append_array(_pack_face(2, 2, 1, 2, 3, "skipme", [
		[0, 0, 0.0, 0.0], [1, 1, 1.0, 0.0],
	]))
	return data


func _magic_geo() -> PackedByteArray:
	return PackedByteArray([0x2E, 0x47, 0x45, 0x4F])


func _magic_oeg() -> PackedByteArray:
	return PackedByteArray([0x4F, 0x45, 0x47, 0x2E])


func _pack_header(magic: PackedByteArray, checksum: int, name: String, nvert: int, nface: int, flags: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(magic)
	b.append_array(_s32(checksum))
	var nb := name.to_ascii_buffer()
	var name16 := PackedByteArray()
	name16.resize(16)
	for i in mini(16, nb.size()):
		name16[i] = nb[i]
	b.append_array(name16)
	b.append_array(_s32(nvert))
	b.append_array(_s32(nface))
	b.append_array(_s32(flags))
	return b


func _pack_face(idx: int, node_count: int, cr: int, cg: int, cb: int, tex: String, nodes: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(55)
	b.encode_s32(0, idx)
	b.encode_s32(4, node_count)
	b.encode_u8(8, cr)
	b.encode_u8(9, cg)
	b.encode_u8(10, cb)
	b.encode_float(11, 0.0)
	b.encode_float(15, 0.0)
	b.encode_float(19, 1.0)
	b.encode_float(23, 0.0)
	b.encode_float(27, 0.5)
	b.encode_u8(31, 4)
	b.encode_u8(32, 1)
	b.encode_u8(33, 0)
	var tb := tex.to_ascii_buffer()
	for i in mini(13, tb.size()):
		b[34 + i] = tb[i]
	b.encode_s32(47, -1)
	b.encode_u32(51, 0)
	for n in nodes:
		var node := PackedByteArray()
		node.resize(16)
		node.encode_s32(0, int(n[0]))
		node.encode_s32(4, int(n[1]))
		node.encode_float(8, float(n[2]))
		node.encode_float(12, float(n[3]))
		b.append_array(node)
	return b


func _s32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_s32(0, v)
	return b


func _f3(x: float, y: float, z: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(12)
	b.encode_float(0, x)
	b.encode_float(4, y)
	b.encode_float(8, z)
	return b


func _write_tmp(name: String, data: PackedByteArray) -> String:
	var path := OS.get_temp_dir().path_join("bzgeo_%s" % name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return path
	f.store_buffer(data)
	return path


func _v3(t, got: Vector3, x: float, y: float, z: float, msg: String) -> void:
	t.near(got.x, x, 0.0001, msg + ".x")
	t.near(got.y, y, 0.0001, msg + ".y")
	t.near(got.z, z, 0.0001, msg + ".z")


func _v2(t, got: Vector2, u: float, v: float, msg: String) -> void:
	t.near(got.x, u, 0.0001, msg + ".u")
	t.near(got.y, v, 0.0001, msg + ".v")


func _node(t, node: Array, pi: int, ni: int, u: float, v: float, msg: String) -> void:
	t.eq(int(node[0]), pi, msg + " pi")
	t.eq(int(node[1]), ni, msg + " ni")
	t.near(float(node[2]), u, 0.0001, msg + " u")
	t.near(float(node[3]), v, 0.0001, msg + " v")
