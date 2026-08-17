extends RefCounted
## C1-C4 on a synthetic 256² basin. Cross-checked against Python.


func run(t) -> void:
	var hm: BzHg2.HeightMap = _basin()
	var g := _clean_layout()
	var v := BzCheckConnectivity.new(hm, g)
	var m: Dictionary = v.measure()
	t.near(float(m["traversable_pct"]), 75.20751953125, 0.05, "traversable_pct")
	t.eq((m["unreachable_economy"] as Array).size(), 0)
	t.eq((m["single_corridor_pairs"] as Array).size(), 0)
	t.ok(m["min_corridor_width_m"] != null and float(m["min_corridor_width_m"]) >= 30.0)
	t.eq(v.validate().size(), 0, "clean basin+layout passes C1-C4")
	t.eq(BzCheckConnectivity.validate_connectivity(hm, g).size(), 0)

	var bad := BzLayout.new(1280.0, 1280.0, 2)
	bad.add_node("b0", 400.0, 400.0, BzLayout.BASE)
	bad.add_node("b1", 880.0, 880.0, BzLayout.BASE)
	bad.add_node("bad", 10.0, 10.0, BzLayout.GEYSER)
	var c1: PackedStringArray = BzCheckConnectivity.validate_connectivity(hm, bad)
	t.ok(c1.size() >= 1 and c1[0].contains("C1:"), c1[0] if c1.size() else "no C1")
	t.ok(c1[0].contains("'bad'"), "unreachable id listed")
	t.ok(c1[0].begins_with("[error]"), "C1 is an error")

	var pocket: BzHg2.HeightMap = _basin_with_corner_pocket()
	var c2v := BzCheckConnectivity.new(pocket, g)
	var c2m: Dictionary = c2v.measure()
	var traps: Array = c2m["trap_areas_m2"]
	t.ok(traps.size() >= 1, "corner pocket recorded")
	var c2p: PackedStringArray = c2v.validate()
	var c2j := "\n".join(c2p)
	t.ok(c2j.contains("[warning] C2:"), "large pocket is a warning: %s" % c2j)


func _clean_layout() -> BzLayout:
	var g := BzLayout.new(1280.0, 1280.0, 2)
	g.add_node("b0", 400.0, 400.0, BzLayout.BASE, 0)
	g.add_node("b1", 880.0, 880.0, BzLayout.BASE, 1)
	g.add_node("g0", 640.0, 400.0, BzLayout.GEYSER)
	g.add_node("s0", 400.0, 640.0, BzLayout.SCRAP)
	return g


func _basin() -> BzHg2.HeightMap:
	var data := PackedInt32Array()
	data.resize(256 * 256)
	for z in 256:
		for x in 256:
			var edge: int = mini(mini(z, x), mini(255 - z, 255 - x))
			if edge < 16:
				data[z * 256 + x] = 1000 + (16 - edge) * 80
			else:
				data[z * 256 + x] = 1000
	return BzHg2.HeightMap.new(1, 1, data)


func _basin_with_corner_pocket() -> BzHg2.HeightMap:
	var data := PackedInt32Array()
	data.resize(256 * 256)
	for z in 256:
		for x in 256:
			var edge: int = mini(mini(z, x), mini(255 - z, 255 - x))
			if edge < 16:
				data[z * 256 + x] = 1000 + (16 - edge) * 80
			else:
				data[z * 256 + x] = 1000
	# Flatten the outer 20×20 corner to the rim peak so it is a disconnected
	# traversable pocket (~10 000 m² > C2_WARN 5000).
	for z in 20:
		for x in 20:
			data[z * 256 + x] = 2280
	return BzHg2.HeightMap.new(1, 1, data)
