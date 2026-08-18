extends RefCounted
## MapGalleryEnum: fabricated dirs → entries + thumb resolution. No game files.


func run(t) -> void:
	var tmp := OS.get_temp_dir().path_join("bz_gallery_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)

	var addon := tmp.path_join("game").path_join("addon")
	var nest := addon.path_join("nested")
	_write(addon.path_join("foo.trn"), "trn")
	_write(addon.path_join("foo.png"), "png")
	_write(addon.path_join("foo.bmp"), "bmp")
	_write(addon.path_join("bar.trn"), "trn")
	_write(addon.path_join("bar.BMP"), "bmp")
	_write(addon.path_join("skip.txt"), "no")
	_write(addon.path_join("orphan.bzn"), "bzn")
	_write(nest.path_join("deep.trn"), "trn")
	_write(nest.path_join("deep.bmp"), "bmp")
	_write(addon.path_join("binmap.trn"), "trn")
	_write(addon.path_join("binmap.bzn"), "\u0000binary")
	_write(addon.path_join("CASED.TRN"), "trn")

	var pack := tmp.path_join("workshop").path_join("Cool Pack")
	_write(pack.path_join("foo.trn"), "trn")
	_write(pack.path_join("foo.png"), "png")
	_write(pack.path_join("onlybzn.bzn"), "ascii")

	var templates := tmp.path_join("templates")
	_write(templates.path_join("crater-arena").path_join("xtcrater.trn"), "trn")
	_write(templates.path_join("valley").path_join("xtvalley.trn"), "trn")
	_write(templates.path_join("valley").path_join("xtvalley.png"), "png")
	_write(templates.path_join("README.md"), "docs")

	var missing_addon := tmp.path_join("nogame")
	DirAccess.make_dir_recursive_absolute(missing_addon)
	t.eq(MapGalleryEnum.collect_sources(missing_addon, "", []).size(), 0, "no addon dir → no addon source")

	var none := MapGalleryEnum.collect_sources("", "", [])
	t.eq(none.size(), 0, "empty roots → no sources")

	var sources := MapGalleryEnum.collect_sources(
		tmp.path_join("game"),
		templates,
		[
			{"kind": "workshop_item", "path": pack, "name": "Cool Pack", "id": "99"},
			{"kind": "workshop_item", "path": tmp.path_join("missing_pack"), "name": "Gone"},
		]
	)
	t.eq(sources.size(), 3, "addon + existing pack + templates")
	t.eq(str(sources[0].get("kind")), "addon")
	t.eq(str(sources[0].get("source")), "addon")
	t.eq(str(sources[1].get("kind")), "workshop")
	t.eq(str(sources[1].get("source")), "Cool Pack")
	t.eq(str(sources[2].get("kind")), "template")
	t.eq(str(sources[2].get("source")), "template")

	var nameless := tmp.path_join("workshop").path_join("12345")
	DirAccess.make_dir_recursive_absolute(nameless)
	var fallback := MapGalleryEnum.collect_sources("", "", [
		{"kind": "workshop_item", "path": nameless, "id": "12345"},
	])
	t.eq(fallback.size(), 1)
	t.eq(str(fallback[0].get("source")), "12345", "workshop name falls back to id")

	var from_probe := MapGalleryEnum.workshop_items_from_discover({
		"ok": true,
		"installs": [
			{"kind": "game", "path": "/game"},
			{"kind": "workshop_item", "path": pack, "name": "Cool Pack", "id": "99"},
			{"kind": "workshop_item", "path": nameless, "id": "12345"},
		],
	})
	t.eq(from_probe.size(), 2, "discover payload keeps only workshop_item")
	t.eq(MapGalleryEnum.workshop_items_from_discover(
		BzErrors.err("install_invalid", "nope")
	).size(), 0, "error payload → no items")
	t.eq(MapGalleryEnum.workshop_items_from_discover(null).size(), 0)

	var one := MapGalleryEnum.scan_dir(addon, "addon", "addon")
	var stems := _stems(one.get("entries", []))
	stems.sort()
	t.eq(stems, ["CASED", "bar", "binmap", "foo"], "scan_dir is one level; .TRN counts")
	t.ok("orphan" not in stems, "bzn-only is not a tile")
	var subdirs: PackedStringArray = one.get("subdirs", PackedStringArray())
	t.ok(str(subdirs[0]).ends_with("nested") if subdirs.size() > 0 else false, "scan_dir reports child dirs")

	t.eq(MapGalleryEnum.resolve_thumb(addon, "foo").get_file().to_lower(), "foo.png", "png wins over bmp")
	t.eq(MapGalleryEnum.resolve_thumb(addon, "bar").get_extension().to_lower(), "bmp", "bmp/BMP when no png")
	t.eq(MapGalleryEnum.resolve_thumb(addon, "binmap"), "", "no thumb → empty")
	t.eq(MapGalleryEnum.resolve_thumb(addon, "missing"), "", "unknown stem → empty")
	t.eq(MapGalleryEnum.resolve_thumb(tmp.path_join("nope"), "foo"), "")

	var foo_entry := _by_stem(one.get("entries", []), "foo")
	t.eq(str(foo_entry.get("thumb_path")).get_file().to_lower(), "foo.png")
	t.eq(str(_by_stem(one.get("entries", []), "bar").get("thumb_path")).get_extension().to_lower(), "bmp")
	t.eq(str(_by_stem(one.get("entries", []), "binmap").get("thumb_path")), "")
	t.ok(not str(_by_stem(one.get("entries", []), "binmap").get("path")).is_empty(), "binary sibling still listed")

	var missing_scan := MapGalleryEnum.scan_dir(tmp.path_join("absent"), "addon", "addon")
	t.eq((missing_scan.get("entries", []) as Array).size(), 0)
	t.eq((missing_scan.get("subdirs", PackedStringArray()) as PackedStringArray).size(), 0)

	var tree := MapGalleryEnum.scan_sources(sources)
	var by_key := {}
	for e in tree:
		var key := "%s|%s" % [e.get("stem"), e.get("source")]
		by_key[key] = e
	t.ok(by_key.has("foo|addon"), "addon foo")
	t.ok(by_key.has("foo|Cool Pack"), "same stem in workshop is a second tile")
	t.ok(by_key.has("deep|addon"), "nested addon trn")
	t.eq(str(by_key["deep|addon"].get("thumb_path")).get_file().to_lower(), "deep.bmp")
	t.ok(by_key.has("xtcrater|template"))
	t.ok(by_key.has("xtvalley|template"))
	t.eq(str(by_key["xtvalley|template"].get("thumb_path")).get_file().to_lower(), "xtvalley.png")
	t.ok(not by_key.has("onlybzn|Cool Pack"), "workshop bzn without trn is skipped")
	t.ok(by_key.has("binmap|addon"), "binary bzn is not filtered")
	t.ok(by_key.has("CASED|addon"), "TRN case")

	var filtered := MapGalleryEnum.filter_by_stem(tree, "FOO")
	var f_stems := _stems(filtered)
	f_stems.sort()
	t.eq(f_stems, ["foo", "foo"], "stem substring, case-insensitive")
	var src_hit := MapGalleryEnum.filter_by_stem(tree, "Cool")
	t.eq(src_hit.size(), 0, "search does not match source / pack name")
	t.eq(MapGalleryEnum.filter_by_stem(tree, "   ").size(), tree.size(), "blank query is all")
	t.eq(MapGalleryEnum.filter_by_stem(tree, "xtc").size(), 1)
	t.eq(str(MapGalleryEnum.filter_by_stem(tree, "xtc")[0].get("stem")), "xtcrater")

	var sortable: Array = [
		{"stem": "b", "kind": "template", "source": "template", "path": "2"},
		{"stem": "a", "kind": "addon", "source": "addon", "path": "1"},
		{"stem": "a", "kind": "workshop", "source": "Zed", "path": "3"},
	]
	MapGalleryEnum.sort_entries(sortable)
	t.eq(str(sortable[0].get("stem")), "a")
	t.eq(str(sortable[0].get("kind")), "addon")
	t.eq(str(sortable[1].get("kind")), "workshop")
	t.eq(str(sortable[2].get("stem")), "b")

	t.eq(
		MapGalleryEnum.dir_key("C:/Maps/Addon") == MapGalleryEnum.dir_key("C:/Maps/Addon/"),
		true
	)

	await _dialog_state(t, tree)

	_rmtree(tmp)


func _dialog_state(t, entries: Array) -> void:
	var dlg: Node = load("res://project/ui/gallery/MapGalleryDialog.tscn").instantiate()
	t.tree.root.add_child(dlg)
	await t.tree.process_frame
	dlg.test_workshop_items = []
	dlg._entries = entries
	dlg._scanning = false
	dlg._rebuild_grid()
	var grid: ItemList = dlg.find_child("Tiles", true, false)
	var open_btn: Button = dlg.find_child("Open", true, false)
	t.ok(grid.item_count >= 2, "grid lists cached entries")
	t.ok(open_btn.disabled, "Open disabled with no selection")
	t.eq(open_btn.tooltip_text, "Select a map")
	dlg._search.text = "xtc"
	dlg._on_search("xtc")
	t.eq(grid.item_count, 1, "search filters the grid")
	t.eq(open_btn.tooltip_text, "Select a map")
	dlg._search.text = "zzzz-no-map"
	dlg._on_search("zzzz-no-map")
	t.eq(grid.item_count, 0)
	t.ok(open_btn.disabled)
	t.eq(open_btn.tooltip_text, "No maps match")
	dlg._search.text = ""
	dlg._on_search("")
	grid.select(0)
	dlg._refresh_open_button()
	t.ok(not open_btn.disabled, "Open enables after select")
	var opened: Array = []
	dlg.map_open_requested.connect(func(p): opened.append(p))
	var want := str(grid.get_item_metadata(0).get("path", ""))
	dlg._open_selected()
	t.eq(opened, [want], "Open emits the .trn path")
	t.ok(not dlg.visible, "dialog hides after Open")
	dlg.queue_free()
	await t.tree.process_frame


func _by_stem(entries: Array, stem: String) -> Dictionary:
	for e in entries:
		if str(e.get("stem", "")) == stem:
			return e
	return {}


func _stems(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out.append(str(e.get("stem", "")))
	return out


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _rmtree(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		DirAccess.remove_absolute(path)
		return
	da.include_hidden = true
	da.include_navigational = false
	for fname in da.get_files():
		DirAccess.remove_absolute(path.path_join(String(fname)))
	for dname in da.get_directories():
		_rmtree(path.path_join(String(dname)))
	DirAccess.remove_absolute(path)
