extends RefCounted
class_name BzGlb
## Minimal glTF 2.0 / GLB writer. Port of formats/glb.py.

const GLTF_VERSION := 2
const TARGET_ARRAY := 34962
const TARGET_ELEMENT_ARRAY := 34963
const COMP_F32 := 5126
const COMP_U16 := 5123
const COMP_U32 := 5125
const MODE_TRIANGLES := 4


static func write_glb(path: String, primitives: Array, images: Variant = null) -> Dictionary:
	var img_list: Array = []
	if images != null and images is Array:
		img_list = images
	var bin_blob := PackedByteArray()
	var views: Array = []
	var accessors: Array = []
	var prims_json: Array = []
	var materials: Array = []
	var gltf_images: Array = []
	var textures: Array = []

	for img in img_list:
		if img == null or not (img is Image):
			continue
		var src: Image = img
		var rgba: Image = src
		if src.get_format() != Image.FORMAT_RGBA8:
			rgba = src.duplicate()
			rgba.convert(Image.FORMAT_RGBA8)
		var png: PackedByteArray = rgba.save_png_to_buffer()
		var view: int = _add_blob(bin_blob, views, png, -1)
		gltf_images.append({"bufferView": view, "mimeType": "image/png"})
		textures.append({"source": gltf_images.size() - 1})

	for prim in primitives:
		if not (prim is Dictionary):
			continue
		var rec: Dictionary = prim
		var pos := _vec3_list(rec.get("positions", []))
		var nrm_raw: Variant = rec.get("normals", null)
		var uv_raw: Variant = rec.get("uvs", null)
		var nrm: Array
		var uvs: Array
		# Python: prim.get("normals") or [(0,1,0)]*n — empty is falsy.
		if _is_empty_seq(nrm_raw):
			nrm = []
			for _i in pos.size():
				nrm.append(Vector3(0.0, 1.0, 0.0))
		else:
			nrm = _vec3_list(nrm_raw)
		if _is_empty_seq(uv_raw):
			uvs = []
			for _i in pos.size():
				uvs.append(Vector2(0.0, 0.0))
		else:
			uvs = _vec2_list(uv_raw)
		var idx := _int_list(rec.get("indices", []))
		if pos.is_empty() or idx.is_empty():
			continue
		var pos_b := _pack_vec3(pos)
		var nrm_b := _pack_vec3(nrm)
		var uv_b := _pack_vec2(uvs)
		var mx: int = 0
		for iv in idx:
			if int(iv) > mx:
				mx = int(iv)
		var idx_b: PackedByteArray
		var idx_type: int
		if mx > 65535:
			idx_b = _pack_u32(idx)
			idx_type = COMP_U32
		else:
			idx_b = _pack_u16(idx)
			idx_type = COMP_U16
		# Python pads every blob to 4 with 0x00; both target branches are identical.
		var pv: int = _add_blob(bin_blob, views, pos_b, TARGET_ARRAY)
		var nv: int = _add_blob(bin_blob, views, nrm_b, TARGET_ARRAY)
		var uv: int = _add_blob(bin_blob, views, uv_b, TARGET_ARRAY)
		var iview: int = _add_blob(bin_blob, views, idx_b, TARGET_ELEMENT_ARRAY)
		var pmm: Array = _minmax_vec3(pos)
		var nmm: Array = _minmax_vec3(nrm)
		var umm: Array = _minmax_vec2(uvs)
		accessors.append({
			"bufferView": pv,
			"componentType": COMP_F32,
			"count": pos.size(),
			"type": "VEC3",
			"min": pmm[0],
			"max": pmm[1],
		})
		accessors.append({
			"bufferView": nv,
			"componentType": COMP_F32,
			"count": nrm.size(),
			"type": "VEC3",
			"min": nmm[0],
			"max": nmm[1],
		})
		accessors.append({
			"bufferView": uv,
			"componentType": COMP_F32,
			"count": uvs.size(),
			"type": "VEC2",
			"min": umm[0],
			"max": umm[1],
		})
		accessors.append({
			"bufferView": iview,
			"componentType": idx_type,
			"count": idx.size(),
			"type": "SCALAR",
		})
		var base: int = accessors.size() - 4
		# Docstring says optional "color"; the Python reads "colour" only.
		var colour: Variant = rec.get("colour", null)
		var cr := 180.0 / 255.0
		var cg := 180.0 / 255.0
		var cb := 180.0 / 255.0
		if colour != null:
			var rgb: Array = _colour_rgb(colour)
			if rgb.size() >= 3:
				cr = float(rgb[0])
				cg = float(rgb[1])
				cb = float(rgb[2])
		var pbr := {
			"baseColorFactor": [cr, cg, cb, 1.0],
			"metallicFactor": 0.0,
			"roughnessFactor": 0.9,
		}
		var img_i: Variant = rec.get("image", null)
		if img_i != null and int(img_i) >= 0 and int(img_i) < textures.size():
			pbr["baseColorTexture"] = {"index": int(img_i)}
		var mat := {"pbrMetallicRoughness": pbr}
		materials.append(mat)
		var attrs := {}
		attrs["POSITION"] = base
		attrs["NORMAL"] = base + 1
		attrs["TEXCOORD_0"] = base + 2
		prims_json.append({
			"attributes": attrs,
			"indices": base + 3,
			"material": materials.size() - 1,
			"mode": MODE_TRIANGLES,
		})

	if prims_json.is_empty():
		return BzErrors.err(
			"no_primitives",
			"no primitives to write",
			"Each primitive needs positions and indices."
		)

	var root := {}
	root["asset"] = {"version": "2.0", "generator": "bzmap"}
	root["scene"] = 0
	root["scenes"] = [{"nodes": [0]}]
	root["nodes"] = [{"mesh": 0}]
	root["meshes"] = [{"primitives": prims_json}]
	root["accessors"] = accessors
	root["bufferViews"] = views
	root["buffers"] = [{"byteLength": bin_blob.size()}]
	root["materials"] = materials
	if not gltf_images.is_empty():
		root["images"] = gltf_images
		root["textures"] = textures

	# compact, insertion-order, full float precision — matches
	# json.dumps(root, separators=(",", ":")) for this schema.
	var js_text: String = JSON.stringify(root, "", false, true)
	var js: PackedByteArray = js_text.to_utf8_buffer()
	js = _pad(js, 4, 0x20)
	var blob: PackedByteArray = _pad(bin_blob, 4, 0x00)
	var total: int = 12 + 8 + js.size() + 8 + blob.size()
	var out := PackedByteArray()
	out.resize(total)
	var o: int = 0
	out[o] = 0x67
	out[o + 1] = 0x6C
	out[o + 2] = 0x54
	out[o + 3] = 0x46
	out.encode_u32(o + 4, GLTF_VERSION)
	out.encode_u32(o + 8, total)
	o += 12
	out.encode_u32(o, js.size())
	out[o + 4] = 0x4A
	out[o + 5] = 0x53
	out[o + 6] = 0x4F
	out[o + 7] = 0x4E
	o += 8
	for i in js.size():
		out[o + i] = js[i]
	o += js.size()
	out.encode_u32(o, blob.size())
	out[o + 4] = 0x42
	out[o + 5] = 0x49
	out[o + 6] = 0x4E
	out[o + 7] = 0x00
	o += 8
	for i in blob.size():
		out[o + i] = blob[i]

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return BzErrors.err(
			"io",
			"%s: cannot write" % path,
			error_string(FileAccess.get_open_error())
		)
	f.store_buffer(out)
	return {"ok": true, "path": path}


