extends RefCounted
class_name BzOgre
## OGRE ``.mesh`` reader for MeshSerializer_v1.100 (docs/formats/F7).
## Port of formats/ogre.py.

const H_HEADER := 0x1000
const M_MESH := 0x3000
const M_SUBMESH := 0x4000
const M_SUBMESH_OP := 0x4010
const M_GEOMETRY := 0x5000
const M_GEOM_DECL := 0x5100
const M_GEOM_ELEM := 0x5110
const M_GEOM_VBUF := 0x5200
const M_GEOM_VDATA := 0x5210
const M_BOUNDS := 0x9000

const VES_POSITION := 1
const VES_NORMAL := 4
const VES_COLOUR := 5
const VES_TEXCOORD := 7


class OgreSubmesh extends RefCounted:
	var material: String = ""
	var positions: Array = []
	var normals: Array = []
	var uvs: Array = []
	var indices: Array = []


class OgreMesh extends RefCounted:
	var version: String = ""
	var submeshes: Array = []


class _Buf extends RefCounted:
	var data: PackedByteArray = PackedByteArray()
	var pos: int = 0
	var le: bool = true

	func remaining() -> int:
		return data.size() - pos

	func at_end() -> bool:
		return pos >= data.size()

	func u8() -> int:
		if pos >= data.size():
			pos += 1
			return 0
		var v: int = int(data[pos])
		pos += 1
		return v

	func u16() -> int:
		if remaining() < 2:
			pos += 2
			return 0
		var v: int
		if le:
			v = data.decode_u16(pos)
		else:
			v = (int(data[pos]) << 8) | int(data[pos + 1])
		pos += 2
		return v

	func u32() -> int:
		if remaining() < 4:
			pos += 4
			return 0
		var v: int
		if le:
			v = data.decode_u32(pos)
		else:
			v = (int(data[pos]) << 24) | (int(data[pos + 1]) << 16) \
					| (int(data[pos + 2]) << 8) | int(data[pos + 3])
		pos += 4
		return v

	func read_bytes(n: int) -> PackedByteArray:
		var end: int = mini(pos + n, data.size())
		var v := data.slice(pos, end)
		pos += n
		return v

	func read_string() -> String:
		var end: int = pos
		while end < data.size() and int(data[end]) != 0x0A:
			end += 1
		var found: bool = end < data.size()
		var s := BzOgre._ascii_ignore(data, pos, end)
		pos = end + 1 if found else end
		return s

	func peek_u16() -> Variant:
		if remaining() < 2:
			return null
		if le:
			return data.decode_u16(pos)
		return (int(data[pos]) << 8) | int(data[pos + 1])


