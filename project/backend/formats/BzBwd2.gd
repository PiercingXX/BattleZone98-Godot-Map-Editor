extends RefCounted
class_name BzBwd2
## `.vdf` / `.sdf` BWD2 node containers (docs/formats/F5). Port of `bzmap.formats.bwd2`.

const VDF_RECORD := 100
const SDF_RECORD := 120
const LOD_VDF := 7
const REP_VDF := 4
const LOD_SDF := 3
const REP_SDF := 2

## Gizmo class IDs excluded from converter meshes (F5 §8). Python set.
const SKIP_CLASS := {
	0x26: true,
	0x28: true,
	0x46: true,
	0x47: true,
	0x48: true,
	0x49: true,
	0x4A: true,
	0x4B: true,
	0x4C: true,
	0x4D: true,
}


class Bwd2Node extends RefCounted:
	var name: String = ""
	var parent: String = ""
	var transform: PackedFloat32Array = PackedFloat32Array()
	var class_id: int = 0
	var lod: int = 0
	var rep: int = 0
	var radius: float = 0.0


class Bwd2Model extends RefCounted:
	var kind: String = "vdf"
	var nodes: Array = []


static func read_bwd2(path: String) -> Bwd2Model:
	## Extract VGEO/SGEO nodes. Not a full parse/emit pair: VDFC/SDFC/ANIM/COLP/
	## SPCS/VCHK/EXIT and any VGEO trailing bytes are skipped, matching Python.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("%s: cannot open (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	var model := Bwd2Model.new()
	# Python: kind comes from the path suffix, not the VGEO/SGEO tag.
	model.kind = "sdf" if path.get_extension().to_lower() == "sdf" else "vdf"
	var off := 0
	while off + 8 <= data.size():
		var size: int = data.decode_s32(off + 4)
		if size < 8 or off + size > data.size():
			break
		var payload := data.slice(off + 8, off + size)
		var tag := _chunk_tag(data.slice(off, off + 4))
		if tag == "VGEO" or tag == "SGEO":
			model.nodes = _parse_geo_table(payload, tag == "SGEO")
		off += size
	return model


static func visible_primary(nodes: Array) -> Array:
	## LOD 0 / REP 0 renderable geometry nodes.
	var out: Array = []
	for n in nodes:
		if n.lod != 0 or n.rep != 0:
			continue
		if SKIP_CLASS.has(n.class_id):
			continue
		out.append(n)
	return out


static func xform_point(xform: Variant, p: Variant) -> Vector3:
	## Apply a 12-float right/up/front/posit transform to a point.
	var x := _as12(xform)
	var v := _as3(p)
	return Vector3(
		x[0] * v.x + x[3] * v.y + x[6] * v.z + x[9],
		x[1] * v.x + x[4] * v.y + x[7] * v.z + x[10],
		x[2] * v.x + x[5] * v.y + x[8] * v.z + x[11],
	)


static func xform_dir(xform: Variant, p: Variant) -> Vector3:
	var x := _as12(xform)
	var v := _as3(p)
	return Vector3(
		x[0] * v.x + x[3] * v.y + x[6] * v.z,
		x[1] * v.x + x[4] * v.y + x[7] * v.z,
		x[2] * v.x + x[5] * v.y + x[8] * v.z,
	)


static func _parse_geo_table(payload: PackedByteArray, sdf: bool) -> Array:
	if payload.size() < 4:
		return []
	var count: int = payload.decode_u32(0)
	var rec: int = SDF_RECORD if sdf else VDF_RECORD
	var lod_n: int = LOD_SDF if sdf else LOD_VDF
	var rep_n: int = REP_SDF if sdf else REP_VDF
	var nodes: Array = []
	var off := 4
	for lod in lod_n:
		for rep in rep_n:
			for _i in count:
				if off + rec > payload.size():
					return nodes
				var raw := payload.slice(off, off + rec)
				off += rec
				var name := _cname(raw, 0, 8)
				# Spec F5 §6: the slot table is dense and NULL records are present.
				# Python skips NULL / empty names and never returns them.
				if name.to_upper() == "NULL" or name.is_empty():
					continue
				var node := Bwd2Node.new()
				node.name = name
				node.parent = _cname(raw, 0x38, 8)
				node.transform = PackedFloat32Array()
				node.transform.resize(12)
				for k in 12:
					node.transform[k] = raw.decode_float(8 + k * 4)
				node.radius = raw.decode_float(0x4C)
				node.class_id = raw.decode_u32(0x5C)
				node.lod = lod
				node.rep = rep
				nodes.append(node)
	return nodes


static func _chunk_tag(name4: PackedByteArray) -> String:
	# F5 §2: REV is written `REV\0`. Python matches the first three bytes.
	if name4.size() >= 3 and name4[0] == 0x52 and name4[1] == 0x45 and name4[2] == 0x56:
		return "REV"
	var end := name4.size()
	while end > 0 and name4[end - 1] == 0:
		end -= 1
	return name4.slice(0, end).get_string_from_ascii()


static func _cname(raw: PackedByteArray, from: int, length: int) -> String:
	var stop: int = from
	var lim: int = mini(raw.size(), from + length)
	while stop < lim and raw[stop] != 0:
		stop += 1
	var cleaned := PackedByteArray()
	for i in range(from, stop):
		if raw[i] < 128:
			cleaned.append(raw[i])
	return cleaned.get_string_from_ascii()


static func _as12(xform: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(12)
	if xform is PackedFloat32Array or xform is Array:
		var n: int = mini(12, xform.size())
		for i in n:
			out[i] = float(xform[i])
	return out


static func _as3(p: Variant) -> Vector3:
	if p is Vector3:
		return p
	if p is Vector2:
		return Vector3(p.x, p.y, 0.0)
	if p is Array or p is PackedFloat32Array or p is PackedFloat64Array:
		var x := 0.0
		var y := 0.0
		var z := 0.0
		if p.size() > 0:
			x = float(p[0])
		if p.size() > 1:
			y = float(p[1])
		if p.size() > 2:
			z = float(p[2])
		return Vector3(x, y, z)
	return Vector3.ZERO
