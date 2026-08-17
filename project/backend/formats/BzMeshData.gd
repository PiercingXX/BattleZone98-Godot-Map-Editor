extends RefCounted
class_name BzMeshData
## OGRE `.mesh` binary writer — `MeshSerializer_v1.100` (the BZ98R dialect).
## Port of `bzmap.formats.mesh`. Writer only; there is no reader in the Python.

const _VERSION := "[MeshSerializer_v1.100]\n"

const _H_HEADER := 0x1000
const _M_MESH := 0x3000
const _M_SUBMESH := 0x4000
const _M_GEOMETRY := 0x5000
const _M_GEOM_VERTEX_DECL := 0x5100
const _M_GEOM_VERTEX_ELEMENT := 0x5110
const _M_GEOM_VERTEX_BUFFER := 0x5200
const _M_GEOM_VERTEX_BUFFER_DATA := 0x5210
const _M_MESH_BOUNDS := 0x9000

const _VET_FLOAT2 := 1
const _VET_FLOAT3 := 2
const _VES_POSITION := 1
const _VES_NORMAL := 4
const _VES_TEXCOORD := 7


static func write_mesh(
	path: String,
	vertices: Array,
	normals: Array,
	uvs: Array,
	indices: Array,
	material_name: String
) -> String:
	## Write a single-submesh OGRE mesh. `vertices`/`normals` are sequences of
	## `(x, y, z)`; `uvs` of `(u, v)`; `indices` a flat sequence of 16-bit
	## triangle vertex indices. Returns `path` on success, empty string on error.
	var n: int = vertices.size()
	if normals.size() != n or uvs.size() != n:
		push_error("vertices, normals and uvs must be the same length")
		return ""
	var max_idx := 0
	if not indices.is_empty():
		max_idx = int(indices[0])
		for i in range(1, indices.size()):
			var iv: int = int(indices[i])
			if iv > max_idx:
				max_idx = iv
	if max_idx >= n:
		push_error("index out of range")
		return ""
	if n > 65535:
		push_error("%s vertices exceeds the 16-bit index limit; split the mesh" % n)
		return ""
	for i in indices.size():
		var iv2: int = int(indices[i])
		if iv2 < 0 or iv2 > 65535:
			push_error("index out of range")
			return ""

	# Interleaved vertex buffer: pos(3) + normal(3) + uv(2) = 32 bytes.
	var buf := PackedByteArray()
	buf.resize(n * 32)
	var minv := Vector3(INF, INF, INF)
	var maxv := Vector3(-INF, -INF, -INF)
	for i in n:
		var p := _as_vec3(vertices[i])
		var nor := _as_vec3(normals[i])
		var uv := _as_vec2(uvs[i])
		var o: int = i * 32
		buf.encode_float(o + 0, p.x)
		buf.encode_float(o + 4, p.y)
		buf.encode_float(o + 8, p.z)
		buf.encode_float(o + 12, nor.x)
		buf.encode_float(o + 16, nor.y)
		buf.encode_float(o + 20, nor.z)
		buf.encode_float(o + 24, uv.x)
		buf.encode_float(o + 28, uv.y)
		minv.x = minf(minv.x, p.x)
		minv.y = minf(minv.y, p.y)
		minv.z = minf(minv.z, p.z)
		maxv.x = maxf(maxv.x, p.x)
		maxv.y = maxf(maxv.y, p.y)
		maxv.z = maxf(maxv.z, p.z)

	var decl := PackedByteArray()
	for spec in [
		[_VET_FLOAT3, _VES_POSITION, 0],
		[_VET_FLOAT3, _VES_NORMAL, 12],
		[_VET_FLOAT2, _VES_TEXCOORD, 24],
	]:
		var elem := PackedByteArray()
		elem.resize(10)
		elem.encode_u16(0, 0)
		elem.encode_u16(2, int(spec[0]))
		elem.encode_u16(4, int(spec[1]))
		elem.encode_u16(6, int(spec[2]))
		elem.encode_u16(8, 0)
		decl.append_array(_chunk(_M_GEOM_VERTEX_ELEMENT, elem))
	var decl_chunk := _chunk(_M_GEOM_VERTEX_DECL, decl)

	var vbuf_head := PackedByteArray()
	vbuf_head.resize(4)
	vbuf_head.encode_u16(0, 0)
	vbuf_head.encode_u16(2, 32)
	vbuf_head.append_array(_chunk(_M_GEOM_VERTEX_BUFFER_DATA, buf))
	var vbuf := _chunk(_M_GEOM_VERTEX_BUFFER, vbuf_head)

	var geom_body := PackedByteArray()
	geom_body.resize(4)
	geom_body.encode_u32(0, n)
	geom_body.append_array(decl_chunk)
	geom_body.append_array(vbuf)
	var geometry := _chunk(_M_GEOMETRY, geom_body)

	var index_bytes := PackedByteArray()
	index_bytes.resize(indices.size() * 2)
	for i in indices.size():
		index_bytes.encode_u16(i * 2, int(indices[i]))

	var sub_body := material_name.to_ascii_buffer()
	sub_body.append(0x0A)
	var flags := PackedByteArray()
	flags.resize(6)
	flags.encode_u8(0, 0) # useSharedVertices = false
	flags.encode_u32(1, indices.size())
	flags.encode_u8(5, 0) # indexes32bit = false
	sub_body.append_array(flags)
	sub_body.append_array(index_bytes)
	sub_body.append_array(geometry)
	var submesh := _chunk(_M_SUBMESH, sub_body)

	var dx: float = maxv.x - minv.x
	var dy: float = maxv.y - minv.y
	var dz: float = maxv.z - minv.z
	# Python: max(AABB_diagonal / 2, 1.0). F7 §3 only names the field.
	var radius: float = maxf(sqrt(dx * dx + dy * dy + dz * dz) / 2.0, 1.0)
	var bounds_body := PackedByteArray()
	bounds_body.resize(28)
	bounds_body.encode_float(0, minv.x)
	bounds_body.encode_float(4, minv.y)
	bounds_body.encode_float(8, minv.z)
	bounds_body.encode_float(12, maxv.x)
	bounds_body.encode_float(16, maxv.y)
	bounds_body.encode_float(20, maxv.z)
	bounds_body.encode_float(24, radius)
	var bounds := _chunk(_M_MESH_BOUNDS, bounds_body)

	var mesh_body := PackedByteArray()
	mesh_body.append(0) # skeletallyAnimated = false
	mesh_body.append_array(submesh)
	mesh_body.append_array(bounds)
	var mesh := _chunk(_M_MESH, mesh_body)

	# F7 §2: the 0x1000 header has NO size field — just the id and the
	# newline-terminated version string.
	var header := PackedByteArray()
	header.resize(2)
	header.encode_u16(0, _H_HEADER)
	header.append_array(_VERSION.to_utf8_buffer())
	header.append_array(mesh)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("%s: cannot open for write (%s)" % [path, error_string(FileAccess.get_open_error())])
		return ""
	file.store_buffer(header)
	return path


static func _chunk(cid: int, body: PackedByteArray) -> PackedByteArray:
	## Wrap `body` in a chunk header (size includes the 6-byte header).
	var out := PackedByteArray()
	out.resize(6)
	out.encode_u16(0, cid)
	out.encode_u32(2, body.size() + 6)
	out.append_array(body)
	return out


static func _as_vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array or v is PackedFloat32Array or v is PackedFloat64Array:
		var x := 0.0
		var y := 0.0
		var z := 0.0
		if v.size() > 0:
			x = float(v[0])
		if v.size() > 1:
			y = float(v[1])
		if v.size() > 2:
			z = float(v[2])
		return Vector3(x, y, z)
	return Vector3.ZERO


static func _as_vec2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Array or v is PackedFloat32Array or v is PackedFloat64Array:
		var u := 0.0
		var w := 0.0
		if v.size() > 0:
			u = float(v[0])
		if v.size() > 1:
			w = float(v[1])
		return Vector2(u, w)
	return Vector2.ZERO
