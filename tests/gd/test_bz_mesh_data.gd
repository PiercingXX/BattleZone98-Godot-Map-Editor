extends RefCounted
## BzMeshData — OGRE MeshSerializer_v1.100 writer.
## Hex goldens were produced by bzmap.formats.mesh (PYTHONPATH=backend python3).
## `*.mesh` is gitignored, so goldens are embedded rather than loaded from disk.


func run(t) -> void:
	_write_parse_triangle(t)
	_byte_identical_python(t)
	_no_index_mesh(t)
	_errors(t)
	_radius_floor(t)


func _write_parse_triangle(t) -> void:
	var path := OS.get_temp_dir().path_join("bzmesh_tri.mesh")
	var ret: String = BzMeshData.write_mesh(
		path,
		[[0.0, 0.0, 0.0], [2.0, 0.0, 0.0], [0.0, 3.0, 0.0]],
		[[0.0, 0.0, 1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 1.0]],
		[[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]],
		[0, 1, 2],
		"water"
	)
	t.eq(ret, path)
	var data := FileAccess.get_file_as_bytes(path)
	t.ok(data.size() > 26, "wrote a mesh")
	t.eq(data.decode_u16(0), 0x1000, "header id")
	var ver := data.slice(2, 26).get_string_from_ascii()
	t.eq(ver, "[MeshSerializer_v1.100]\n")
	t.eq(data.decode_u16(26), 0x3000, "M_MESH")
	t.eq(data.decode_u32(28), data.size() - 26, "mesh chunk closes the file")
	t.eq(data[32], 0, "not skeletally animated")
	t.eq(data.decode_u16(33), 0x4000, "M_SUBMESH")
	var nl := 39
	while nl < data.size() and data[nl] != 0x0A:
		nl += 1
	t.eq(data.slice(39, nl).get_string_from_ascii(), "water")
	var i: int = nl + 1
	t.eq(data[i], 0, "useSharedVertices")
	i += 1
	t.eq(data.decode_u32(i), 3, "indexCount")
	i += 4
	t.eq(data[i], 0, "indexes32bit")
	i += 1
	t.eq(data.decode_u16(i), 0)
	t.eq(data.decode_u16(i + 2), 1)
	t.eq(data.decode_u16(i + 4), 2)
	i += 6
	t.eq(data.decode_u16(i), 0x5000, "M_GEOMETRY")
	i += 6
	t.eq(data.decode_u32(i), 3, "vertexCount")
	i += 4
	t.eq(data.decode_u16(i), 0x5100, "vertex declaration")
	t.eq(data.decode_u32(i + 2), 54)
	i += 54
	t.eq(data.decode_u16(i), 0x5200, "vertex buffer")
	t.eq(data.decode_u16(i + 6), 0, "bindIndex")
	t.eq(data.decode_u16(i + 8), 32, "vertexSize")
	i += 10
	t.eq(data.decode_u16(i), 0x5210, "buffer data")
	t.eq(data.decode_u32(i + 2), 6 + 96, "data chunk size")
	i += 6
	t.near(data.decode_float(i + 0), 0.0, 0.0001)
	t.near(data.decode_float(i + 20), 1.0, 0.0001, "n.z of vert 0")
	t.near(data.decode_float(i + 32), 2.0, 0.0001, "x of vert 1")
	t.near(data.decode_float(i + 68), 3.0, 0.0001, "y of vert 2")
	var bo: int = data.size() - 34
	t.eq(data.decode_u16(bo), 0x9000)
	t.eq(data.decode_u32(bo + 2), 34)
	t.near(data.decode_float(bo + 6), 0.0, 0.0001, "minx")
	t.near(data.decode_float(bo + 18), 2.0, 0.0001, "maxx")
	t.near(data.decode_float(bo + 22), 3.0, 0.0001, "maxy")
	var want_r: float = sqrt(4.0 + 9.0) / 2.0
	t.near(data.decode_float(bo + 30), want_r, 0.0001, "radius")


