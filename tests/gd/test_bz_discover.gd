extends RefCounted
## Fabricated install trees — never a real game / workshop / corpus path.


func run(t) -> void:
	var tmp := OS.get_temp_dir().path_join("bz_disc_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_isolate()
	_test_parse_vdf(t)
	_test_is_game_install(t, tmp)
	_test_invalid_override(t, tmp)
	_test_override_and_packaged(t, tmp)
	_test_workshop_union(t, tmp)
	_test_steam_injection(t, tmp)
	_test_probe_shape(t, tmp)
	_test_first_game_root(t)
	_test_empty_roots_warns(t)
	_test_live_shape(t)
	_test_linux_roots(t)
	_restore()
	_rmtree(tmp)


func _test_linux_roots(t) -> void:
	if OS.get_name() != "Linux":
		return
	var roots := BzDiscover._linux_steam_roots()
	var joined := "\n".join(roots)
	t.ok("/.steam/steam" in joined, "classic steam root probed")
	t.ok("/.local/share/Steam" in joined, "xdg steam root probed")
	t.ok("com.valvesoftware.Steam" in joined, "flatpak steam root probed")
	t.ok("/snap/steam/common/" in joined, "snap steam root probed")


func _isolate() -> void:
	BzDiscover.test_steam_roots = PackedStringArray()
	BzDiscover.test_gog_installs = PackedStringArray()


func _restore() -> void:
	BzDiscover.test_steam_roots = null
	BzDiscover.test_gog_installs = null


func _test_parse_vdf(t) -> void:
	var text := (
		"\"libraryfolders\"\n{\n"
		+ "\"0\"\n{\n"
		+ "\"path\"\"/home/x/.local/share/Steam\"\n"
		+ "}\n"
		+ "\"1\"\n{\n"
		+ "\"path\"\t\t\"/mnt/games\"\n"
		+ "}\n}\n"
	)
	var paths: Array = BzDiscover.parse_libraryfolders_vdf(text)
	t.eq(paths.size(), 2, "vdf path count")
	t.eq(str(paths[0]), "/home/x/.local/share/Steam", "vdf tight path")
	t.eq(str(paths[1]), "/mnt/games", "vdf spaced path")

	var win: Array = BzDiscover.parse_libraryfolders_vdf("\"path\"\t\"C:\\\\SteamLibrary\"")
	t.eq(win.size(), 1, "vdf windows unescape count")
	t.eq(str(win[0]), "C:\\SteamLibrary", "vdf windows unescape")

	var spaced: Array = BzDiscover.parse_libraryfolders_vdf("\"Path\" \" /foo \"")
	t.eq(spaced.size(), 1, "vdf keeps interior spaces")
	t.eq(str(spaced[0]), " /foo ", "vdf does not strip captured path")


func _test_is_game_install(t, tmp: String) -> void:
	var bare := tmp.path_join("bare")
	DirAccess.make_dir_recursive_absolute(bare)
	t.ok(not BzDiscover.is_game_install(bare), "empty dir is not an install")
	t.ok(not BzDiscover.is_game_install(tmp.path_join("missing")), "missing path")

	var exe_only := tmp.path_join("exe_only")
	DirAccess.make_dir_recursive_absolute(exe_only)
	_touch(exe_only.path_join("battlezone98redux.exe"))
	t.ok(not BzDiscover.is_game_install(exe_only), "exe without models")

	var models_only := tmp.path_join("models_only")
	DirAccess.make_dir_recursive_absolute(
		models_only.path_join("BZ_ASSETS").path_join("common").path_join("models")
	)
	t.ok(not BzDiscover.is_game_install(models_only), "models without exe")

	var ok := tmp.path_join("ok_install")
	_make_install(ok)
	t.ok(BzDiscover.is_game_install(ok), "exe + models is an install")

	var mixed := tmp.path_join("mixed_case")
	DirAccess.make_dir_recursive_absolute(
		mixed.path_join("BZ_ASSETS").path_join("common").path_join("models")
	)
	_touch(mixed.path_join("Battlezone98Redux.EXE"))
	t.ok(BzDiscover.is_game_install(mixed), "exe match is case-insensitive")


func _test_invalid_override(t, tmp: String) -> void:
	var bogus := tmp.path_join("not-an-install")
	DirAccess.make_dir_recursive_absolute(bogus)
	var err := BzDiscover.discover(bogus)
	t.ok(BzErrors.is_err(err), "invalid override is an error")
	var error: Dictionary = err.get("error", {})
	t.eq(str(error.get("code", "")), "install_invalid", "install_invalid code")
	t.ok(str(error.get("message", "")).contains("not a BZ98R install"), "message")
	t.ok(str(error.get("hint", "")).contains("battlezone98redux.exe"), "hint")
	t.ok(str(error.get("path", "")).contains("not-an-install"), "path field")

	var probe_err := BzDiscover.probe(bogus)
	t.ok(BzErrors.is_err(probe_err), "probe invalid override")


func _test_override_and_packaged(t, tmp: String) -> void:
	var inst := tmp.path_join("override_game")
	_make_install(inst)
	var pack := inst.path_join("packaged_mods").path_join("9990001")
	DirAccess.make_dir_recursive_absolute(pack)
	_touch(pack.path_join("synth.odf"))
	_touch(pack.path_join("readme.txt"), "hello")

	var found := BzDiscover.discover(inst)
	t.ok(not BzErrors.is_err(found), "valid override succeeds")
	t.ok(found.has("installs"), "installs key")
	t.ok(found.has("warnings"), "warnings key")
	t.ok(found.has("libraries"), "libraries key")

	var games := _of_kind(found, "game")
	t.eq(games.size(), 1, "one game from override")
	t.eq(str(games[0].get("kind")), "game")
	t.eq(str(games[0].get("platform_hint")), "proton")
	t.ok(str(games[0].get("path", "")).contains("override_game"), "resolved path")
	t.ok(games[0].has("version"), "game has version")

	var items := _of_kind(found, "workshop_item")
	t.eq(items.size(), 1, "packaged_mods item with assets")
	t.eq(str(items[0].get("id")), "9990001")
	t.eq(str(items[0].get("source")), "packaged")
	t.eq(str(items[0].get("name")), "9990001")
	t.eq(int(items[0].get("file_count", 0)), 2, "top-level file count")
	t.ok(int(items[0].get("size_bytes", 0)) > 0, "size_bytes")

	# A packaged dir with no asset-suffix files is skipped.
	var empty_pack := inst.path_join("packaged_mods").path_join("8880001")
	DirAccess.make_dir_recursive_absolute(empty_pack)
	_touch(empty_pack.path_join("notes.txt"), "no assets")
	var again := BzDiscover.discover(inst)
	t.eq(_of_kind(again, "workshop_item").size(), 1, "non-asset pack skipped")


func _test_workshop_union(t, tmp: String) -> void:
	var steam := tmp.path_join("steam_union")
	var inst := steam.path_join("steamapps").path_join("common").path_join("Battlezone 98 Redux")
	_make_install(inst)
	var ws := steam.path_join("steamapps").path_join("workshop").path_join("content").path_join("301650")
	var ws_item := ws.path_join("3406347034")
	DirAccess.make_dir_recursive_absolute(ws_item)
	_touch(ws_item.path_join("ws_only.odf"))
	var both_ws := ws.path_join("5550001")
	DirAccess.make_dir_recursive_absolute(both_ws)
	_touch(both_ws.path_join("from_ws.odf"))
	var both_pkg := inst.path_join("packaged_mods").path_join("5550001")
	DirAccess.make_dir_recursive_absolute(both_pkg)
	_touch(both_pkg.path_join("from_pkg.odf"))

	BzDiscover.test_steam_roots = PackedStringArray([steam])
	BzDiscover.test_gog_installs = PackedStringArray()
	var found := BzDiscover.discover()
	var items := _of_kind(found, "workshop_item")
	var by_id := {}
	for rec in items:
		by_id[str(rec.get("id"))] = rec
	t.ok(by_id.has("3406347034"), "workshop-only id")
	t.eq(str(by_id["3406347034"].get("source")), "workshop")
	t.ok(by_id.has("5550001"), "union id")
	t.eq(str(by_id["5550001"].get("source")), "both")
	t.ok(str(by_id["5550001"].get("path", "")).contains("packaged_mods"), "both prefers packaged")
	BzDiscover.test_steam_roots = PackedStringArray()


func _test_steam_injection(t, tmp: String) -> void:
	var steam := tmp.path_join("steam_root")
	var lib2 := tmp.path_join("lib2")
	var inst := steam.path_join("steamapps").path_join("common").path_join("Battlezone 98 Redux")
	_make_install(inst)
	var acf := steam.path_join("steamapps").path_join("appmanifest_301650.acf")
	_write(acf, "\"AppState\"\n{\n\t\"appid\"\t\t\"301650\"\n\t\"buildid\"\t\t\"1718871\"\n}\n")
	var vdf := steam.path_join("steamapps").path_join("libraryfolders.vdf")
	_write(vdf, "\"libraryfolders\"\n{\n\"0\"\n{\n\"path\"\t\"%s\"\n}\n\"1\"\n{\n\"path\"\t\"%s\"\n}\n}\n" % [steam, lib2])
	DirAccess.make_dir_recursive_absolute(lib2.path_join("steamapps"))

	BzDiscover.test_steam_roots = PackedStringArray([steam])
	var found := BzDiscover.discover()
	var games := _of_kind(found, "game")
	t.eq(games.size(), 1, "steam common install")
	t.eq(str(games[0].get("version")), "1718871", "buildid from appmanifest")
	t.eq(str(games[0].get("platform_hint")), "proton")
	var libs: Array = found.get("libraries", [])
	t.ok(libs.size() >= 1, "libraries listed")
	BzDiscover.test_steam_roots = PackedStringArray()


func _test_probe_shape(t, tmp: String) -> void:
	var inst := tmp.path_join("probe_game")
	_make_install(inst)
	var payload := BzDiscover.probe(inst)
	t.eq(payload.get("ok"), true, "probe ok")
	t.eq(int(payload.get("contract_version", 0)), 1, "contract_version")
	t.eq(str(payload.get("bzmap_version", "")), "0.1.0", "bzmap_version")
	t.ok(payload.has("python"), "frozen python key")
	t.ok(payload.has("installs"), "installs")
	t.ok(payload.has("warnings"), "warnings")
	t.ok(not payload.has("libraries"), "probe drops libraries")
	t.eq(_of_kind(payload, "game").size(), 1, "probe lists override")


func _test_first_game_root(t) -> void:
	t.eq(BzDiscover.first_game_root({"installs": [], "warnings": []}), "", "none")
	var fake := {
		"installs": [
			{"kind": "workshop_item", "path": "/ws", "id": "1"},
			{"kind": "game", "path": "/game/a", "version": "", "platform_hint": "proton"},
			{"kind": "game", "path": "/game/b", "version": "", "platform_hint": "proton"},
		],
		"warnings": [],
	}
	t.eq(BzDiscover.first_game_root(fake), "/game/a", "first game wins")
	var err := BzErrors.err("install_invalid", "nope")
	t.eq(BzDiscover.first_game_root(err), "", "error discovery")


func _test_empty_roots_warns(t) -> void:
	var found := BzDiscover.discover()
	t.ok(not BzErrors.is_err(found), "no-install is not an error")
	t.eq(_of_kind(found, "game").size(), 0, "isolated: no games")
	var warnings: Array = found.get("warnings", [])
	t.ok(warnings.has("no game install found at any default path"), "warning text")


func _test_live_shape(t) -> void:
	# Real OS roots (this machine may or may not have the game). Must not crash
	# and must keep the frozen keys. Do not require an install.
	_restore()
	var found := BzDiscover.discover()
	t.ok(not BzErrors.is_err(found), "live discover returns a dict")
	t.ok(found.get("installs") is Array, "live installs array")
	t.ok(found.get("warnings") is Array, "live warnings array")
	t.ok(found.get("libraries") is Array, "live libraries array")
	for item in found.get("installs", []):
		if typeof(item) != TYPE_DICTIONARY:
			t.fail("install entry is not a dict")
			continue
		var kind := str(item.get("kind", ""))
		t.ok(kind == "game" or kind == "workshop_item", "known kind")
		if kind == "game":
			t.ok(BzDiscover.is_game_install(str(item.get("path", ""))), "listed game is valid")
			t.ok(item.has("platform_hint"), "game platform_hint")
		else:
			t.ok(item.has("id") and item.has("source") and item.has("file_count"), "workshop fields")
	var probe := BzDiscover.probe()
	t.eq(probe.get("ok"), true, "live probe ok")
	t.eq(int(probe.get("contract_version", 0)), 1)
	_isolate()


func _of_kind(found: Dictionary, kind: String) -> Array:
	var out: Array = []
	for item in found.get("installs", []):
		if typeof(item) == TYPE_DICTIONARY and str(item.get("kind", "")) == kind:
			out.append(item)
	return out


func _make_install(root: String) -> void:
	DirAccess.make_dir_recursive_absolute(
		root.path_join("BZ_ASSETS").path_join("common").path_join("models")
	)
	_touch(root.path_join("battlezone98redux.exe"))


func _touch(path: String, body: String = "") -> void:
	_write(path, body)


func _write(path: String, body: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(body)


func _rmtree(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.include_hidden = true
	da.include_navigational = false
	for fname in da.get_files():
		da.remove(fname)
	for dname in da.get_directories():
		_rmtree(path.path_join(dname))
	DirAccess.remove_absolute(path)
