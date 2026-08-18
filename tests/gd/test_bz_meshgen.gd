extends RefCounted
## BzMeshGen: water/plant mesh determinism, bounds, and sidecar text.


func run(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz_meshgen_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_test_stem_validation(t)
	_test_water_determinism_and_bounds(t, tmp)
	_test_water_no_geometry(t, tmp)
	_test_plant_determinism(t, tmp)
	_test_sidecars_verbatim(t, tmp)
	_rm_rf(tmp)


func _test_stem_validation(t) -> void:
	var bad: Dictionary = BzMeshGen.validate_feature_stems(
		[{"stem": "toolongxx", "kind": "water"}], "mapstem"
	)
	t.ok(BzErrors.is_err(bad), "stem > 8 is an error")
	t.eq(bad["error"].get("code"), "stem_too_long")

	var collide: Dictionary = BzMeshGen.validate_feature_stems(
		[{"stem": "mapstem", "kind": "water"}], "mapstem"
	)
	t.ok(BzErrors.is_err(collide), "stem colliding with map stem")
	t.eq(collide["error"].get("code"), "stem_collision")

	var dup: Dictionary = BzMeshGen.validate_feature_stems(
		[{"stem": "w1", "kind": "water"}, {"stem": "W1", "kind": "plants"}], "map"
	)
	t.ok(BzErrors.is_err(dup), "duplicate stems")

	var ok: Dictionary = BzMeshGen.validate_feature_stems(
		[{"stem": "w1", "kind": "water"}, {"stem": "plnt1", "kind": "plants"}], "mapstem"
	)
	t.eq(ok.get("ok"), true)


func _test_water_determinism_and_bounds(t, tmp: String) -> void:
	var hm: BzHg2.HeightMap = _pit_heightmap()
	var mask: PackedByteArray = _pit_mask()
	var a: String = tmp.path_join("w_a")
	var b: String = tmp.path_join("w_b")
	DirAccess.make_dir_recursive_absolute(a)
	DirAccess.make_dir_recursive_absolute(b)
	var r1: Dictionary = BzMeshGen.build_water_surface(a, "wtr1", hm, 70.0, "water", 10.0, 1.0, mask)
	var r2: Dictionary = BzMeshGen.build_water_surface(b, "wtr1", hm, 70.0, "water", 10.0, 1.0, mask)
	t.eq(r1.get("ok"), true, "water build ok")
	t.eq(r1.get("written"), true, "water wrote a mesh")
	t.eq(r2.get("written"), true)
	var bytes_a: PackedByteArray = FileAccess.get_file_as_bytes(a.path_join("wtr1.mesh"))
	var bytes_b: PackedByteArray = FileAccess.get_file_as_bytes(b.path_join("wtr1.mesh"))
	t.ok(bytes_a.size() > 26, "water mesh has bytes")
	t.eq(bytes_a, bytes_b, "water mesh is deterministic")

	var bounds: Dictionary = _mesh_bounds(bytes_a)
	t.ok(bool(bounds.get("ok")), "parsed water bounds")
	# Transposed local frame: y is water_level; x is world z; z is world x.
	t.near(float(bounds["miny"]), 70.0, 0.001, "water y min")
	t.near(float(bounds["maxy"]), 70.0, 0.001, "water y max")
	# Pit is cells 40..80; step=2 so verts can sit one tile outside the mask.
	var lo: float = 40.0 * 5.0 - 10.0
	var hi: float = 80.0 * 5.0 + 10.0
	t.ok(float(bounds["minx"]) >= lo - 0.01, "world-z min in pit bbox")
	t.ok(float(bounds["maxx"]) <= hi + 0.01, "world-z max in pit bbox")
	t.ok(float(bounds["minz"]) >= lo - 0.01, "world-x min in pit bbox")
	t.ok(float(bounds["maxz"]) <= hi + 0.01, "world-x max in pit bbox")
	t.ok(float(bounds["maxx"]) - float(bounds["minx"]) > 20.0, "water spans more than one tile")


func _test_water_no_geometry(t, tmp: String) -> void:
	var data := PackedInt32Array()
	data.resize(256 * 256)
	data.fill(2000) # 200 m, above any reasonable waterline
	var hm := BzHg2.HeightMap.new(1, 1, data)
	var out_dir: String = tmp.path_join("w_dry")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var r: Dictionary = BzMeshGen.build_water_surface(out_dir, "dry1", hm, 70.0)
	t.eq(r.get("ok"), true)
	t.eq(r.get("written"), false, "no underwater cells → no mesh")
	t.ok(not FileAccess.file_exists(out_dir.path_join("dry1.mesh")))


func _test_plant_determinism(t, tmp: String) -> void:
	var hm: BzHg2.HeightMap = _pit_heightmap()
	var mask: PackedByteArray = _flat_plant_mask()
	var a: String = tmp.path_join("p_a")
	var b: String = tmp.path_join("p_b")
	var c: String = tmp.path_join("p_c")
	DirAccess.make_dir_recursive_absolute(a)
	DirAccess.make_dir_recursive_absolute(b)
	DirAccess.make_dir_recursive_absolute(c)
	var r1: Dictionary = BzMeshGen.build_plant_field(
		a, "plnt1", hm, 7, 24, "plants", 0.0, 12.0, [], 140.0, 4.0, 2.2, 70.0, mask
	)
	var r2: Dictionary = BzMeshGen.build_plant_field(
		b, "plnt1", hm, 7, 24, "plants", 0.0, 12.0, [], 140.0, 4.0, 2.2, 70.0, mask
	)
	var r3: Dictionary = BzMeshGen.build_plant_field(
		c, "plnt1", hm, 8, 24, "plants", 0.0, 12.0, [], 140.0, 4.0, 2.2, 70.0, mask
	)
	t.eq(r1.get("written"), true, "plants wrote a mesh")
	t.eq(r2.get("written"), true)
	t.eq(r3.get("written"), true)
	var ba: PackedByteArray = FileAccess.get_file_as_bytes(a.path_join("plnt1.mesh"))
	var bb: PackedByteArray = FileAccess.get_file_as_bytes(b.path_join("plnt1.mesh"))
	var bc: PackedByteArray = FileAccess.get_file_as_bytes(c.path_join("plnt1.mesh"))
	t.eq(ba, bb, "same seed → identical plant mesh")
	t.ok(ba != bc, "different seed → different plant mesh")
	var bounds: Dictionary = _mesh_bounds(ba)
	t.ok(bool(bounds.get("ok")))
	# Plants sit near ground (~100 m) minus the 2.5 m sink, blade up to ~5 m.
	t.ok(float(bounds["miny"]) > 80.0, "plants not in the pit")
	t.ok(float(bounds["maxy"]) < 120.0, "plants stay near the surface")


func _test_sidecars_verbatim(t, tmp: String) -> void:
	var hm: BzHg2.HeightMap = _pit_heightmap()
	var out_dir: String = tmp.path_join("side")
	DirAccess.make_dir_recursive_absolute(out_dir)
	BzMeshGen.build_water_surface(out_dir, "wtr1", hm, 70.0, "water", 10.0, 1.0, _pit_mask())
	var mat: PackedByteArray = FileAccess.get_file_as_bytes(out_dir.path_join("wtr1.material"))
	t.ok(mat.size() > 0)
	var mat_s: String = mat.get_string_from_ascii()
	t.ok(mat_s.contains("\r\n"), "material uses CRLF")
	t.ok(mat_s.contains("material water"), "material name from template")
	t.ok(mat_s.contains("thecavew.png"))
	t.ok(mat_s.contains("scene_blend add"))
	t.ok(mat_s.contains("depth_write off"))
	t.ok(mat_s.contains("\ttechnique"), "verbatim tab indent")
	var odf: String = FileAccess.get_file_as_string(out_dir.path_join("wtr1.odf"))
	t.ok(odf.contains('classLabel = "i76building2"'))
	t.ok(odf.contains("unitName = \"wtr1 water\""))
	t.ok(odf.contains("maxHealth = 99999999"))
	t.ok(odf.contains("\r\n"), "odf is CRLF")

	BzMeshGen.build_plant_field(out_dir, "plnt1", hm, 1, 8)
	var pmat: String = FileAccess.get_file_as_string(out_dir.path_join("plnt1.material"))
	t.ok(pmat.contains("EoPlnt01_D.dds"))
	t.ok(pmat.contains("alpha_rejection greater_equal 128"))
	var podf: String = FileAccess.get_file_as_string(out_dir.path_join("plnt1.odf"))
	t.ok(podf.contains("unitName = \"plnt1 plants\""))


func _pit_heightmap() -> BzHg2.HeightMap:
	var data := PackedInt32Array()
	data.resize(256 * 256)
	data.fill(1000) # 100 m flats
	for z in range(40, 81):
		for x in range(40, 81):
			data[z * 256 + x] = 400 # 40 m pit
	return BzHg2.HeightMap.new(1, 1, data)


func _pit_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(256 * 256)
	for z in range(40, 81):
		for x in range(40, 81):
			mask[z * 256 + x] = 1
	return mask


func _flat_plant_mask() -> PackedByteArray:
	## On everywhere except the pit, so plants land on the 100 m flats.
	var mask := PackedByteArray()
	mask.resize(256 * 256)
	mask.fill(1)
	for z in range(40, 81):
		for x in range(40, 81):
			mask[z * 256 + x] = 0
	return mask


func _mesh_bounds(data: PackedByteArray) -> Dictionary:
	if data.size() < 34:
		return {"ok": false}
	var bo: int = data.size() - 34
	if data.decode_u16(bo) != 0x9000:
		return {"ok": false}
	return {
		"ok": true,
		"minx": data.decode_float(bo + 6),
		"miny": data.decode_float(bo + 10),
		"minz": data.decode_float(bo + 14),
		"maxx": data.decode_float(bo + 18),
		"maxy": data.decode_float(bo + 22),
		"maxz": data.decode_float(bo + 26),
	}


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
