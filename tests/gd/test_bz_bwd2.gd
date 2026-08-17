extends RefCounted
## BzBwd2 — parse VDF/SDF, visible_primary, xforms, write→parse.
## Synthetic bytes are hand-packed here (layouts from bzmap.formats.bwd2 / F5).
## `*.vdf`/`*.sdf` are gitignored, so fixtures are not loaded from disk.


func run(t) -> void:
	_constants(t)
	_parse_vdf(t)
	_parse_sdf(t)
	_empty_name_skipped(t)
	_kind_from_extension(t)
	_xforms(t)
	_write_parse_roundtrip(t)
	_truncated_table(t)


func _constants(t) -> void:
	t.eq(BzBwd2.VDF_RECORD, 100)
	t.eq(BzBwd2.SDF_RECORD, 120)
	t.eq(BzBwd2.LOD_VDF, 7)
	t.eq(BzBwd2.REP_VDF, 4)
	t.eq(BzBwd2.LOD_SDF, 3)
	t.eq(BzBwd2.REP_SDF, 2)
	t.ok(BzBwd2.SKIP_CLASS.has(0x26))
	t.ok(BzBwd2.SKIP_CLASS.has(0x28))
	t.ok(BzBwd2.SKIP_CLASS.has(0x46))
	t.ok(BzBwd2.SKIP_CLASS.has(0x4D))
	t.ok(not BzBwd2.SKIP_CLASS.has(0x3C), "VEHICLE_GEOMETRY is renderable")


func _parse_vdf(t) -> void:
	var model = BzBwd2.read_bwd2(_write_tmp("synthetic.vdf", _synthetic_vdf()))
	t.ok(model != null, "synthetic.vdf parses")
	if model == null:
		return
	t.eq(model.kind, "vdf")
	# 7*4*2 = 56 slots; four named (hull, hp1, rep1, hul1); rest NULL skipped
	t.eq(model.nodes.size(), 4, "NULL slots omitted (Python vs F5 dense table)")
	var hull = model.nodes[0]
	t.eq(hull.name, "hull")
	t.eq(hull.parent, "World")
	t.eq(hull.class_id, 0x3C)
	t.eq(hull.lod, 0)
	t.eq(hull.rep, 0)
	t.near(hull.radius, 5.5, 0.0001)
	t.eq(hull.transform.size(), 12)
	t.near(hull.transform[0], 2.0, 0.0001, "scale baked into basis")
	t.near(hull.transform[9], 10.0, 0.0001)
	t.near(hull.transform[10], 20.0, 0.0001)
	t.near(hull.transform[11], 30.0, 0.0001)

	t.eq(model.nodes[1].name, "hp1")
	t.eq(model.nodes[1].class_id, 0x46)
	t.eq(model.nodes[1].lod, 0)
	t.eq(model.nodes[1].rep, 0)

	t.eq(model.nodes[2].name, "rep1")
	t.eq(model.nodes[2].lod, 0)
	t.eq(model.nodes[2].rep, 1)

	t.eq(model.nodes[3].name, "hul1")
	t.eq(model.nodes[3].lod, 1)
	t.eq(model.nodes[3].rep, 0)

	var vis: Array = BzBwd2.visible_primary(model.nodes)
	t.eq(vis.size(), 1, "gizmo + non-primary filtered")
	t.eq(vis[0].name, "hull")


func _parse_sdf(t) -> void:
	var model = BzBwd2.read_bwd2(_write_tmp("synthetic.sdf", _synthetic_sdf()))
	t.ok(model != null, "synthetic.sdf parses")
	if model == null:
		return
	t.eq(model.kind, "sdf")
	t.eq(model.nodes.size(), 2)
	t.eq(model.nodes[0].name, "bldg")
	t.eq(model.nodes[0].class_id, 0x3D)
	t.eq(model.nodes[0].lod, 0)
	t.eq(model.nodes[0].rep, 0)
	t.near(model.nodes[0].radius, 12.0, 0.0001)
	t.eq(model.nodes[1].name, "lod2")
	t.eq(model.nodes[1].lod, 2)
	t.eq(model.nodes[1].rep, 1)
	var vis: Array = BzBwd2.visible_primary(model.nodes)
	t.eq(vis.size(), 1)
	t.eq(vis[0].name, "bldg")


func _empty_name_skipped(t) -> void:
	var ident := _ident()
	var recs := PackedByteArray()
	var empty := _pack_vdf_node("xxxx", "World", ident, 0x3C, 1.0)
	for i in 8:
		empty[i] = 0
	recs.append_array(empty)
	for _i in 27:
		recs.append_array(_pack_vdf_node("NULL", "NULL", ident, 0, 0.0))
	var payload := PackedByteArray()
	payload.append_array(_u32(1))
	payload.append_array(recs)
	var file := PackedByteArray()
	file.append_array(_chunk("BWD2", PackedByteArray()))
	file.append_array(_chunk("VGEO", payload))
	var model = BzBwd2.read_bwd2(_write_tmp("empty_name.vdf", file))
	t.ok(model != null)
	if model != null:
		t.eq(model.nodes.size(), 0, "empty name skipped like NULL")