static func read_ogre_mesh(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return BzErrors.err(
			"io",
			"%s: cannot read" % path,
			error_string(FileAccess.get_open_error())
		)
	var data: PackedByteArray = f.get_buffer(f.get_length())
	if data.size() < 4:
		return BzErrors.err("too_short", "%s: too short" % path, "Need at least the 2-byte header id.")
	var le: bool = int(data[0]) == 0x00 and int(data[1]) == 0x10
	if not le and not (int(data[0]) == 0x10 and int(data[1]) == 0x00):
		# Python: still try LE when the endian marker is unrecognized.
		le = true
	var buf := _Buf.new()
	buf.data = data
	buf.le = le
	var hid: int = buf.u16()
	if hid != H_HEADER and hid != 0x0010:
		# Python accepts either endian interpretation and continues anyway.
		pass
	var version: String = buf.read_string()
	var mesh := OgreMesh.new()
	mesh.version = version
	while not buf.at_end():
		var cid: Variant = buf.peek_u16()
		if cid == null:
			break
		if int(cid) == M_MESH:
			_read_mesh(buf, mesh)
		else:
			_skip_chunk(buf)
	return {"ok": true, "mesh": mesh}


static func _skip_chunk(buf: _Buf) -> void:
	if buf.remaining() < 6:
		buf.pos = buf.data.size()
		return
	buf.u16()
	var size: int = buf.u32()
	var body: int = maxi(size - 6, 0)
	buf.pos = mini(buf.data.size(), buf.pos + body)


static func _read_mesh(buf: _Buf, mesh: OgreMesh) -> void:
	var start: int = buf.pos
	buf.u16()
	var size: int = buf.u32()
	var end: int = start + size
	buf.u8()
	var shared: Variant = null
	while buf.pos < end:
		var cid: Variant = buf.peek_u16()
		if cid == null:
			break
		if int(cid) == M_SUBMESH:
			mesh.submeshes.append(_read_submesh(buf, shared))
		elif int(cid) == M_GEOMETRY:
			shared = _read_geometry(buf)
		elif int(cid) == M_BOUNDS:
			_skip_chunk(buf)
		else:
			_skip_chunk(buf)
	buf.pos = end


static func _read_submesh(buf: _Buf, shared: Variant) -> OgreSubmesh:
	var start: int = buf.pos
	buf.u16()
	var size: int = buf.u32()
	var end: int = start + size
	var material: String = buf.read_string()
	var use_shared: int = buf.u8()
	var index_count: int = buf.u32()
	var idx32: int = buf.u8()
	var ib_size: int = index_count * (4 if idx32 != 0 else 2)
	var raw: PackedByteArray = buf.read_bytes(ib_size)
	var indices: Array = []
	if idx32 != 0:
		for i in index_count:
			var off: int = i * 4
			if off + 4 > raw.size():
				break
			if buf.le:
				indices.append(raw.decode_u32(off))
			else:
				indices.append(
					(int(raw[off]) << 24) | (int(raw[off + 1]) << 16) \
					| (int(raw[off + 2]) << 8) | int(raw[off + 3])
				)
	else:
		for i in index_count:
			var off: int = i * 2
			if off + 2 > raw.size():
				break
			if buf.le:
				indices.append(raw.decode_u16(off))
			else:
				indices.append((int(raw[off]) << 8) | int(raw[off + 1]))
	var geom: Variant = shared if use_shared != 0 else null
	while buf.pos < end:
		var cid: Variant = buf.peek_u16()
		if cid == null:
			break
		if int(cid) == M_GEOMETRY:
			geom = _read_geometry(buf)
		else:
			_skip_chunk(buf)
	buf.pos = end
	var sm := OgreSubmesh.new()
	sm.material = material
	sm.indices = indices
	if geom != null and geom is Array:
		var g: Array = geom
		if g.size() >= 3:
			sm.positions = g[0]
			sm.normals = g[1]
			sm.uvs = g[2]
			if sm.normals.is_empty():
				for _i in sm.positions.size():
					sm.normals.append(Vector3(0.0, 1.0, 0.0))
			if sm.uvs.is_empty():
				for _i in sm.positions.size():
					sm.uvs.append(Vector2(0.0, 0.0))
	return sm


static func _read_geometry(buf: _Buf) -> Array:
	var start: int = buf.pos
	buf.u16()
	var size: int = buf.u32()
	var end: int = start + size
	var vcount: int = buf.u32()
	var elements: Array = []
	var buffers := {}
	while buf.pos < end:
		var cid: Variant = buf.peek_u16()
		if cid == null:
			break
		if int(cid) == M_GEOM_DECL:
			elements.append_array(_read_decl(buf))
		elif int(cid) == M_GEOM_VBUF:
			var rec: Array = _read_vbuf(buf)
			buffers[int(rec[0])] = [rec[1], rec[2]]
		else:
			_skip_chunk(buf)
	buf.pos = end
	return _decode_vertices(vcount, elements, buffers)


static func _read_decl(buf: _Buf) -> Array:
	var start: int = buf.pos
	buf.u16()
	var size: int = buf.u32()
	var end: int = start + size
	var elems: Array = []
	while buf.pos < end:
		var cid: Variant = buf.peek_u16()
		if cid == null or int(cid) != M_GEOM_ELEM:
			break
		buf.u16()
		var esize: int = buf.u32()
		var eend: int = buf.pos + maxi(esize - 6, 0)
		var source: int = buf.u16()
		var typ: int = buf.u16()
		var sem: int = buf.u16()
		var offset: int = buf.u16()
		var index: int = buf.u16()
		elems.append([source, typ, sem, offset, index])
		buf.pos = eend
	buf.pos = end
	return elems


static func _read_vbuf(buf: _Buf) -> Array:
	var start: int = buf.pos
	buf.u16()
	var size: int = buf.u32()
	var end: int = start + size
	var bind: int = buf.u16()
	var stride: int = buf.u16()
	var blob := PackedByteArray()
	while buf.pos < end:
		var cid: Variant = buf.peek_u16()
		if cid != null and int(cid) == M_GEOM_VDATA:
			buf.u16()
			var dsize: int = buf.u32()
			blob = buf.read_bytes(maxi(dsize - 6, 0))
		else:
			if cid == null:
				break
			_skip_chunk(buf)
	buf.pos = end
	return [bind, stride, blob]


static func _decode_vertices(vcount: int, elements: Array, buffers: Dictionary) -> Array:
	# F7 §5: OGRE vectors are left/up/front with the left component negated
	# to reach right/up/front. Python unpacks raw <3f with no negation and
	# does not read skeletons, so this port matches Python (no axis flip).
	# Vertex floats are also always little-endian in Python (`<3f`) even
	# when the file header is big-endian.
	var positions: Array = []
	for _i in vcount:
		positions.append(Vector3.ZERO)
	var normals: Array = []
	var uvs: Array = []
	var have_n := false
	var have_uv := false
	for i in vcount:
		var nrm := Vector3(0.0, 1.0, 0.0)
		var uv := Vector2(0.0, 0.0)
		var pos := Vector3.ZERO
		for elem in elements:
			var source: int = int(elem[0])
			var typ: int = int(elem[1])
			var sem: int = int(elem[2])
			var offset: int = int(elem[3])
			if not buffers.has(source):
				continue
			var rec: Array = buffers[source]
			var stride: int = int(rec[0])
			var blob: PackedByteArray = rec[1]
			var off: int = i * stride + offset
			# Python only guards `off + 4 > len(blob)` then unpacks 12 bytes
			# for FLOAT3 (can raise). Skip the element when the real type
			# does not fit — no-exceptions adaptation.
			if off + 4 > blob.size():
				continue
			if sem == VES_POSITION and typ == 2:
				if off + 12 > blob.size():
					continue
				pos = Vector3(
					blob.decode_float(off),
					blob.decode_float(off + 4),
					blob.decode_float(off + 8)
				)
			elif sem == VES_NORMAL and typ == 2:
				if off + 12 > blob.size():
					continue
				nrm = Vector3(
					blob.decode_float(off),
					blob.decode_float(off + 4),
					blob.decode_float(off + 8)
				)
				have_n = true
			elif sem == VES_TEXCOORD and (typ == 1 or typ == 2 or typ == 3):
				if off + 8 > blob.size():
					continue
				uv = Vector2(blob.decode_float(off), blob.decode_float(off + 4))
				have_uv = true
		positions[i] = pos
		normals.append(nrm)
		uvs.append(uv)
	if not have_n:
		normals = []
	if not have_uv:
		uvs = []
	return [positions, normals, uvs]


static func _ascii_ignore(data: PackedByteArray, from_i: int, to_i: int) -> String:
	var clean := PackedByteArray()
	for i in range(from_i, to_i):
		var b: int = int(data[i])
		if b < 128:
			clean.append(b)
	return clean.get_string_from_ascii()
