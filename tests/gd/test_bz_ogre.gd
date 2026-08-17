extends RefCounted
## Synthetic OGRE .mesh tests. Goldens were written with formats/mesh.py
## write_mesh (no PIL) and checked with formats/ogre.py read_ogre_mesh.
## Extra shared-geometry / 32-bit-index files were hand-packed per F7 and
## confirmed by the same Python reader.


func run(t) -> void:
	var dir := _tmp_dir()
	_test_python_write_mesh_golden(t, dir)
	_test_shared_geometry(t, dir)
	_test_idx32_and_defaults(t, dir)
	_test_write_parse_roundtrip(t, dir)
	_test_skips_unknown_and_errors(t, dir)


func _test_python_write_mesh_golden(t, dir: String) -> void:
	var path := dir.path_join("tri.mesh")
	_write(path, _tri_mesh_bytes())
	var r: Dictionary = BzOgre.read_ogre_mesh(path)
	t.ok(bool(r.get("ok", false)), "read write_mesh golden")
	var mesh: BzOgre.OgreMesh = r["mesh"]
	t.eq(mesh.version, "[MeshSerializer_v1.100]")
	t.eq(mesh.submeshes.size(), 1)
	var sm: BzOgre.OgreSubmesh = mesh.submeshes[0]
	t.eq(sm.material, "TestMat")
	t.eq(sm.indices, [0, 1, 2])
	t.eq(sm.positions.size(), 3)
	t.ok(sm.positions[0].is_equal_approx(Vector3(0, 0, 0)), "p0")
	t.ok(sm.positions[1].is_equal_approx(Vector3(1, 0, 0)), "p1")
	t.ok(sm.positions[2].is_equal_approx(Vector3(0, 1, 0)), "p2")
	t.ok(sm.normals[0].is_equal_approx(Vector3(0, 0, 1)), "n0")
	t.ok(sm.uvs[1].is_equal_approx(Vector2(1, 0)), "uv1")
	t.ok(sm.uvs[2].is_equal_approx(Vector2(0, 1)), "uv2")


func _test_shared_geometry(t, dir: String) -> void:
	var path := dir.path_join("shared.mesh")
	_write(path, _shared_mesh_bytes())
	var r: Dictionary = BzOgre.read_ogre_mesh(path)
	t.ok(bool(r.get("ok", false)), "shared parse")
	var mesh: BzOgre.OgreMesh = r["mesh"]
	t.eq(mesh.submeshes.size(), 2)
	var a: BzOgre.OgreSubmesh = mesh.submeshes[0]
	var b: BzOgre.OgreSubmesh = mesh.submeshes[1]
	t.eq(a.material, "A")
	t.eq(b.material, "B")
	t.eq(a.indices, [0, 1, 2])
	t.eq(b.indices, [2, 1, 0])
	t.ok(a.positions[1].is_equal_approx(Vector3(1, 0, 0)))
	t.ok(b.positions[2].is_equal_approx(Vector3(0, 1, 0)))
	# No normals/uvs in the file → Python fills (0,1,0) and (0,0).
	t.ok(a.normals[0].is_equal_approx(Vector3(0, 1, 0)), "default normal")
	t.ok(a.uvs[0].is_equal_approx(Vector2(0, 0)), "default uv")
	t.eq(a.normals.size(), a.positions.size())
	t.eq(a.uvs.size(), a.positions.size())


func _test_idx32_and_defaults(t, dir: String) -> void:
	var path := dir.path_join("idx32.mesh")
	_write(path, _idx32_mesh_bytes())
	var r: Dictionary = BzOgre.read_ogre_mesh(path)
	t.ok(bool(r.get("ok", false)), "idx32 parse")
	var mesh: BzOgre.OgreMesh = r["mesh"]
	t.eq(mesh.version, "[MeshSerializer_v1.41]")
	t.eq(mesh.submeshes.size(), 1)
	var sm: BzOgre.OgreSubmesh = mesh.submeshes[0]
	t.eq(sm.material, "I32")
	t.eq(sm.indices, [0, 1, 2])
	t.ok(sm.positions[0].is_equal_approx(Vector3(0, 0, 0)))
	t.ok(sm.normals[0].is_equal_approx(Vector3(0, 1, 0)))