func _kind_from_extension(t) -> void:
	# Python: kind is the suffix, stride is the VGEO/SGEO tag.
	var model = BzBwd2.read_bwd2(_write_tmp("mislabelled.sdf", _synthetic_vdf()))
	t.ok(model != null)
	if model == null:
		return
	t.eq(model.kind, "sdf", "kind follows .sdf suffix")
	t.eq(model.nodes.size(), 4, "still parsed as VGEO (100-byte) via tag")


func _xforms(t) -> void:
	var xf := PackedFloat32Array([
		2.0, 0.0, 0.0,
		0.0, 2.0, 0.0,
		0.0, 0.0, 2.0,
		10.0, 20.0, 30.0,
	])
	var p: Vector3 = BzBwd2.xform_point(xf, Vector3(1, 1, 1))
	t.near(p.x, 12.0, 0.0001)
	t.near(p.y, 22.0, 0.0001)
	t.near(p.z, 32.0, 0.0001)
	var d: Vector3 = BzBwd2.xform_dir(xf, [1.0, 1.0, 1.0])
	t.near(d.x, 2.0, 0.0001)
	t.near(d.y, 2.0, 0.0001)
	t.near(d.z, 2.0, 0.0001)
	var ident := _ident()
	var q: Vector3 = BzBwd2.xform_point(ident, [3.0, 4.0, 5.0])
	t.near(q.x, 3.0, 0.0001)
	t.near(q.y, 4.0, 0.0001)
	t.near(q.z, 5.0, 0.0001)


func _write_parse_roundtrip(t) -> void:
	var ident := PackedFloat32Array([
		1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 5.0, 6.0, 7.0,
	])
	var recs := PackedByteArray()
	for lod in 7:
		for rep in 4:
			if lod == 0 and rep == 0:
				recs.append_array(_pack_vdf_node("nose", "World", ident, 0x3C, 1.25))
			else:
				recs.append_array(_pack_vdf_node("NULL", "NULL", ident, 0, 0.0))
	var vgeo := PackedByteArray()
	vgeo.append_array(_u32(1))
	vgeo.append_array(recs)
	vgeo.append_array(PackedByteArray([0x11, 0x22]))
	var file := PackedByteArray()
	file.append_array(_chunk("BWD2", PackedByteArray()))
	file.append_array(_chunk("REV", _u32(7)))
	file.append_array(_chunk("EXIT", PackedByteArray()))
	file.append_array(_chunk("VGEO", vgeo))
	file.append_array(_chunk("EXIT", PackedByteArray()))
	var model = BzBwd2.read_bwd2(_write_tmp("roundtrip.vdf", file))
	t.ok(model != null, "write→parse vdf")
	if model == null:
		return
	t.eq(model.kind, "vdf")
	t.eq(model.nodes.size(), 1)
	t.eq(model.nodes[0].name, "nose")
	t.eq(model.nodes[0].parent, "World")
	t.eq(model.nodes[0].class_id, 0x3C)
	t.near(model.nodes[0].radius, 1.25, 0.0001)
	t.near(model.nodes[0].transform[9], 5.0, 0.0001)
	t.eq(BzBwd2.visible_primary(model.nodes).size(), 1)

	var srecs := PackedByteArray()
	for lod in 3:
		for rep in 2:
			if lod == 0 and rep == 0:
				srecs.append_array(_pack_sdf_node("pad", "World", ident, 0x3D, 9.0))
			else:
				srecs.append_array(_pack_sdf_node("NULL", "NULL", ident, 0, 0.0))
	var sgeo := PackedByteArray()
	sgeo.append_array(_u32(1))
	sgeo.append_array(srecs)
	var sfile := PackedByteArray()
	sfile.append_array(_chunk("BWD2", PackedByteArray()))
	sfile.append_array(_chunk("REV", _u32(8)))
	sfile.append_array(_chunk("SGEO", sgeo))
	var smodel = BzBwd2.read_bwd2(_write_tmp("roundtrip.sdf", sfile))
	t.ok(smodel != null, "write→parse sdf")
	if smodel == null:
		return
	t.eq(smodel.kind, "sdf")
	t.eq(smodel.nodes.size(), 1)
	t.eq(smodel.nodes[0].name, "pad")
	t.eq(smodel.nodes[0].class_id, 0x3D)


func _truncated_table(t) -> void:
	var ident := _ident()
	var payload := PackedByteArray()
	payload.append_array(_u32(2))
	payload.append_array(_pack_vdf_node("only", "World", ident, 0x3C, 1.0))
	var model = BzBwd2.read_bwd2(_write_tmp("trunc.vdf", _chunk("VGEO", payload)))
	t.ok(model != null)
	if model != null:
		t.eq(model.nodes.size(), 1)
		t.eq(model.nodes[0].name, "only")


