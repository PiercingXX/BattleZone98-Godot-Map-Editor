extends RefCounted
## T1-T4 plus sufficiency helpers. Numbers cross-checked against Python.


func run(t) -> void:
	_test_constants(t)
	_test_basin_clean(t)
	_test_t1_steep(t)
	_test_t2_t3_t4(t)
	_test_sufficiency(t)


func _test_constants(t) -> void:
	t.near(BzCheckTerrain.SLOPE_5_DEG, 0.08748866352592401, 1e-12)
	t.near(BzCheckTerrain.SLOPE_45_DEG, 0.9999999999999999, 1e-12)
	t.eq(BzCheckTerrain.T1_MIN_FLAT_FRACTION, 0.175)
	t.eq(BzCheckTerrain.T3_P99_MAX, 3900)
	t.eq(BzCheckTerrain.des_size_band(1280.0), "Small")
	t.eq(BzCheckTerrain.des_size_band(2560.0), "Small")
	t.eq(BzCheckTerrain.des_size_band(3000.0), "Medium")
	t.eq(BzCheckTerrain.des_size_band(4000.0), "Large")


func _test_basin_clean(t) -> void:
	var hm: BzHg2.HeightMap = _basin()
	var v := BzCheckTerrain.new(hm)
	var m: Dictionary = v.measure()
	t.near(float(m["flat_pct"]), 75.20751953125, 0.01, "basin flat_pct")
	t.near(float(m["flat_connected_pct"]), 75.201416015625, 0.01, "basin connected")
	t.eq(m["flat_distributed"], true)
	t.eq(m["modal_raw"], 1000)
	t.near(float(m["p99_raw"]), 2280.0, 0.01, "basin p99")
	t.eq(m["boundary_impassable"], true)
	t.eq(v.validate().size(), 0, "basin passes T1-T4")
	t.eq(BzCheckTerrain.validate_terrain(hm).size(), 0)


func _test_t1_steep(t) -> void:
	var data := PackedInt32Array()
	data.resize(256 * 256)
	for z in 256:
		for x in 256:
			# Steady 0.2 m/m (~11°) ramp; period-2 checkerboards have zero
			# central-difference slope (numpy.gradient) so they would not trip T1.
			data[z * 256 + x] = 500 + x * 10
	var hm := BzHg2.HeightMap.new(1, 1, data)
	var problems: PackedStringArray = BzCheckTerrain.validate_terrain(hm)
	var joined := "\n".join(problems)
	t.ok(joined.contains("T1:"), "steady ramp trips T1")
	t.ok(joined.contains("[error]"), "T1 is an error")


func _test_t2_t3_t4(t) -> void:
	var flat := PackedInt32Array()
	flat.resize(256 * 256)
	flat.fill(1000)
	var flat_p: PackedStringArray = BzCheckTerrain.validate_terrain(BzHg2.HeightMap.new(1, 1, flat))
	t.eq(flat_p.size(), 1, "flat map: only T4")
	t.ok(flat_p[0].begins_with("[error] T4:"), flat_p[0])

	var zero := PackedInt32Array()
	zero.resize(256 * 256)
	zero.fill(0)
	var zp: PackedStringArray = BzCheckTerrain.validate_terrain(BzHg2.HeightMap.new(1, 1, zero))
	var zj := "\n".join(zp)
	t.ok(zj.contains("[warning] T2:"), "modal 0 is T2 warning")
	t.ok(zj.contains("[error] T4:"), "zero map also T4")

	var hi := PackedInt32Array()
	hi.resize(256 * 256)
	hi.fill(4000)
	var hp: PackedStringArray = BzCheckTerrain.validate_terrain(BzHg2.HeightMap.new(1, 1, hi))
	var hj := "\n".join(hp)
	t.ok(hj.contains("[error] T3:"), "p99 4000 is T3")
	t.ok(hj.contains("[warning] T2:"), "modal 4000 is T2")

	var mid := PackedInt32Array()
	mid.resize(256 * 256)
	mid.fill(2000)
	var mp: PackedStringArray = BzCheckTerrain.validate_terrain(BzHg2.HeightMap.new(1, 1, mid))
	t.ok("\n".join(mp).contains("[warning] T2: modal raw height 2000"), "modal 2000")


func _test_sufficiency(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz-trn-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var stub: String = tmp.path_join("stub.trn")
	_write_text(stub, "[Size]\nWidth = 1280\nDepth = 1280\n")
	var stub_p: PackedStringArray = BzCheckTerrain.check_trn_sufficiency(stub)
	var stub_j := "\n".join(stub_p)
	t.ok(stub_j.contains("missing [Color]"), stub_j)
	t.ok(stub_j.contains("missing [Sky]"), stub_j)
	t.ok(stub_j.contains("missing [Atlases]"), stub_j)
	t.ok(stub_j.contains("no [TextureType*]"), stub_j)

	var full: String = tmp.path_join("full.trn")
	_write_text(
		full,
		"[Color]\nfoo = 1\n[Sky]\nbar = 1\n[Atlases]\nbaz = 1\n[TextureType0]\nSolid = a\n"
	)
	var mat: String = tmp.path_join("full.mat")
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_u16(0, 0x0000)
	bytes.encode_u16(2, 0x1000) # material index 1
	bytes.encode_u16(4, 0x1000)
	bytes.encode_u16(6, 0x0000)
	var mf := FileAccess.open(mat, FileAccess.WRITE)
	mf.store_buffer(bytes)
	mf.close()
	var mat_p: PackedStringArray = BzCheckTerrain.check_trn_sufficiency(full, mat)
	t.ok(
		"\n".join(mat_p).contains("material index 1")
		and "\n".join(mat_p).contains("[TextureType1]"),
		"MAT index without TextureType block"
	)

	var ok_des: PackedStringArray = BzCheckTerrain.check_des_fields(
		"WORLD: mars\tSIZE: Small\nGEYSERS: 0\tSCRAP: 0\n",
		"missionName = \"Silver Pools\"\ncustomtags = \"fun\"\n",
		"xx01",
		1280.0
	)
	t.eq(ok_des.size(), 0, "real display name + tags pass")

	var bad_des: PackedStringArray = BzCheckTerrain.check_des_fields(
		"SIZE: Tiny\n",
		"missionName = \"xx01\"\ncustomtags = \"\"\n",
		"xx01",
		1280.0
	)
	t.eq(bad_des.size(), 3, "SIZE + slug name + empty tags")
	t.ok(bad_des[0].contains("SIZE 'Tiny'"), bad_des[0])

	var vxt_miss: PackedStringArray = BzCheckTerrain.check_vxt_players("avobserv only")
	t.eq(vxt_miss.size(), 4)
	t.ok(vxt_miss[0].contains("'svobserv'"), vxt_miss[0])
	t.eq(BzCheckTerrain.check_vxt_players("avobserv svobserv bvobserv cvobserv observer").size(), 0)


func _basin() -> BzHg2.HeightMap:
	var data := PackedInt32Array()
	data.resize(256 * 256)
	var rim := 16
	var step := 80
	var plateau := 1000
	for z in 256:
		for x in 256:
			var edge: int = mini(mini(z, x), mini(255 - z, 255 - x))
			if edge < rim:
				data[z * 256 + x] = plateau + (rim - edge) * step
			else:
				data[z * 256 + x] = plateau
	return BzHg2.HeightMap.new(1, 1, data)


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
