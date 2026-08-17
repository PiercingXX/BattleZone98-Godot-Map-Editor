extends RefCounted
## E4/E5/B1-B3. Clean layout numbers cross-checked against Python.


func run(t) -> void:
	var hm: BzHg2.HeightMap = _basin()
	var g: BzLayout = _balanced_layout()
	var v := BzCheckBalance.new(hm, g)
	var m: Dictionary = v.measure()
	t.eq(int(m["per_base_economy"]["b0"]), 3)
	t.eq(int(m["per_base_economy"]["b1"]), 3)
	t.near(float(m["e4_spread"]), 0.0, 1e-9)
	t.near(float(m["e5_contested_frac"]), 0.5, 1e-9)
	t.near(float(m["base_pocket_m2"]["b0"]), 1232100.0, 1.0)
	t.near(float(m["nearest_base_m"]), 800.0, 0.01)
	t.near(float(m["b2_separation_frac"]), 0.44194173824159216, 1e-6)
	t.eq(m["spawn_count"], 14)
	t.eq(m["spawn_cluster_count"], 2)
	t.near(float(m["min_cluster_spacing_m"]), 20.0, 0.01)
	t.eq(v.validate().size(), 0, "balanced layout passes E4/E5/B1-B3")

	var unbalanced := BzLayout.new(1280.0, 1280.0, 2)
	unbalanced.add_node("b0", 400.0, 400.0, BzLayout.BASE)
	unbalanced.add_node("b1", 880.0, 880.0, BzLayout.BASE)
	unbalanced.add_node("g0", 410.0, 400.0, BzLayout.GEYSER)
	unbalanced.add_node("g1", 420.0, 400.0, BzLayout.GEYSER)
	unbalanced.add_node("g2", 430.0, 400.0, BzLayout.GEYSER)
	unbalanced.add_route("b0", "g0", 10.0)
	unbalanced.add_route("b0", "g1", 10.0)
	unbalanced.add_route("b0", "g2", 10.0)
	unbalanced.add_route("b1", "g0", 1000.0)
	unbalanced.add_route("b1", "g1", 1000.0)
	unbalanced.add_route("b1", "g2", 1000.0)
	unbalanced.add_route("b0", "b1", 800.0)
	var bp: PackedStringArray = BzCheckBalance.validate_balance(hm, unbalanced, [])
	var bj := "\n".join(bp)
	t.ok(bj.contains("[error] E4:"), "unequal economy: %s" % bj)
	t.ok(bj.contains("200.0% exceeds 5%"), bj)
	t.ok(bj.contains("[warning] E5:"), "0% contested")
	t.ok(bj.contains("[error] B3: deathmatch/_SW needs 14 spawns, got 0"), bj)

	# B1: base parked on the steep rim has no buildable pocket.
	var rim := BzLayout.new(1280.0, 1280.0, 2)
	rim.add_node("b0", 5.0, 5.0, BzLayout.BASE)
	rim.add_node("b1", 10.0, 5.0, BzLayout.BASE)
	var b1p: PackedStringArray = BzCheckBalance.new(hm, rim, []).validate()
	t.ok("\n".join(b1p).contains("[error] B1: base b0"), "rim base fails B1")


func _balanced_layout() -> BzLayout:
	var g := BzLayout.new(1280.0, 1280.0, 2)
	g.add_node("b0", 400.0, 400.0, BzLayout.BASE, 0)
	g.add_node("b1", 880.0, 880.0, BzLayout.BASE, 1)
	g.add_node("g0", 420.0, 400.0, BzLayout.GEYSER)
	g.add_node("g1", 860.0, 880.0, BzLayout.GEYSER)
	g.add_node("gc0", 640.0, 640.0, BzLayout.GEYSER)
	g.add_node("gc1", 650.0, 630.0, BzLayout.GEYSER)
	g.add_node("s0", 400.0, 420.0, BzLayout.SCRAP)
	g.add_node("s1", 880.0, 860.0, BzLayout.SCRAP)
	g.add_route("b0", "g0", 20.0)
	g.add_route("b1", "g1", 20.0)
	g.add_route("b0", "s0", 20.0)
	g.add_route("b1", "s1", 20.0)
	g.add_route("b0", "gc0", 500.0)
	g.add_route("b1", "gc0", 550.0)
	g.add_route("b0", "gc1", 550.0)
	g.add_route("b1", "gc1", 500.0)
	g.add_route("b0", "b1", 800.0)
	for team in [0, 1]:
		var bx: float = 400.0 if team == 0 else 880.0
		var bz: float = 400.0 if team == 0 else 880.0
		for i in 7:
			g.add_node("sp%d_%d" % [team, i], bx + float(i) * 20.0, bz + 40.0, BzLayout.SPAWN, team)
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
