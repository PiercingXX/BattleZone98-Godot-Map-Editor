extends RefCounted
## BzOdf: write, parse [SBPMapSettings], write→parse, scrap PrjIDs, Python golden.


func run(t) -> void:
	var work := _work_dir()
	var path := work.path_join("map.odf")

	# --- write with no control points ---
	BzOdf.write_odf(path)
	var bare_want := (
		"[SBPMapSettings]\r\n"
		+ "\r\n"
		+ "\r\n"
		+ "[ScrapImpactZone]\r\n"
		+ "SIZ_IncludeSpawnPoints = 1\r\n"
	)
	_eq_bytes(t, path, bare_want, "write_odf bare match odf.py")

	var cfg: BzTrn.TerrainConfig = BzTrn.read_trn(path)
	t.ok(cfg.section("SBPMapSettings") != null, "legacy section name preserved")
	t.eq(cfg.get("ScrapImpactZone", "SIZ_IncludeSpawnPoints"), "1")

	# empty list is falsy in Python — same bare file
	BzOdf.write_odf(path, [])
	_eq_bytes(t, path, bare_want, "empty control_points == omitted")

	# --- control points + scrap flag off ---
	BzOdf.write_odf(path, [["alpha", 10, 20.5], ["beta", 0, 0]], false)
	var cps_want := (
		"[SBPMapSettings]\r\n"
		+ "\r\n"
		+ "CP1Name = alpha\r\n"
		+ "CP1X = 10\r\n"
		+ "CP1Z = 20.5\r\n"
		+ "CP2Name = beta\r\n"
		+ "CP2X = 0\r\n"
		+ "CP2Z = 0\r\n"
		+ "\r\n"
		+ "[ScrapImpactZone]\r\n"
		+ "SIZ_IncludeSpawnPoints = 0\r\n"
	)
	_eq_bytes(t, path, cps_want, "write_odf CPs match odf.py")
	var cps: BzTrn.TerrainConfig = BzTrn.read_trn(path)
	t.eq(cps.get("SBPMapSettings", "CP1Name"), "alpha")
	t.eq(cps.get("SBPMapSettings", "CP1X"), "10")
	t.eq(cps.get("SBPMapSettings", "CP1Z"), "20.5")
	t.eq(cps.get("SBPMapSettings", "CP2Name"), "beta")
	t.eq(cps.get("ScrapImpactZone", "SIZ_IncludeSpawnPoints"), "0")

	# write → parse float 10.0 must be Python "10.0"
	BzOdf.write_odf(path, [["pad", 10.0, 1.5]], true)
	var pad: BzTrn.TerrainConfig = BzTrn.read_trn(path)
	t.eq(pad.get("SBPMapSettings", "CP1X"), "10.0", "float str() matches Python")
	t.eq(pad.get("SBPMapSettings", "CP1Z"), "1.5")

	# --- KNOWN_SCRAP_PRJIDS (F8 classLabel=scrap expansion) ---
	t.eq(BzOdf.KNOWN_SCRAP_PRJIDS, ["npscr1", "npscr2", "npscr3", "sscr_1", "blc-pell"])
	t.ok(BzOdf.is_scrap_prjid("npscr1"))
	t.ok(BzOdf.is_scrap_prjid("NPSCR1"), "case-insensitive")
	t.ok(BzOdf.is_scrap_prjid("sscr_1"))
	t.ok(BzOdf.is_scrap_prjid("blc-pell"))
	t.ok(not BzOdf.is_scrap_prjid("eggeizr1"))
	t.ok(not BzOdf.is_scrap_prjid(""))

	var fixture := ProjectSettings.globalize_path("res://tests/gd/fixtures/odf/bare.txt")
	if FileAccess.file_exists(fixture):
		_eq_bytes(t, fixture, bare_want, "checked-in bare ODF golden")


func _work_dir() -> String:
	var d := OS.get_cache_dir().path_join("bz_odf_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _eq_bytes(t, path: String, want: String, msg: String) -> void:
	var got := FileAccess.get_file_as_bytes(path).get_string_from_utf8()
	t.eq(got, want, msg)