static func _add_blob(
	bin_blob: PackedByteArray,
	views: Array,
	data: PackedByteArray,
	target: int
) -> int:
	var padded: PackedByteArray = _pad(data, 4, 0x00)
	var view := {
		"buffer": 0,
		"byteOffset": bin_blob.size(),
		"byteLength": padded.size(),
	}
	if target >= 0:
		view["target"] = target
	views.append(view)
	bin_blob.append_array(padded)
	return views.size() - 1


static func _pad(buf: PackedByteArray, align: int = 4, fill: int = 0x20) -> PackedByteArray:
	var n: int = posmod(-buf.size(), align)
	if n == 0:
		return buf
	var out := buf.duplicate()
	for _i in n:
		out.append(fill)
	return out


static func _minmax_vec3(values: Array) -> Array:
	if values.is_empty():
		return [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for item in values:
		var v: Vector3 = item
		lo.x = minf(lo.x, v.x)
		lo.y = minf(lo.y, v.y)
		lo.z = minf(lo.z, v.z)
		hi.x = maxf(hi.x, v.x)
		hi.y = maxf(hi.y, v.y)
		hi.z = maxf(hi.z, v.z)
	return [[lo.x, lo.y, lo.z], [hi.x, hi.y, hi.z]]


static func _minmax_vec2(values: Array) -> Array:
	if values.is_empty():
		return [[0.0, 0.0], [0.0, 0.0]]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for item in values:
		var v: Vector2 = item
		lo.x = minf(lo.x, v.x)
		lo.y = minf(lo.y, v.y)
		hi.x = maxf(hi.x, v.x)
		hi.y = maxf(hi.y, v.y)
	return [[lo.x, lo.y], [hi.x, hi.y]]


static func _pack_vec3(values: Array) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(values.size() * 12)
	for i in values.size():
		var v: Vector3 = values[i]
		buf.encode_float(i * 12, v.x)
		buf.encode_float(i * 12 + 4, v.y)
		buf.encode_float(i * 12 + 8, v.z)
	return buf


static func _pack_vec2(values: Array) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(values.size() * 8)
	for i in values.size():
		var v: Vector2 = values[i]
		buf.encode_float(i * 8, v.x)
		buf.encode_float(i * 8 + 4, v.y)
	return buf


static func _pack_u16(values: Array) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(values.size() * 2)
	for i in values.size():
		buf.encode_u16(i * 2, int(values[i]))
	return buf


static func _pack_u32(values: Array) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(values.size() * 4)
	for i in values.size():
		buf.encode_u32(i * 4, int(values[i]))
	return buf


static func _vec3_list(values: Variant) -> Array:
	var out: Array = []
	if values == null:
		return out
	if values is PackedVector3Array:
		var pv: PackedVector3Array = values
		for v in pv:
			out.append(v)
		return out
	if values is Array:
		for item in values:
			out.append(_as_vec3(item))
	return out


static func _vec2_list(values: Variant) -> Array:
	var out: Array = []
	if values == null:
		return out
	if values is PackedVector2Array:
		var pv: PackedVector2Array = values
		for v in pv:
			out.append(v)
		return out
	if values is Array:
		for item in values:
			out.append(_as_vec2(item))
	return out


static func _int_list(values: Variant) -> Array:
	var out: Array = []
	if values == null:
		return out
	if values is PackedInt32Array:
		var pi: PackedInt32Array = values
		for v in pi:
			out.append(int(v))
		return out
	if values is PackedInt64Array:
		var pl: PackedInt64Array = values
		for v in pl:
			out.append(int(v))
		return out
	if values is Array:
		for item in values:
			out.append(int(item))
	return out


static func _as_vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Vector3i:
		var vi: Vector3i = v
		return Vector3(vi)
	if v is Array or v is PackedFloat32Array or v is PackedFloat64Array or v is PackedInt32Array:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


static func _as_vec2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Vector2i:
		var vi: Vector2i = v
		return Vector2(vi)
	if v is Array or v is PackedFloat32Array or v is PackedFloat64Array or v is PackedInt32Array:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


static func _colour_rgb(colour: Variant) -> Array:
	# Keep factors in GDScript float (64-bit) so JSON.stringify(..., full_precision)
	# matches Python json.dumps(r/255.0). PackedFloat32Array would round 180/255.
	var out: Array = []
	if colour is Color:
		var c: Color = colour
		out.append(c.r)
		out.append(c.g)
		out.append(c.b)
		return out
	if colour is Array or colour is PackedByteArray or colour is PackedInt32Array \
			or colour is PackedFloat32Array or colour is PackedFloat64Array:
		# Python colour is 0–255.
		if colour.size() >= 3:
			out.append(float(colour[0]) / 255.0)
			out.append(float(colour[1]) / 255.0)
			out.append(float(colour[2]) / 255.0)
	return out


static func _is_empty_seq(v: Variant) -> bool:
	if v == null:
		return true
	if v is Array:
		return (v as Array).is_empty()
	if v is PackedVector3Array:
		return (v as PackedVector3Array).is_empty()
	if v is PackedVector2Array:
		return (v as PackedVector2Array).is_empty()
	if v is PackedFloat32Array:
		return (v as PackedFloat32Array).is_empty()
	return false