func _synthetic_vdf() -> PackedByteArray:
	var ident := _ident()
	var hull_xf := PackedFloat32Array([
		2.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 2.0, 10.0, 20.0, 30.0,
	])
	var hp_xf := PackedFloat32Array([
		1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 2.0, 3.0,
	])
	var low_xf := PackedFloat32Array([
		1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 4.0, 5.0, 6.0,
	])
	var recs := PackedByteArray()
	for lod in 7:
		for rep in 4:
			for idx in 2:
				if lod == 0 and rep == 0 and idx == 0:
					recs.append_array(_pack_vdf_node("hull", "World", hull_xf, 0x3C, 5.5))
				elif lod == 0 and rep == 0 and idx == 1:
					recs.append_array(_pack_vdf_node("hp1", "hull", hp_xf, 0x46, 0.25))
				elif lod == 1 and rep == 0 and idx == 0:
					recs.append_array(_pack_vdf_node("hul1", "World", low_xf, 0x3C, 4.0))
				elif lod == 0 and rep == 1 and idx == 0:
					recs.append_array(_pack_vdf_node("rep1", "World", ident, 0x3C, 1.0))
				else:
					recs.append_array(_pack_vdf_node("NULL", "NULL", ident, 0, 0.0))
	var vgeo := PackedByteArray()
	vgeo.append_array(_u32(2))
	vgeo.append_array(recs)
	for _i in 8:
		vgeo.append(0xAA)
	var out := PackedByteArray()
	out.append_array(_chunk("BWD2", PackedByteArray()))
	out.append_array(_chunk("REV", _u32(7)))
	var dummy := PackedByteArray()
	dummy.resize(60)
	out.append_array(_chunk("VDFC", dummy))
	out.append_array(_chunk("EXIT", PackedByteArray()))
	out.append_array(_chunk("VGEO", vgeo))
	out.append_array(_chunk("EXIT", PackedByteArray()))
	out.append_array(_chunk("EXIT", PackedByteArray()))
	return out


func _synthetic_sdf() -> PackedByteArray:
	var ident := _ident()
	var recs := PackedByteArray()
	for lod in 3:
		for rep in 2:
			if lod == 0 and rep == 0:
				recs.append_array(_pack_sdf_node("bldg", "World", ident, 0x3D, 12.0))
			elif lod == 2 and rep == 1:
				recs.append_array(_pack_sdf_node("lod2", "World", ident, 0x3D, 3.0))
			else:
				recs.append_array(_pack_sdf_node("NULL", "NULL", ident, 0, 0.0))
	var sgeo := PackedByteArray()
	sgeo.append_array(_u32(1))
	sgeo.append_array(recs)
	var out := PackedByteArray()
	out.append_array(_chunk("BWD2", PackedByteArray()))
	out.append_array(_chunk("REV", _u32(8)))
	var dummy := PackedByteArray()
	dummy.resize(70)
	out.append_array(_chunk("SDFC", dummy))
	out.append_array(_chunk("SGEO", sgeo))
	out.append_array(_chunk("EXIT", PackedByteArray()))
	out.append_array(_chunk("EXIT", PackedByteArray()))
	out.append_array(_chunk("EXIT", PackedByteArray()))
	return out


func _ident() -> PackedFloat32Array:
	return PackedFloat32Array([
		1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0,
	])


func _chunk(name: String, payload: PackedByteArray) -> PackedByteArray:
	var b := PackedByteArray()
	var nb := name.to_ascii_buffer()
	b.resize(4)
	for i in mini(4, nb.size()):
		b[i] = nb[i]
	b.append_array(_s32(8 + payload.size()))
	b.append_array(payload)
	return b


func _pack_vdf_node(name: String, parent: String, xform: PackedFloat32Array, class_id: int, radius: float) -> PackedByteArray:
	var raw := PackedByteArray()
	raw.resize(100)
	var nb := name.to_ascii_buffer()
	for i in mini(8, nb.size()):
		raw[i] = nb[i]
	for i in 12:
		raw.encode_float(8 + i * 4, xform[i])
	var pb := parent.to_ascii_buffer()
	for i in mini(8, pb.size()):
		raw[0x38 + i] = pb[i]
	raw.encode_float(0x4C, radius)
	raw.encode_u32(0x5C, class_id)
	return raw


func _pack_sdf_node(name: String, parent: String, xform: PackedFloat32Array, class_id: int, radius: float) -> PackedByteArray:
	var raw := _pack_vdf_node(name, parent, xform, class_id, radius)
	raw.resize(120)
	return raw


func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b


func _s32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_s32(0, v)
	return b


func _write_tmp(name: String, data: PackedByteArray) -> String:
	var path := OS.get_temp_dir().path_join("bzbwd2_%s" % name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return path
	f.store_buffer(data)
	return path
