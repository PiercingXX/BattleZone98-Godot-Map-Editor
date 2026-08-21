extends RefCounted
## BzWorlds: synthetic Edit/trn templates, stock order, error paths.


func run(t) -> void:
	var tmp: String = OS.get_temp_dir().path_join("bz_worlds_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	_test_errors(t, tmp)
	_test_success(t, tmp)
	_test_solid_a0(t, tmp)
	_test_flat_color(t)
	_rm_rf(tmp)


func _test_errors(t, tmp: String) -> void:
	var missing: Dictionary = BzWorlds.worlds_from_game(tmp.path_join("nogame"))
	t.ok(BzErrors.is_err(missing), "no Edit/trn → error")
	t.eq(missing["error"].get("code"), "no_trn_templates")
	t.ok(str(missing["error"].get("message", "")).contains("no Edit/trn directory"))
	t.eq(missing["error"].get("hint"), "the game install is missing its terrain templates")
	t.ok(str(missing["error"].get("path", "")).ends_with("Edit/trn") or str(missing["error"].get("path", "")).ends_with("Edit\\trn"))

	var empty_root: String = tmp.path_join("emptygame")
	DirAccess.make_dir_recursive_absolute(empty_root.path_join("Edit").path_join("trn"))
	var empty: Dictionary = BzWorlds.worlds_from_game(empty_root)
	t.ok(BzErrors.is_err(empty), "empty Edit/trn → error")
	t.eq(empty["error"].get("code"), "no_trn_templates")
	t.ok(str(empty["error"].get("message", "")).contains("contains no .trn files"))


func _test_success(t, tmp: String) -> void:
	var game: String = tmp.path_join("game")
	var trn_dir: String = game.path_join("Edit").path_join("trn")
	DirAccess.make_dir_recursive_absolute(trn_dir)
	_write_text(
		trn_dir.path_join("mars.trn"),
		"[Size]\r\nWidth = 1280\r\nDepth = 1280\r\n"
		+ "[Atlases]\r\nMaterialName = mars_detail_atlas\r\n"
		+ "[Sky]\r\nSkyTexture = mars.map\r\n"
		+ "[TextureType0] // Sandy\r\nFlatColor = 140 90 60\r\n"
		+ "[TextureType1] Lava Pool\r\nFlatColor = 200\r\n"
	)
	_write_text(trn_dir.path_join("elysium.trn"), "[Atlases]\r\nMaterialName = elysium_atlas\r\n[Sky]\r\nSkyType = clear\r\n")
	_write_text(trn_dir.path_join("zzmod.trn"), "[Size]\r\nWidth = 1280\r\n")
	_write_text(trn_dir.path_join("readme.txt"), "not a trn")
	var pm: String = game.path_join("Edit").path_join("PlanetMaterials")
	DirAccess.make_dir_recursive_absolute(pm)
	_write_text(
		pm.path_join("mars_detail_atlas.csv"),
		"MA00SA0.MAP,0.0,0.0,0.125,0.125\nMA11SA0.MAP,0.125,0.0,0.125,0.125\n"
	)
	var png_dir: String = game.path_join("Edit").path_join("Detail_PNG")
	DirAccess.make_dir_recursive_absolute(png_dir)
	_write_bytes(png_dir.path_join("mars_detail.png"), PackedByteArray([0x89, 0x50, 0x4E, 0x47]))

	var result: Dictionary = BzWorlds.worlds_from_game(game)
	t.eq(result.get("ok"), true, "worlds ok")
	t.ok(result.has("worlds"), "verb payload has worlds")
	var worlds: Array = result.get("worlds", [])
	t.eq(worlds.size(), 3, "elysium + mars + extra zzmod")
	if worlds.size() < 3:
		return
	var ids: Array = []
	for w in worlds:
		ids.append(w.get("id"))
	t.eq(ids[0], "elysium", "stock worlds first (elysium before mars)")
	t.eq(ids[1], "mars")
	t.eq(ids[2], "zzmod", "mod templates after the stock nine")

	var mars: Dictionary = worlds[1]
	t.eq(mars.get("label"), "Mars")
	t.eq(mars.get("trn_template"), "Edit/trn/mars.trn")
	t.eq(mars.get("atlas"), "mars_detail_atlas")
	t.eq(mars.get("sky"), "mars.map")
	t.eq(mars.get("atlas_image"), png_dir.path_join("mars_detail.png"))
	var uvs: Array = mars.get("tile_uvs", [])
	t.eq(uvs.size(), 16, "16 tile UVs")
	t.eq(uvs[0], [0.0, 0.0, 0.125, 0.125])
	t.eq(uvs[1], [0.125, 0.0, 0.125, 0.125])
	t.eq(uvs[2], [0.0, 0.0, 0.125, 0.125], "missing CSV row keeps default")
	var types: Array = mars.get("texture_types", [])
	t.eq(types.size(), 2)
	t.eq(types[0].get("index"), 0)
	t.eq(types[0].get("flat_color"), [140, 90, 60])
	t.eq(types[0].get("label"), "Sandy")
	t.eq(types[1].get("index"), 1)
	t.eq(types[1].get("flat_color"), [200, 200, 200])
	t.eq(types[1].get("label"), "Lava Pool")

	var ely: Dictionary = worlds[0]
	t.eq(ely.get("sky"), "clear", "SkyType fallback when SkyTexture absent")

	t.eq(BzWorlds.STOCK_WORLDS.size(), 9)
	t.eq(BzWorlds.STOCK_WORLDS[0], "achilles")
	t.eq(BzWorlds.STOCK_WORLDS[8], "venus")


func _test_solid_a0(t, tmp: String) -> void:
	var game: String = tmp.path_join("elysium_solids")
	var trn_dir: String = game.path_join("Edit").path_join("trn")
	DirAccess.make_dir_recursive_absolute(trn_dir)
	_write_text(
		trn_dir.path_join("elysium.trn"),
		"[Atlases]\r\nMaterialName = el_detail_atlas\r\n"
		+ "[TextureType0] // Packed Dirt\r\nFlatColor = 201\r\nSolidA0 = el00sa0.map\r\n"
		+ "[TextureType4] // Base Grid-iron\r\nFlatColor = 201\r\nSolidA0 = el04sa0.map\r\n"
	)
	var pm: String = game.path_join("Edit").path_join("PlanetMaterials")
	DirAccess.make_dir_recursive_absolute(pm)
	_write_text(
		pm.path_join("el_detail_atlas.csv"),
		"EL00SA0.MAP,0.125,0.0,0.125,0.125\nEL04SA0.MAP,0.375,0.25,0.125,0.125\n"
	)
	var result: Dictionary = BzWorlds.worlds_from_game(game)
	t.eq(result.get("ok"), true)
	var worlds: Array = result.get("worlds", [])
	t.eq(worlds.size(), 1)
	var ely: Dictionary = worlds[0]
	var types: Array = ely.get("texture_types", [])
	t.eq(types.size(), 2)
	t.eq(types[0].get("solid_tile"), "el00sa0.map")
	t.eq(types[1].get("index"), 4)
	t.eq(types[1].get("solid_tile"), "el04sa0.map")
	var uvs: Array = ely.get("tile_uvs", [])
	t.eq(uvs[0], [0.125, 0.0, 0.125, 0.125], "type 0 uses SolidA0 UV")
	t.eq(uvs[4], [0.375, 0.25, 0.125, 0.125], "type 4 uses EL04SA0, not a dummy origin")
	var tiles: Dictionary = ely.get("atlas_tiles", {})
	t.eq(tiles.get("EL44SA0.MAP"), [0.375, 0.25, 0.125, 0.125], "alias {i}{i}SA0 for the LUT")


func _test_flat_color(t) -> void:
	t.eq(BzWorlds._parse_flat_color("140 90 60"), [140, 90, 60])
	t.eq(BzWorlds._parse_flat_color("200"), [200, 200, 200])
	t.eq(BzWorlds._parse_flat_color(""), [128, 128, 128])
	t.eq(BzWorlds._parse_flat_color("x"), [128, 128, 128])


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(text.to_utf8_buffer())
	f.close()


func _write_bytes(path: String, buf: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(buf)
	f.close()


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
