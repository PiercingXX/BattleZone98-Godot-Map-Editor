extends RefCounted
## BzIni: write, parse back as INI, write→parse, byte match vs Python golden.


func run(t) -> void:
	var work := _work_dir()
	var path := work.path_join("map.ini")

	# --- write default (pack-matching K / 14) ---
	BzIni.write_ini(path, "Silver Pools")
	var default_want := (
		"[DESCRIPTION]\r\n"
		+ "missionName = \"Silver Pools\"\r\n"
		+ "\r\n"
		+ "[WORKSHOP]\r\n"
		+ ";mapType = \"instant_action\"\r\n"
		+ "mapType = \"multiplayer\"\r\n"
		+ "customtags = \"\"\r\n"
		+ "\r\n"
		+ "[MULTIPLAYER]\r\n"
		+ "minPlayers = \"1\"\r\n"
		+ "maxPlayers = \"14\"\r\n"
		+ "gameType = \"K\"\r\n"
	)
	_eq_bytes(t, path, default_want, "write_ini defaults match ini.py")

	# parse (INI-shaped — reuse BzTrn)
	var cfg: BzTrn.TerrainConfig = BzTrn.read_trn(path)
	t.eq(cfg.get("DESCRIPTION", "missionName"), "\"Silver Pools\"")
	t.eq(cfg.get("WORKSHOP", "mapType"), "\"multiplayer\"")
	t.eq(cfg.get("MULTIPLAYER", "minPlayers"), "\"1\"")
	t.eq(cfg.get("MULTIPLAYER", "maxPlayers"), "\"14\"")
	t.eq(cfg.get("MULTIPLAYER", "gameType"), "\"K\"")
	t.eq(cfg.get("WORKSHOP", "customtags"), "\"\"")

	# --- write → parse with non-defaults ---
	BzIni.write_ini(
		path,
		"Test Map",
		"multiplayer",
		"strategy, small, mars",
		2,
		8,
		"K"
	)
	var tagged_want := (
		"[DESCRIPTION]\r\n"
		+ "missionName = \"Test Map\"\r\n"
		+ "\r\n"
		+ "[WORKSHOP]\r\n"
		+ ";mapType = \"instant_action\"\r\n"
		+ "mapType = \"multiplayer\"\r\n"
		+ "customtags = \"strategy, small, mars\"\r\n"
		+ "\r\n"
		+ "[MULTIPLAYER]\r\n"
		+ "minPlayers = \"2\"\r\n"
		+ "maxPlayers = \"8\"\r\n"
		+ "gameType = \"K\"\r\n"
	)
	_eq_bytes(t, path, tagged_want, "write_ini tagged match ini.py")
	var again: BzTrn.TerrainConfig = BzTrn.read_trn(path)
	t.eq(again.get("DESCRIPTION", "missionName"), "\"Test Map\"")
	t.eq(again.get("WORKSHOP", "customtags"), "\"strategy, small, mars\"")
	t.eq(again.get("MULTIPLAYER", "minPlayers"), "\"2\"")
	t.eq(again.get("MULTIPLAYER", "maxPlayers"), "\"8\"")

	# fixture golden, if present
	var fixture := ProjectSettings.globalize_path("res://tests/gd/fixtures/ini/default.ini")
	if FileAccess.file_exists(fixture):
		_eq_bytes(t, fixture, default_want, "checked-in default.ini golden")


func _work_dir() -> String:
	var d := OS.get_cache_dir().path_join("bz_ini_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _eq_bytes(t, path: String, want: String, msg: String) -> void:
	var got := FileAccess.get_file_as_bytes(path).get_string_from_utf8()
	t.eq(got, want, msg)
