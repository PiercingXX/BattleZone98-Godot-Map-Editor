extends RefCounted
class_name BzGeo
## Classic `.geo` mesh reader (docs/formats/F4). Port of `bzmap.formats.geo`.

const _HEADER_SIZE := 36
const _FACE_FIXED_SIZE := 55
const _NODE_SIZE := 16


class GeoFace extends RefCounted:
	var colour: Array = [0, 0, 0]
	var texture_name: String = ""
	var nodes: Array = []


class GeoMesh extends RefCounted:
	var name: String = ""
	var flags: int = 0
	var checksum: int = 0
	var positions: Array = []
	var normals: Array = []
	var faces: Array = []


static func read_geo(path: String) -> GeoMesh:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("%s: cannot open (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return _parse_geo(data, path)


static func geo_to_primitives(mesh: GeoMesh) -> Array:
	## Fan-triangulate, split on (pos, nrm, uv). Group by material key.
	var groups: Dictionary = {}
	for face in mesh.faces:
		var key: String
		if face.texture_name.is_empty():
			# Python: f"rgb:{face.colour}" with a 3-int tuple, e.g. "rgb:(255, 128, 0)".
			key = "rgb:(%d, %d, %d)" % [int(face.colour[0]), int(face.colour[1]), int(face.colour[2])]
		else:
			key = String(face.texture_name).to_lower()
		if not groups.has(key):
			groups[key] = {
				"verts": [],
				"norms": [],
				"uvs": [],
				"indices": [],
				"colour": face.colour,
				"texture": face.texture_name,
				"lookup": {},
			}
		var prim: Dictionary = groups[key]
		var idxs: Array = []
		var aborted := false
		for node in face.nodes:
			var pi: int = int(node[0])
			var ni: int = int(node[1])
			var u: float = float(node[2])
			var v: float = float(node[3])
			if pi < 0 or pi >= mesh.positions.size():
				idxs = []
				aborted = true
				break
			var nrm: Vector3
			if ni >= 0 and ni < mesh.normals.size():
				nrm = mesh.normals[ni]
			else:
				nrm = Vector3(0.0, 1.0, 0.0)
			var pos: Vector3 = mesh.positions[pi]
			var tup := _vert_key(pos, nrm, u, v)
			var lookup: Dictionary = prim["lookup"]
			var slot: int
			if lookup.has(tup):
				slot = int(lookup[tup])
			else:
				slot = (prim["verts"] as Array).size()
				lookup[tup] = slot
				(prim["verts"] as Array).append(pos)
				(prim["norms"] as Array).append(nrm)
				(prim["uvs"] as Array).append(Vector2(u, v))
			idxs.append(slot)
		if aborted:
			continue
		for i in range(1, idxs.size() - 1):
			var a: int = int(idxs[0])
			var b: int = int(idxs[i])
			var c: int = int(idxs[i + 1])
			if a == b or b == c or a == c:
				continue
			(prim["indices"] as Array).append(a)
			(prim["indices"] as Array).append(b)
			(prim["indices"] as Array).append(c)
	var out: Array = []
	for g in groups.values():
		if not (g["indices"] as Array).is_empty():
			out.append(g)
	return out


static func _parse_geo(data: PackedByteArray, path: String) -> GeoMesh:
	if data.size() < _HEADER_SIZE:
		push_error("%s: too short for a .geo header" % path)
		return null
	if not _magic_ok(data):
		push_error("%s: bad magic %s" % [path, _bytes_repr(data.slice(0, 4))])
		return null
	var checksum: int = data.decode_s32(4)
	var nvert: int = data.decode_s32(24)
	var nface: int = data.decode_s32(28)
	var flags: int = data.decode_s32(32)
	if nvert < 0 or nface < 0:
		push_error("%s: negative counts" % path)
		return null
	var off: int = _HEADER_SIZE
	var pos_bytes: int = 12 * nvert
	var nrm_bytes: int = 12 * nvert
	if off + pos_bytes + nrm_bytes > data.size():
		push_error("%s: truncated vertex data" % path)
		return null
	var mesh := GeoMesh.new()
	mesh.name = _cstr(data, 8, 16)
	mesh.flags = flags
	mesh.checksum = checksum
	for i in nvert:
		mesh.positions.append(_vec3(data, off + i * 12))
	off += pos_bytes
	for i in nvert:
		mesh.normals.append(_vec3(data, off + i * 12))
	off += nrm_bytes
	for _f in nface:
		if off + _FACE_FIXED_SIZE > data.size():
			push_error("%s: truncated face at %s" % [path, off])
			return null
		# Face fixed part is 55 bytes with no alignment padding (F4 §3).
		# Python keeps only colour, texture_name, and nodes — plane/area/shade/
		# texture_type/xluscent/parent/tree_branch are read and discarded.
		var node_count: int = data.decode_s32(off + 4)
		var cr: int = data.decode_u8(off + 8)
		var cg: int = data.decode_u8(off + 9)
		var cb: int = data.decode_u8(off + 10)
		var tex := _cstr(data, off + 0x22, 13)
		off += _FACE_FIXED_SIZE
		var nodes: Array = []
		for _n in node_count:
			if off + _NODE_SIZE > data.size():
				push_error("%s: truncated face node at %s" % [path, off])
				return null
			var pi: int = data.decode_s32(off)
			var ni: int = data.decode_s32(off + 4)
			var u: float = data.decode_float(off + 8)
			var v: float = data.decode_float(off + 12)
			off += _NODE_SIZE
			# F4 §5: stored v is inverted. Python applies the flip on read.
			nodes.append([pi, ni, u, 1.0 - v])
		if node_count >= 3:
			var face := GeoFace.new()
			face.colour = [cr, cg, cb]
			face.texture_name = tex
			face.nodes = nodes
			mesh.faces.append(face)
	return mesh


static func _magic_ok(data: PackedByteArray) -> bool:
	if data.size() < 4:
		return false
	# Spec (F4 §1) documents only ASCII ".GEO". Python also accepts the
	# byte-swapped "OEG." and still unpacks the rest little-endian.
	if data[0] == 0x2E and data[1] == 0x47 and data[2] == 0x45 and data[3] == 0x4F:
		return true
	if data[0] == 0x4F and data[1] == 0x45 and data[2] == 0x47 and data[3] == 0x2E:
		return true
	return false


static func _cstr(data: PackedByteArray, from: int, length: int) -> String:
	var end: int = mini(data.size(), from + length)
	var stop: int = from
	while stop < end and data[stop] != 0:
		stop += 1
	# ASCII, errors="ignore": drop bytes >= 128 (Red Odyssey / F8 §6).
	var cleaned := PackedByteArray()
	for i in range(from, stop):
		if data[i] < 128:
			cleaned.append(data[i])
	return cleaned.get_string_from_ascii()


static func _vec3(data: PackedByteArray, off: int) -> Vector3:
	return Vector3(data.decode_float(off), data.decode_float(off + 4), data.decode_float(off + 8))


static func _vert_key(p: Vector3, n: Vector3, u: float, v: float) -> String:
	var b := PackedByteArray()
	b.resize(32)
	b.encode_float(0, p.x)
	b.encode_float(4, p.y)
	b.encode_float(8, p.z)
	b.encode_float(12, n.x)
	b.encode_float(16, n.y)
	b.encode_float(20, n.z)
	b.encode_float(24, u)
	b.encode_float(28, v)
	return b.hex_encode()


static func _bytes_repr(raw: PackedByteArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i in raw.size():
		var b: int = raw[i]
		if b >= 32 and b < 127:
			parts.append(String.chr(b))
		else:
			parts.append("\\x%02x" % b)
	return "b'%s'" % "".join(parts)