func _test_write_parse_roundtrip(t, dir: String) -> void:
	# Reconstruct the mesh.py write_mesh layout in GDScript, parse it,
	# and confirm it matches the Python golden bytes and decoded mesh.
	var verts := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
	var norms := [Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]
	var packed := _write_mesh_like_python(verts, norms, uvs, [0, 1, 2], "TestMat")
	t.eq(packed, _tri_mesh_bytes(), "GDScript packer matches mesh.py bytes")
	var path := dir.path_join("rt.mesh")
	_write(path, packed)
	var r: Dictionary = BzOgre.read_ogre_mesh(path)
	t.ok(bool(r.get("ok", false)), "round-trip parse")
	var sm: BzOgre.OgreSubmesh = (r["mesh"] as BzOgre.OgreMesh).submeshes[0]
	t.eq(sm.material, "TestMat")
	t.eq(sm.indices, [0, 1, 2])
	t.ok(sm.positions[2].is_equal_approx(Vector3(0, 1, 0)))
	t.ok(sm.normals[1].is_equal_approx(Vector3(0, 0, 1)))
	t.ok(sm.uvs[1].is_equal_approx(Vector2(1, 0)))


func _test_skips_unknown_and_errors(t, dir: String) -> void:
	var missing: Dictionary = BzOgre.read_ogre_mesh(dir.path_join("nope.mesh"))
	t.eq(missing.get("ok"), false, "missing file")
	var short_path := dir.path_join("short.mesh")
	_write(short_path, PackedByteArray([0, 1, 2]))
	var short_r: Dictionary = BzOgre.read_ogre_mesh(short_path)
	t.eq(short_r.get("ok"), false, "too short")
	# Top-level unknown chunk is skipped; a following MESH is still read.
	var golden := _tri_mesh_bytes()
	var ver := "[MeshSerializer_v1.100]\n"
	var mesh_body := golden.slice(2 + ver.length())
	var composed := PackedByteArray()
	composed.append_array(_u16(0x1000))
	composed.append_array(ver.to_utf8_buffer())
	composed.append_array(_u16(0xE000))
	composed.append_array(_u32(10))
	composed.append_array(PackedByteArray([1, 2, 3, 4]))
	composed.append_array(mesh_body)
	var skip_path := dir.path_join("skip.mesh")
	_write(skip_path, composed)
	var skip_r: Dictionary = BzOgre.read_ogre_mesh(skip_path)
	t.ok(bool(skip_r.get("ok", false)), "skips unknown top-level chunk")
	t.eq((skip_r["mesh"] as BzOgre.OgreMesh).submeshes.size(), 1)
	t.eq((skip_r["mesh"] as BzOgre.OgreMesh).submeshes[0].material, "TestMat")


