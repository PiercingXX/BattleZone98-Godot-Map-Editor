extends RefCounted
## Material swatches crop the world's solid atlas tiles, not dummy origin UVs.


func run(t) -> void:
	var saved_world := MapState.world
	var saved_worlds: Array = MapState.worlds.duplicate(true)
	var tmp: String = OS.get_temp_dir().path_join("bz_mat_thumbs_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var png := _write_atlas(tmp)

	_test_no_world(t)
	_test_crops_solids(t, png)
	_test_skips_default_uv(t, png)
	_test_skips_dds(t, tmp)
	_test_hex_index(t, png)
	_test_elysium_type4(t, png)
	_test_solid_tile_field(t, png)
	_test_cap_fallback_icon(t, png)
	_test_transition_catalog(t, png)
	await _test_panel_fills_swatch(t, png)

	_rm_rf(tmp)
	MapState.world = saved_world
	MapState.worlds = saved_worlds


func _test_no_world(t) -> void:
	MapState.world = ""
	MapState.worlds = []
	var thumbs: Array = MaterialPalette.material_thumbnails(16)
	t.eq(thumbs.size(), 16)
	for i in 16:
		t.eq(thumbs[i], null, "no world → no thumb %d" % i)


func _test_crops_solids(t, png: String) -> void:
	_set_world(png, {
		"MA00SA0.MAP": [0.0, 0.0, 0.125, 0.125],
		"MA11SA0.MAP": [0.125, 0.0, 0.125, 0.125],
	})
	var thumbs: Array = MaterialPalette.material_thumbnails(16)
	t.eq(thumbs.size(), 16)
	t.ok(thumbs[0] is ImageTexture, "mat 0 has a solid tile")
	t.ok(thumbs[1] is ImageTexture, "mat 1 has a solid tile")
	t.eq(thumbs[2], null, "mat 2 has no CSV solid")
	_assert_near(t, _center(thumbs[0]), Color(1, 0, 0), "mat 0 is the red tile")
	_assert_near(t, _center(thumbs[1]), Color(0, 1, 0), "mat 1 is the green tile")
	if thumbs[0] is ImageTexture:
		t.eq((thumbs[0] as ImageTexture).get_width(), 16)
		t.eq((thumbs[0] as ImageTexture).get_height(), 16)


func _test_skips_default_uv(t, png: String) -> void:
	# tile_uvs defaults to the origin square; without atlas_tiles that would
	# paint every unused slot with material 0's texture.
	MapState.world = "mars"
	MapState.worlds = [{
		"id": "mars",
		"atlas_image": png,
		"tile_uvs": [[0.0, 0.0, 0.125, 0.125]],
		"atlas_tiles": {},
	}]
	var thumbs: Array = MaterialPalette.material_thumbnails(16)
	for i in 16:
		t.eq(thumbs[i], null, "no atlas_tiles → no thumb %d" % i)


func _test_skips_dds(t, tmp: String) -> void:
	var dds: String = tmp.path_join("mars_detail.dds")
	var f := FileAccess.open(dds, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([0, 1, 2, 3]))
	f.close()
	MapState.world = "mars"
	MapState.worlds = [{
		"id": "mars",
		"atlas_image": dds,
		"atlas_tiles": {"MA00SA0.MAP": [0.0, 0.0, 0.125, 0.125]},
	}]
	var thumbs: Array = MaterialPalette.material_thumbnails(16)
	t.eq(thumbs[0], null, "DDS atlas is refused")


func _test_elysium_type4(t, png: String) -> void:
	# Stock Elysium names type 4's fill EL04SA0, not EL44SA0. That's why only
	# four of five chips were getting atlas crops.
	_set_world(png, {
		"EL00SA0.MAP": [0.0, 0.0, 0.125, 0.125],
		"EL11SA0.MAP": [0.125, 0.0, 0.125, 0.125],
		"EL22SA0.MAP": [0.25, 0.25, 0.125, 0.125],
		"EL33SA0.MAP": [0.25, 0.25, 0.125, 0.125],
		"EL04SA0.MAP": [0.375, 0.0, 0.125, 0.125],
	})
	MapState.world = "elysium"
	MapState.worlds[0]["id"] = "elysium"
	var thumbs: Array = MaterialPalette.material_thumbnails(16)
	t.ok(thumbs[0] is ImageTexture, "type 0 EL00SA0")
	t.ok(thumbs[1] is ImageTexture, "type 1 EL11SA0")
	t.ok(thumbs[4] is ImageTexture, "type 4 EL04SA0 (not EL44SA0)")
	_assert_near(t, _center(thumbs[4]), Color(1, 1, 0), "type 4 is the yellow tile")
	t.eq(thumbs[5], null, "no sixth solid")


func _test_solid_tile_field(t, png: String) -> void:
	MapState.world = "elysium"
	MapState.worlds = [{
		"id": "elysium",
		"atlas_image": png,
		"atlas_tiles": {"EL04SA0.MAP": [0.375, 0.0, 0.125, 0.125]},
		"texture_types": [
			{"index": 4, "solid_tile": "el04sa0.map", "flat_color": [201, 201, 201]},
		],
	}]
	var thumbs: Array = MaterialPalette.material_thumbnails(16)
	t.ok(thumbs[4] is ImageTexture, "SolidA0 name resolves without {i}{i} alias")
	_assert_near(t, _center(thumbs[4]), Color(1, 1, 0), "SolidA0 crop is the yellow tile")


func _test_cap_fallback_icon(t, png: String) -> void:
	# Material 1 often has no `{i}{i}SA0` — only a cap that names it (MA01CA0).
	_set_world(png, {
		"MA00SA0.MAP": [0.0, 0.0, 0.125, 0.125],
		"MA01CA0.MAP": [0.125, 0.0, 0.125, 0.125],
		"MA04DA0.MAP": [0.375, 0.0, 0.125, 0.125],
	})
	var thumbs: Array = MaterialPalette.material_thumbnails(16)
	t.ok(thumbs[0] is ImageTexture, "mat 0 still uses the solid")
	t.ok(thumbs[1] is ImageTexture, "mat 1 uses the 0→1 cap")
	_assert_near(t, _center(thumbs[1]), Color(0, 1, 0), "cap crop is the green tile")
	t.ok(thumbs[4] is ImageTexture, "mat 4 uses the 0→4 diagonal")
	_assert_near(t, _center(thumbs[4]), Color(1, 1, 0), "diag crop is the yellow tile")
	t.eq(thumbs[2], null, "mat 2 still has no atlas tile")


func _test_hex_index(t, png: String) -> void:
	_set_world(png, {
		"MAAASA0.MAP": [0.25, 0.25, 0.125, 0.125],
	})
	var thumbs: Array = MaterialPalette.material_thumbnails(16)
	t.ok(thumbs[10] is ImageTexture, "mat 10 uses hex SA0 key")
	_assert_near(t, _center(thumbs[10]), Color(0, 0, 1), "mat 10 is the blue tile")
	t.eq(thumbs[0], null)


func _test_panel_fills_swatch(t, png: String) -> void:
	_set_world(png, {
		"MA00SA0.MAP": [0.0, 0.0, 0.125, 0.125],
		"MA11SA0.MAP": [0.125, 0.0, 0.125, 0.125],
	})
	MapState.worlds[0]["texture_types"] = [
		{"index": 0, "name": "Sand", "flat_color": [140, 90, 60]},
		{"index": 1, "name": "Rock", "flat_color": [20, 200, 20]},
	]
	var pal: Node = load("res://project/ui/palette/PalettePanel.tscn").instantiate()
	t.tree.root.add_child(pal)
	await t.tree.process_frame
	pal.refresh_swatches()
	var swatches: GridContainer = pal.find_child("Swatches", true, false)
	t.eq(swatches.get_child_count(), 16)
	var b0: Button = swatches.get_child(0)
	var thumb0 := b0.get_node_or_null("Thumb") as TextureRect
	t.ok(thumb0 != null and thumb0.visible, "mat 0 swatch shows the atlas crop")
	t.ok(thumb0.texture is Texture2D)
	var sb0 := b0.get_theme_stylebox("normal") as StyleBoxFlat
	t.ok(sb0 != null and sb0.bg_color.a == 0.0, "atlas swatch stylebox is a ring")
	t.eq(b0.custom_minimum_size, Vector2(35, 35))
	var b2: Button = swatches.get_child(2)
	var thumb2 := b2.get_node_or_null("Thumb") as TextureRect
	t.ok(thumb2 != null and not thumb2.visible, "unused slot stays a colour chip")
	var sb2 := b2.get_theme_stylebox("normal") as StyleBoxFlat
	t.ok(sb2 != null and sb2.bg_color.a > 0.5, "unused slot keeps flat_color")
	pal.queue_free()
	await t.tree.process_frame


func _test_transition_catalog(t, png: String) -> void:
	_set_world(png, {
		"MA00SA0.MAP": [0.0, 0.0, 0.125, 0.125],
		"MA01CA0.MAP": [0.5, 0.0, 0.125, 0.125],
		"MA01CB0.MAP": [0.625, 0.0, 0.125, 0.125],
		"MA01DA0.MAP": [0.0, 0.125, 0.125, 0.125],
		"MA04CA0.MAP": [0.75, 0.0, 0.125, 0.125],
	})
	t.ok(MaterialPalette.catalog_known())
	t.ok(MaterialPalette.has_kind_for(0, "cap"), "mat 0 has caps")
	t.ok(MaterialPalette.has_kind_for(0, "diag"), "mat 0 has a corner")
	t.ok(not MaterialPalette.has_kind_for(1, "cap"), "mat 1 has no caps as base")
	t.ok(MaterialPalette.has_transition(0, 1, "cap"))
	t.ok(MaterialPalette.has_transition(0, 4, "cap"))
	t.ok(not MaterialPalette.has_transition(0, 2, "cap"), "no 0→2 cap")
	t.ok(not MaterialPalette.has_transition(0, 4, "diag"), "0→4 is cap only")
	var caps: PackedInt32Array = MaterialPalette.transition_partners(0, "cap")
	t.eq(caps.size(), 2)
	t.ok(caps.has(1) and caps.has(4))
	var vars: PackedInt32Array = MaterialPalette.variants_for(0, 1, "cap")
	t.ok(vars.has(0) and vars.has(1), "0→1 cap has A and B")
	t.eq(MaterialPalette.variants_for(0, 1, "diag"), PackedInt32Array([0]))


func _set_world(png: String, tiles: Dictionary) -> void:
	MapState.world = "mars"
	MapState.worlds = [{
		"id": "mars",
		"atlas_image": png,
		"atlas_tiles": tiles,
	}]


func _write_atlas(tmp: String) -> String:
	# 64×64, 8×8 tiles of 8 px. Tile (0,0) red, (1,0) green, (2,2) blue.
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.1))
	img.fill_rect(Rect2i(0, 0, 8, 8), Color(1, 0, 0))
	img.fill_rect(Rect2i(8, 0, 8, 8), Color(0, 1, 0))
	img.fill_rect(Rect2i(16, 16, 8, 8), Color(0, 0, 1))
	img.fill_rect(Rect2i(24, 0, 8, 8), Color(1, 1, 0))
	var path: String = tmp.path_join("mars_atlas.png")
	img.save_png(path)
	return path


func _center(tex: Variant) -> Color:
	if not tex is ImageTexture:
		return Color(0, 0, 0, 0)
	var img: Image = (tex as ImageTexture).get_image()
	if img == null or img.get_width() < 1:
		return Color(0, 0, 0, 0)
	return img.get_pixel(img.get_width() / 2, img.get_height() / 2)


func _assert_near(t, got: Color, want: Color, msg: String) -> void:
	var ok := (
		absf(got.r - want.r) < 0.08
		and absf(got.g - want.g) < 0.08
		and absf(got.b - want.b) < 0.08
	)
	t.ok(ok, "%s (got %s)" % [msg, got])


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
