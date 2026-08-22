extends RefCounted
## Thumbnail cache keying, invalidation, and the two ways this feature is
## allowed to be absent: no game install (no converted mesh → proxy icon
## stands) and no renderer (headless → nothing is queued at all).
##
## Synthetic files only. This machine has no BZ98 install and no GPU, which
## is exactly the state these paths have to survive.


func run(t) -> void:
	var tmp := OS.get_temp_dir().path_join("bz_thumbs_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)

	_test_source_key(t, tmp)
	_test_file_stem(t)
	_test_paths(t, tmp)
	_test_index_roundtrip(t, tmp)
	_test_blank_detection(t)
	_test_needs_render(t, tmp)
	_test_rig(t)
	_test_gltf_roundtrip(t, tmp)
	await _test_headless_degrades(t, tmp)
	await _test_proxy_fallback(t, tmp)
	await _test_rendered_beats_proxy(t, tmp)
	_test_assets_helpers(t, tmp)

	_rmtree(tmp)


func _test_source_key(t, tmp: String) -> void:
	t.eq(ThumbnailCache.source_key(""), "", "no mesh → no key")
	t.eq(ThumbnailCache.source_key(tmp.path_join("absent.glb")), "",
		"missing mesh → no key")
	var glb := tmp.path_join("meshes").path_join("avtank.glb")
	_write(glb, "glTF-ish")
	var key := ThumbnailCache.source_key(glb)
	t.ok(not key.is_empty(), "converted mesh has a key")
	t.eq(ThumbnailCache.source_key(glb), key, "key is stable for one file")
	# Size is part of the digest, so a reconvert inside one mtime tick still
	# invalidates.
	_write(glb, "glTF-ish but longer after a reconvert")
	t.ne(ThumbnailCache.source_key(glb), key, "changed mesh → changed key")


func _test_file_stem(t) -> void:
	var stem := ThumbnailCache.file_stem("avtank")
	t.ok(stem.begins_with("avtank-"), "stem keeps the readable prjid")
	t.eq(ThumbnailCache.file_stem("AVTANK"), stem, "case-insensitive")
	# ODF stems are user data; the filename has to be legal on Windows too.
	var messy := ThumbnailCache.file_stem("a/b\\c:d*e?.odf")
	for i in messy.length():
		var ch := messy[i]
		var legal := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") \
			or ch == "_" or ch == "-"
		t.ok(legal, "stem char %s is filename-safe" % ch)
	t.ne(ThumbnailCache.file_stem("a.b"), ThumbnailCache.file_stem("a_b"),
		"sanitised prjids do not collide")


func _test_paths(t, tmp: String) -> void:
	t.eq(ThumbnailCache.dir_for(""), "", "no cache dir → no thumb dir")
	t.eq(ThumbnailCache.png_path("", "avtank"), "", "no cache dir → no png")
	var png := ThumbnailCache.png_path(tmp, "avtank")
	t.eq(png.get_base_dir(), ThumbnailCache.dir_for(tmp), "png lives in thumbs/")
	t.ok(png.ends_with(".png"))
	# C14: derived from game assets, so it must sit under the cache dir the
	# repo already gitignores — never inside the project.
	t.ok(ThumbnailCache.dir_for(tmp).begins_with(tmp), "thumbs stay in cache")
	t.eq(BzAssets.thumbnail_dir(tmp), ThumbnailCache.dir_for(tmp),
		"BzAssets and the cache agree on where thumbs go")


func _test_index_roundtrip(t, tmp: String) -> void:
	var cache := tmp.path_join("cache_index")
	var index := ThumbnailCache.load_index(cache, 96)
	t.eq(index.get("entries", null), {}, "absent index starts empty")
	ThumbnailCache.set_entry(index, "AVTANK", "deadbeef")
	t.ok(ThumbnailCache.is_current(index, "avtank", "deadbeef"), "entry matches")
	t.ok(not ThumbnailCache.is_current(index, "avtank", "other"),
		"a different mesh is stale")
	t.ok(not ThumbnailCache.is_current(index, "avtank", ""), "no key is never current")
	t.ok(ThumbnailCache.save_index(cache, index), "index writes")

	var again := ThumbnailCache.load_index(cache, 96)
	t.ok(ThumbnailCache.is_current(again, "avtank", "deadbeef"), "entry survives")
	# One PNG per class holds exactly one size, so a resize invalidates all.
	var resized := ThumbnailCache.load_index(cache, 128)
	t.ok(not ThumbnailCache.is_current(resized, "avtank", "deadbeef"),
		"a different cell size regenerates")

	ThumbnailCache.drop_entry(again, "avtank")
	t.ok(not ThumbnailCache.is_current(again, "avtank", "deadbeef"), "entry dropped")

	_write(ThumbnailCache.index_path(cache), "{ not json")
	var broken := ThumbnailCache.load_index(cache, 96)
	t.eq(broken.get("entries", null), {}, "a corrupt index just regenerates")


func _test_blank_detection(t) -> void:
	t.ok(ThumbnailCache.is_blank(null), "null is blank")
	var clear := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	clear.fill(Color(0, 0, 0, 0))
	t.ok(ThumbnailCache.is_blank(clear), "a never-rendered frame is blank")
	var flat := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	flat.fill(Color(0.2, 0.3, 0.4, 1))
	t.ok(ThumbnailCache.is_blank(flat), "one flat colour is blank")
	var drawn := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	drawn.fill(Color(0, 0, 0, 0))
	for y in range(4, 12):
		for x in range(4, 12):
			drawn.set_pixel(x, y, Color(0.9, 0.5, 0.1, 1))
	t.ok(not ThumbnailCache.is_blank(drawn), "a framed shape is not blank")


func _test_needs_render(t, tmp: String) -> void:
	var cache := tmp.path_join("cache_needs")
	var glb := tmp.path_join("meshes2").path_join("avtank.glb")
	_write(glb, "mesh bytes")
	var index := ThumbnailCache.load_index(cache, 96)
	var rec := {"prjid": "avtank", "mesh": glb}

	t.ok(ThumbnailService.needs_render(index, cache, rec), "uncached → render")
	t.ok(not ThumbnailService.needs_render(index, "", rec), "no cache dir → never")
	t.ok(not ThumbnailService.needs_render(index, cache, {"prjid": "x", "mesh": ""}),
		"no converted mesh → proxy stands, nothing to render")
	t.ok(not ThumbnailService.needs_render(index, cache, {"mesh": glb}),
		"no prjid → nothing to key on")

	# Simulate a completed render.
	var png := ThumbnailCache.png_path(cache, "avtank")
	t.ok(ThumbnailCache.write_png(png, _checkerboard(96)), "thumbnail writes")
	ThumbnailCache.set_entry(index, "avtank", ThumbnailCache.source_key(glb))
	t.ok(not ThumbnailService.needs_render(index, cache, rec), "cached → skip")

	# The mesh gets reconverted: the PNG is now stale.
	_write(glb, "mesh bytes, rebuilt from a newer .msh")
	t.ok(ThumbnailService.needs_render(index, cache, rec), "stale mesh → re-render")

	# The PNG is deleted but the index still claims it: also a miss.
	ThumbnailCache.set_entry(index, "avtank", ThumbnailCache.source_key(glb))
	t.ok(not ThumbnailService.needs_render(index, cache, rec), "re-keyed → skip")
	DirAccess.remove_absolute(png)
	t.ok(ThumbnailService.needs_render(index, cache, rec), "missing png → render")


func _test_rig(t) -> void:
	## The rig is the reproducibility contract. It is also the one part a
	## GPU-less machine can still inspect: wiring, not pixels.
	var vp := ThumbnailService.build_viewport(4, 3, 96)
	t.eq(vp.size, Vector2i(384, 288), "grid fills the viewport exactly")
	t.ok(vp.own_world_3d, "own World3D — editor lighting cannot leak into an icon")
	t.ok(vp.transparent_bg, "icons composite over the palette")
	t.eq(vp.render_target_update_mode, SubViewport.UPDATE_DISABLED,
		"nothing renders until a batch asks for one frame")
	var cams := 0
	var lights := 0
	var envs := 0
	for child in vp.get_children():
		if child is Camera3D:
			cams += 1
			var cam := child as Camera3D
			t.eq(cam.projection, Camera3D.PROJECTION_ORTHOGONAL,
				"orthogonal: every cell of a batch gets the same lens")
			t.eq(cam.keep_aspect, Camera3D.KEEP_HEIGHT)
			t.near(cam.size, 3.0, 0.0001, "one world unit per cell row")
			t.ok(cam.current, "the batch camera is the active one")
			t.ok(cam.far > cam.transform.origin.z, "the grid is inside the frustum")
		elif child is DirectionalLight3D:
			lights += 1
		elif child is WorldEnvironment:
			envs += 1
			var env := (child as WorldEnvironment).environment
			t.ok(env != null and env.ambient_light_energy > 0.0,
				"ambient fill so unlit faces keep their silhouette")
	t.eq(cams, 1, "exactly one camera")
	t.eq(lights, 2, "key and fill")
	t.eq(envs, 1, "one environment")
	vp.free()


func _test_gltf_roundtrip(t, tmp: String) -> void:
	## Framing has to hold against a real glTF tree, not just hand-built
	## nodes: the converted assets arrive as a generated scene with its own
	## node nesting, and that is what the AABB walk sees.
	var glb := tmp.path_join("roundtrip").path_join("box.glb")
	if not _export_box_glb(glb, Vector3(2, 6, 4), Vector3(20, -3, 8)):
		t.ok(true, "glTF export unavailable here; framing covered synthetically")
		return
	var node := ThumbnailService.load_mesh_scene(glb)
	t.ok(node != null, "converted mesh loads as a detached scene")
	if node == null:
		return
	var box := ThumbnailFraming.visual_aabb(node)
	t.near(box.size.x, 2.0, 0.001, "glTF aabb keeps the modelled width")
	t.near(box.size.y, 6.0, 0.001, "glTF aabb keeps the modelled height")
	t.near(box.get_center().x, 20.0, 0.001, "offset survives the node nesting")
	var framed: AABB = ThumbnailFraming.fit_transform(
		box, ThumbnailFraming.view_basis(), ThumbnailGrid.cell_center(5, 4, 3)
	) * box
	var want := ThumbnailGrid.cell_center(5, 4, 3)
	t.near(framed.get_center().x, want.x, 0.001, "real mesh frames into its cell")
	t.near(framed.get_center().y, want.y, 0.001, "real mesh frames into its cell")
	t.near(maxf(framed.size.x, framed.size.y), 0.8, 0.001, "and fills it")
	node.free()
	t.eq(ThumbnailService.load_mesh_scene(tmp.path_join("absent.glb")), null,
		"a missing mesh is a miss, not a crash")
	t.eq(ThumbnailService.load_mesh_scene(""), null, "no path is a miss")


func _test_headless_degrades(t, tmp: String) -> void:
	## No GPU, no display server: the feature has to be absent, not broken.
	var cache := tmp.path_join("cache_headless")
	var svc := ThumbnailService.new()
	t.tree.root.add_child(svc)
	await t.tree.process_frame
	svc.configure(cache, 96)

	var glb := tmp.path_join("meshes3").path_join("avtank.glb")
	_write(glb, "mesh bytes")
	var queued: int = svc.request([{"prjid": "avtank", "mesh": glb}])
	if ThumbnailService.is_supported():
		t.ok(queued >= 0, "renderer present: queueing is allowed")
	else:
		t.eq(queued, 0, "no renderer → nothing queued")
		t.eq(svc.pending(), 0, "queue stays empty")
		t.ok(not svc.is_busy(), "nothing runs")
		t.ok(not FileAccess.file_exists(ThumbnailCache.index_path(cache)),
			"no renderer → no cache writes at all")
	t.eq(svc.texture_for("avtank"), null, "nothing rendered yet")
	t.eq(svc.texture_for(""), null, "empty prjid is not a lookup")

	svc.cancel()
	t.eq(svc.pending(), 0, "cancel drains the queue")

	# No cache dir configured at all — the first-run state before probe.
	var bare := ThumbnailService.new()
	t.tree.root.add_child(bare)
	await t.tree.process_frame
	t.eq(bare.request([{"prjid": "avtank", "mesh": glb}]), 0, "no cache dir → no work")
	t.eq(bare.icon_for({"prjid": "avtank", "icon": "icons/avtank.png"}), null,
		"no cache dir → no icon, no crash")
	bare.queue_free()
	svc.queue_free()
	await t.tree.process_frame


func _test_proxy_fallback(t, tmp: String) -> void:
	## The proxy rung is what every unconverted class shows. Adding real
	## thumbnails must not take it away.
	var cache := tmp.path_join("cache_proxy")
	_write_png(cache.path_join("icons").path_join("avtank.png"), _checkerboard(64))
	var svc := ThumbnailService.new()
	t.tree.root.add_child(svc)
	await t.tree.process_frame
	svc.configure(cache, 96)

	var tex: Texture2D = svc.icon_for({"prjid": "avtank", "icon": "icons/avtank.png"})
	t.ok(tex != null, "unconverted class still gets its proxy icon")
	if tex != null:
		t.eq(tex.get_width(), 64, "that icon is the 64 px proxy")
	t.eq(svc.icon_for({"prjid": "nosuch", "icon": "icons/nosuch.png"}), null,
		"no proxy on disk → null, not a crash")
	t.eq(svc.icon_for({}), null, "no prjid → null")
	svc.queue_free()
	await t.tree.process_frame


func _test_rendered_beats_proxy(t, tmp: String) -> void:
	var cache := tmp.path_join("cache_both")
	_write_png(cache.path_join("icons").path_join("avtank.png"), _checkerboard(64))
	_write_png(ThumbnailCache.png_path(cache, "avtank"), _checkerboard(96))
	var index := ThumbnailCache.load_index(cache, 96)
	ThumbnailCache.set_entry(index, "avtank", "somekey")
	ThumbnailCache.save_index(cache, index)

	var svc := ThumbnailService.new()
	t.tree.root.add_child(svc)
	await t.tree.process_frame
	svc.configure(cache, 96)
	var tex: Texture2D = svc.icon_for({"prjid": "avtank", "icon": "icons/avtank.png"})
	t.ok(tex != null, "cached render is found")
	if tex != null:
		t.eq(tex.get_width(), 96, "the rendered 96 px thumbnail wins")
	var direct: Texture2D = svc.texture_for("AVTANK")
	t.ok(direct != null, "lookup is case-insensitive")

	# A cell-size change must not serve the wrong-size PNG.
	var other := ThumbnailService.new()
	t.tree.root.add_child(other)
	await t.tree.process_frame
	other.configure(cache, 128)
	t.eq(other.texture_for("avtank"), null, "resize invalidates the cached png")
	other.queue_free()
	svc.queue_free()
	await t.tree.process_frame


func _test_assets_helpers(t, tmp: String) -> void:
	t.eq(BzAssets.thumbnail_dir(""), "", "no cache dir → no thumb dir")
	t.eq(BzAssets.cached_mesh_path("avtank", ""), "", "no cache dir → no mesh")
	t.eq(BzAssets.thumbnail_candidates({}), [], "no index → nothing to render")
	t.eq(BzAssets.thumbnail_candidates({"classes": "not an array"}), [])

	var cache := tmp.path_join("cache_assets")
	t.eq(BzAssets.cached_mesh_path("avtank", cache), "", "unconverted class")
	_write(cache.path_join("meshes").path_join("avtank.glb"), "mesh bytes")
	t.ne(BzAssets.cached_mesh_path("AVTANK", cache), "", "converted class, any case")

	var index := {"classes": [
		{"prjid": "avtank", "mesh": "", "mesh_fidelity": "proxy", "icon": "icons/avtank.png"},
		{"prjid": "apwalk", "mesh": tmp.path_join("nope.glb"), "mesh_fidelity": "hd"},
		{"prjid": "", "mesh": ""},
		"junk",
	]}
	var cands := BzAssets.thumbnail_candidates(index, cache)
	t.eq(cands.size(), 1, "only the class with a mesh on disk is a candidate")
	t.eq(str((cands[0] as Dictionary).get("prjid", "")), "avtank")
	t.eq(str((cands[0] as Dictionary).get("icon", "")), "icons/avtank.png",
		"the proxy icon rides along for the fallback")

	var counts := BzAssets.fidelity_counts(index)
	t.eq(int(counts.get("total", 0)), 3, "junk entries are not classes")
	t.eq(int(counts.get("hd", 0)), 1)
	t.eq(int(counts.get("proxy", 0)), 2)
	t.eq(int(BzAssets.fidelity_counts({}).get("total", -1)), 0, "no index → zeroes")


# --- helpers -----------------------------------------------------------------

func _checkerboard(size: int) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var on := ((x / 8) + (y / 8)) % 2 == 0
			img.set_pixel(x, y, Color(0.9, 0.4, 0.1, 1) if on else Color(0, 0, 0, 0))
	return img


func _export_box_glb(path: String, size: Vector3, at: Vector3) -> bool:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	var root := Node3D.new()
	root.add_child(mi)
	mi.owner = root
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var ok := doc.append_from_scene(root, state) == OK \
		and doc.write_to_filesystem(state, path) == OK
	root.free()
	return ok and FileAccess.file_exists(path)


func _write(path: String, body: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(body)


func _write_png(path: String, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)


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