func _write_mesh_like_python(
	verts: Array,
	norms: Array,
	uvs: Array,
	indices: Array,
	material_name: String
) -> PackedByteArray:
	# Mirror formats/mesh.py write_mesh — used only to prove the reader
	# accepts the same bytes the Python writer emits.
	var n: int = verts.size()
	var vbuf := PackedByteArray()
	var minv := Vector3(INF, INF, INF)
	var maxv := Vector3(-INF, -INF, -INF)
	for i in n:
		var p: Vector3 = verts[i]
		var nm: Vector3 = norms[i]
		var uv: Vector2 = uvs[i]
		var rec := PackedByteArray()
		rec.resize(32)
		rec.encode_float(0, p.x)
		rec.encode_float(4, p.y)
		rec.encode_float(8, p.z)
		rec.encode_float(12, nm.x)
		rec.encode_float(16, nm.y)
		rec.encode_float(20, nm.z)
		rec.encode_float(24, uv.x)
		rec.encode_float(28, uv.y)
		vbuf.append_array(rec)
		minv.x = minf(minv.x, p.x)
		minv.y = minf(minv.y, p.y)
		minv.z = minf(minv.z, p.z)
		maxv.x = maxf(maxv.x, p.x)
		maxv.y = maxf(maxv.y, p.y)
		maxv.z = maxf(maxv.z, p.z)
	var decl := PackedByteArray()
	for pair in [[2, 1, 0], [2, 4, 12], [1, 7, 24]]:
		var body := PackedByteArray()
		body.resize(10)
		body.encode_u16(0, 0)
		body.encode_u16(2, int(pair[0]))
		body.encode_u16(4, int(pair[1]))
		body.encode_u16(6, int(pair[2]))
		body.encode_u16(8, 0)
		decl.append_array(_chunk(0x5110, body))
	var decl_chunk := _chunk(0x5100, decl)
	var vdata := _chunk(0x5210, vbuf)
	var vhead := PackedByteArray()
	vhead.resize(4)
	vhead.encode_u16(0, 0)
	vhead.encode_u16(2, 32)
	vhead.append_array(vdata)
	var vbuf_chunk := _chunk(0x5200, vhead)
	var geom_body := _u32(n)
	geom_body.append_array(decl_chunk)
	geom_body.append_array(vbuf_chunk)
	var geometry := _chunk(0x5000, geom_body)
	var ib := PackedByteArray()
	ib.resize(indices.size() * 2)
	for i in indices.size():
		ib.encode_u16(i * 2, int(indices[i]))
	var sm_body := material_name.to_ascii_buffer()
	sm_body.append(0x0A)
	sm_body.append(0)
	sm_body.append_array(_u32(indices.size()))
	sm_body.append(0)
	sm_body.append_array(ib)
	sm_body.append_array(geometry)
	var submesh := _chunk(0x4000, sm_body)
	var dx: float = maxv.x - minv.x
	var dy: float = maxv.y - minv.y
	var dz: float = maxv.z - minv.z
	var radius: float = maxf(sqrt(dx * dx + dy * dy + dz * dz) / 2.0, 1.0)
	var bbody := PackedByteArray()
	bbody.resize(28)
	bbody.encode_float(0, minv.x)
	bbody.encode_float(4, minv.y)
	bbody.encode_float(8, minv.z)
	bbody.encode_float(12, maxv.x)
	bbody.encode_float(16, maxv.y)
	bbody.encode_float(20, maxv.z)
	bbody.encode_float(24, radius)
	var bounds := _chunk(0x9000, bbody)
	var mesh_body := PackedByteArray([0])
	mesh_body.append_array(submesh)
	mesh_body.append_array(bounds)
	var mesh := _chunk(0x3000, mesh_body)
	var out := _u16(0x1000)
	out.append_array("[MeshSerializer_v1.100]\n".to_utf8_buffer())
	out.append_array(mesh)
	return out


func _chunk(cid: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(6)
	out.encode_u16(0, cid)
	out.encode_u32(2, body.size() + 6)
	out.append_array(body)
	return out


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


func _tri_mesh_bytes() -> PackedByteArray:
	return (
		"00105b4d65736853657269616c697a65725f76312e3130305d0a0030f3000000"
		+ "000040ca000000546573744d61740a0003000000000000010002000050b00000"
		+ "0003000000005136000000105110000000000002000100000000001051100000"
		+ "000000020004000c000000105110000000000001000700180000000052700000"
		+ "0000002000105266000000000000000000000000000000000000000000000000"
		+ "00803f00000000000000000000803f0000000000000000000000000000000000"
		+ "00803f0000803f00000000000000000000803f00000000000000000000000000"
		+ "00803f000000000000803f009022000000000000000000000000000000000080"
		+ "3f0000803f000000000000803f"
	).hex_decode()


func _shared_mesh_bytes() -> PackedByteArray:
	return (
		"00105b4d65736853657269616c697a65725f76312e3130305d0a0030ba00000000"
		+ "005054000000030000000051160000001051100000000000020001000000000000"
		+ "523400000000000c0010522a0000000000000000000000000000000000803f0000"
		+ "000000000000000000000000803f00000000004014000000410a01030000000000"
		+ "0001000200004014000000420a0103000000000200010000000090220000000000"
		+ "000000000000000000000000803f0000803f000000000000803f00601500000064"
		+ "756d6d792e736b656c65746f6e0a"
	).hex_decode()


func _idx32_mesh_bytes() -> PackedByteArray:
	return (
		"00105b4d65736853657269616c697a65725f76312e34315d0a0030770000000100"
		+ "40700000004933320a000300000001000000000100000002000000005054000000"
		+ "030000000051160000001051100000000000020001000000000000523400000000"
		+ "000c0010522a0000000000000000000000000000000000803f0000000000000000"
		+ "000000000000803f00000000"
	).hex_decode()


func _tmp_dir() -> String:
	var dir := OS.get_temp_dir().path_join("bz_test_ogre")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _write(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
