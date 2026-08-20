extends RefCounted
## A package (pack/addon/install) must never ship the untouched residue in
## place of the session's edits. BzPackage._save_session used to swallow a
## BzSave failure and copy residue/source over the staging directory, which
## silently reverted every edit — the freshly rendered .BMP still showed the
## sculpt, so the substitution was invisible.


func run(t) -> void:
	var root := OS.get_temp_dir().path_join("bz-pkg-residue")
	if DirAccess.dir_exists_absolute(root):
		_rm_rf(root)
	DirAccess.make_dir_recursive_absolute(root)
	var session := root.path_join("session")
	var out_dir := root.path_join("pack")

	var trn := ProjectSettings.globalize_path("res://templates/highlands-4team/xthiland.trn")
	var opened: Dictionary = BzOpen.open_map(trn, session)
	t.ok(opened.get("ok") == true, "open template: %s" % str(opened))
	if opened.get("ok") != true:
		return
	var manifest: Dictionary = BzSession.read_json(session.path_join("manifest.json"))
	var gx := int(manifest.get("grid_x", 0))
	var gz := int(manifest.get("grid_z", 0))

	# Sculpt exactly as MapState.persist does.
	var field := HeightField.new()
	t.eq(field.load_r16(session.path_join("terrain.r16"), gx, gz), OK, "load_r16")
	var x0 := 250
	var z0 := 250
	var vals := PackedInt32Array()
	vals.resize(11 * 11)
	vals.fill(3333)
	field.write_rect(x0, z0, 11, 11, vals)
	field.write_r16(session.path_join("terrain.r16"))
	var dirty: Dictionary = BzSession.read_json(session.path_join("dirty.json"))
	dirty["terrain"] = true
	BzSession.write_json(session.path_join("dirty.json"), dirty)

	# Break the save *after* the terrain re-encode: features.json is read
	# unconditionally, well past the .hg2 write.
	var f := FileAccess.open(session.path_join("features.json"), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()

	var pkg: Dictionary = BzPackage.package_session(session, "pack", "", "", out_dir)

	if pkg.get("ok", false):
		# If a package reports success, the shipped map must carry the edit.
		var hg2 := out_dir.path_join("xthiland.hg2")
		t.ok(FileAccess.file_exists(hg2), "packed .hg2 exists")
		if FileAccess.file_exists(hg2):
			var rd: Dictionary = BzHg2.read_hg2(hg2)
			t.ok(rd.get("ok", false), "parse packed hg2: %s" % str(rd))
			if rd.get("ok", false):
				var data: PackedInt32Array = (rd.get("heightmap") as BzHg2.HeightMap).data
				var bad := 0
				for zz in range(z0, z0 + 11):
					for xx in range(x0, x0 + 11):
						if (data[zz * gx + xx] & 0x1FFF) != 3333:
							bad += 1
				t.eq(bad, 0, "packaged hg2 lost the sculpt (residue was substituted)")
	else:
		t.ok(
			BzErrors.is_err(pkg),
			"a failed package must report the underlying error: %s" % str(pkg)
		)
	_rm_rf(root)


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