func _byte_identical_python(t) -> void:
	var path := OS.get_temp_dir().path_join("bzmesh_golden.mesh")
	BzMeshData.write_mesh(
		path,
		[[0.0, 0.0, 0.0], [2.0, 0.0, 0.0], [0.0, 3.0, 0.0]],
		[[0.0, 0.0, 1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 1.0]],
		[[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]],
		[0, 1, 2],
		"water"
	)
	var got := FileAccess.get_file_as_bytes(path)
	var want := _TRIANGLE_HEX.hex_decode()
	t.eq(got.size(), want.size(), "golden size")
	t.eq(got, want, "write_mesh byte-identical to Python triangle.mesh")


func _no_index_mesh(t) -> void:
	var path := OS.get_temp_dir().path_join("bzmesh_noidx.mesh")
	var ret: String = BzMeshData.write_mesh(
		path,
		[[1.0, 2.0, 3.0]],
		[[0.0, 1.0, 0.0]],
		[[0.5, 0.5]],
		[],
		"plain"
	)
	t.eq(ret, path)
	var got := FileAccess.get_file_as_bytes(path)
	t.eq(got, _NO_INDEX_HEX.hex_decode(), "empty-index mesh matches Python")


func _errors(t) -> void:
	var path := OS.get_temp_dir().path_join("bzmesh_err.mesh")
	t.eq(BzMeshData.write_mesh(path, [[0, 0, 0]], [], [[0, 0]], [0], "m"), "", "length mismatch")
	t.eq(BzMeshData.write_mesh(path, [[0, 0, 0]], [[0, 1, 0]], [[0, 0]], [1], "m"), "", "index OOR")
	t.eq(BzMeshData.write_mesh(path, [], [], [], [], "m"), "", "n=0 empty indices (max default 0 >= 0)")
	var big_v: Array = []
	var big_n: Array = []
	var big_u: Array = []
	big_v.resize(65536)
	big_n.resize(65536)
	big_u.resize(65536)
	t.eq(BzMeshData.write_mesh(path, big_v, big_n, big_u, [], "m"), "", "16-bit vertex limit")


func _radius_floor(t) -> void:
	var path := OS.get_temp_dir().path_join("bzmesh_tiny.mesh")
	BzMeshData.write_mesh(
		path,
		[[0.0, 0.0, 0.0], [0.1, 0.0, 0.0], [0.0, 0.1, 0.0]],
		[[0.0, 0.0, 1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 1.0]],
		[[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]],
		[0, 1, 2],
		"t"
	)
	var data := FileAccess.get_file_as_bytes(path)
	var bo: int = data.size() - 34
	t.eq(data.decode_u16(bo), 0x9000)
	t.near(data.decode_float(bo + 30), 1.0, 0.0001, "radius floored at 1")


# Produced by: PYTHONPATH=backend python3 -c "from bzmap.formats.mesh import write_mesh; ..."
const _TRIANGLE_HEX := "00105b4d65736853657269616c697a65725f76312e3130305d0a0030f1000000000040c800000077617465720a0003000000000000010002000050b000000003000000005136000000105110000000000002000100000000001051100000000000020004000c000000105110000000000001000700180000000052700000000000200010526600000000000000000000000000000000000000000000000000803f000000000000000000000040000000000000000000000000000000000000803f0000803f0000000000000000000040400000000000000000000000000000803f000000000000803f0090220000000000000000000000000000000000004000004040000000005ac1e63f"
const _NO_INDEX_HEX := "00105b4d65736853657269616c697a65725f76312e3130305d0a0030ab00000000004082000000706c61696e0a00000000000000507000000001000000005136000000105110000000000002000100000000001051100000000000020004000c00000010511000000000000100070018000000005230000000000020001052260000000000803f0000004000004040000000000000803f000000000000003f0000003f0090220000000000803f00000040000040400000803f00000040000040400000803f"
