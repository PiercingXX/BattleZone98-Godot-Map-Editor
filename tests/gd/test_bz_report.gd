extends RefCounted
## CandidateReport measured values, verdict, write().


func run(t) -> void:
	var hm: BzHg2.HeightMap = _basin()
	var g: BzLayout = _balanced_layout()
	var report := BzReport.new(hm, g, null, [], 7)
	var d: Dictionary = report.to_dict()
	t.eq(d["seed"], 7)
	t.eq(d["width_m"], 1280.0)
	t.eq(d["depth_m"], 1280.0)
	t.eq(d["grid"], [256, 256])
	t.eq(d["verdict"], "pass")
	t.ok(d.has("measured"))
	t.ok((d["measured"] as Dictionary).has("terrain"))
	t.ok((d["measured"] as Dictionary).has("connectivity"))
	t.ok((d["measured"] as Dictionary).has("balance"))
	t.eq((d["problems"]["error"] as Array).size(), 0)
	t.eq(report.problems().size(), 0)

	var img: Image = report.preview()
	t.ok(img != null and img.get_width() == 512 and img.get_height() == 512)

	var out: String = OS.get_temp_dir().path_join("bz-rep-%d" % Time.get_ticks_usec())
	var json_path: String = BzReport.write_report(out, hm, g, null, ["[error] injected"], 1)
	t.ok(FileAccess.file_exists(json_path), "report.json written")
	t.ok(FileAccess.file_exists(out.path_join("preview.png")), "preview.png written")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	t.ok(typeof(parsed) == TYPE_DICTIONARY)
	t.eq(parsed["verdict"], "fail")
	t.ok((parsed["problems"]["error"] as Array).size() >= 1)

	var broken := BzLayout.new(1280.0, 1280.0, 2)
	broken.add_node("b0", 400.0, 400.0, BzLayout.BASE)
	var fail := BzReport.new(hm, broken)
	t.eq(fail.to_dict()["verdict"], "fail")
	t.ok(fail.problems().size() > 0)


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
