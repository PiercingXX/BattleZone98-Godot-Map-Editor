extends RefCounted
## Workshop maps define object classes next to the map set (xxp2tr.odf/.mesh/
## .material). The engine quits the mission on the first GameObject whose .odf
## it cannot find — "failed to load game files", 3/8 sim phases — so a package
## that drops them produces a map that installs cleanly and never loads.
##
## manifest.source_path is the map's DIRECTORY; the packager used to take
## get_base_dir() of it and scan one level up, which for a workshop map is
## content/301650/ (numbered item folders, no .odf), so nothing ever matched.


func run(t) -> void:
	var root := OS.get_temp_dir().path_join("bz-custom")
	if DirAccess.dir_exists_absolute(root):
		_rm_rf(root)
	DirAccess.make_dir_recursive_absolute(root)
	# Nest the map a level down, so scanning the parent finds no assets —
	# that is exactly the shape a workshop item has.
	var src_dir := root.path_join("content").path_join("301650").path_join("3781900699")
	var session := root.path_join("session")
	var game_root := root.path_join("game")
	var addon := game_root.path_join("addon")
	DirAccess.make_dir_recursive_absolute(src_dir)
	DirAccess.make_dir_recursive_absolute(addon)

	var tpl := ProjectSettings.globalize_path("res://templates/highlands-4team")
	var da := DirAccess.open(tpl)
	t.ok(da != null, "template dir readable")
	if da == null:
		return
	for name in da.get_files():
		t.eq(
			DirAccess.copy_absolute(tpl.path_join(str(name)), src_dir.path_join(str(name))),
			OK,
			"stage %s" % str(name)
		)
	# A map-private class, plus the geometry its odf names.
	_write_text(src_dir.path_join("xxcust.odf"), "[GameObjectClass]\ngeometryName = xxcust.mesh\n")
	_write_text(src_dir.path_join("xxcust.mesh"), "MESHBYTES")
	_write_text(src_dir.path_join("xxcust.material"), "material xxcust {}\n")

	var opened: Dictionary = BzOpen.open_map(src_dir.path_join("xthiland.trn"), session)
	t.ok(opened.get("ok") == true, "open: %s" % str(opened))
	if opened.get("ok") != true:
		return

	# Place one object of that class.
	var objects: Dictionary = BzSession.read_json(session.path_join("objects.json"))
	var recs: Array = objects.get("", [])
	recs.append({
		"id": "new-0001", "prjid": "xxcust", "label": "xxcust1",
		"x": 100.0, "y": 0.0, "z": 100.0, "team": 1,
	})
	objects[""] = recs
	BzSession.write_json(session.path_join("objects.json"), objects)

	var pkg: Dictionary = BzPackage.package_session(session, "addon", game_root)
	t.ok(pkg.get("ok") == true, "package addon: %s" % str(pkg))
	if pkg.get("ok") != true:
		return

	for want in ["xxcust.odf", "xxcust.mesh", "xxcust.material"]:
		t.ok(
			FileAccess.file_exists(addon.path_join(want)),
			"%s did not ship; the mission would quit on the missing class (custom_assets=%s)"
			% [want, str(pkg.get("custom_assets", []))]
		)
	_rm_rf(root)


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
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
