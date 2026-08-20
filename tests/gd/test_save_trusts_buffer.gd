extends RefCounted
## dirty.json is a hint. When it wrongly says terrain is clean, the save used
## to copy the residue .hg2 while BzRender drew the .BMP from terrain.r16 —
## shipping pre-edit terrain under a correct-looking thumbnail, with no error,
## no warning and every expected file present. On a map created flat that ships
## a heightmap that is flat everywhere.
##
## Asserts the WHOLE grid, not a stamped patch: a patch-only check passes on an
## otherwise-flat map, which is exactly how this stayed hidden.


func run(t) -> void:
	var root := OS.get_temp_dir().path_join("bz-trustbuf")
	if DirAccess.dir_exists_absolute(root):
		_rm_rf(root)
	DirAccess.make_dir_recursive_absolute(root)
	var src_dir := root.path_join("src")
	var session := root.path_join("session")
	var out_dir := root.path_join("out")
	DirAccess.make_dir_recursive_absolute(src_dir)

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

	var opened: Dictionary = BzOpen.open_map(src_dir.path_join("xthiland.trn"), session)
	t.ok(opened.get("ok") == true, "open: %s" % str(opened))
	if opened.get("ok") != true:
		return
	var manifest: Dictionary = BzSession.read_json(session.path_join("manifest.json"))
	var gx := int(manifest.get("grid_x", 0))
	var gz := int(manifest.get("grid_z", 0))

	# Sculpt into the session buffer the way a brush stroke does.
	var field := HeightField.new()
	t.eq(field.load_r16(session.path_join("terrain.r16"), gx, gz), OK, "load_r16")
	var vals := PackedInt32Array()
	vals.resize(41 * 41)
	vals.fill(3333)
	field.write_rect(120, 120, 41, 41, vals)
	field.write_r16(session.path_join("terrain.r16"))

	# ...and leave dirty.json exactly as a fresh open wrote it.
	var dirty: Dictionary = BzSession.read_json(session.path_join("dirty.json"))
	t.ok(not _truthy(dirty.get("terrain")), "precondition: the flag says terrain is clean")

	var saved: Dictionary = BzSave.save_session(session, out_dir, "xthiland")
	t.ok(saved.get("ok") == true, "save: %s" % str(saved))
	if saved.get("ok") != true:
		return

	# The heightmap the thumbnail is drawn from.
	var paths: Dictionary = BzSession.session_paths(session)
	var header: Dictionary = BzSession.read_json(str(paths["hg2_header"]))
	var recon: Variant = BzSession.reconstruct_heightmap(paths, header)
	t.ok(recon is BzHg2.HeightMap, "session reconstructs: %s" % str(recon))
	if not (recon is BzHg2.HeightMap):
		return
	var want: PackedInt32Array = (recon as BzHg2.HeightMap).data

	var hg2s: Array = _matching(out_dir, "xthiland.hg2")
	t.eq(hg2s.size(), 1, "one heightmap shipped, got %s" % str(hg2s))
	if hg2s.size() != 1:
		return
	var rd: Dictionary = BzHg2.read_hg2(out_dir.path_join(str(hg2s[0])))
	t.ok(rd.get("ok", false), "parse shipped %s: %s" % [str(hg2s[0]), str(rd)])
	if not rd.get("ok", false):
		return
	var got: PackedInt32Array = (rd.get("heightmap") as BzHg2.HeightMap).data

	# Whole grid, so an otherwise-flat ship cannot pass on a stamped patch.
	t.eq(got.size(), want.size(), "shipped sample count")
	var diff := 0
	var first := -1
	for i in mini(got.size(), want.size()):
		if got[i] != want[i]:
			diff += 1
			if first < 0:
				first = i
	t.eq(
		diff,
		0,
		"shipped heightmap differs from the .BMP's in %d/%d cells (first at %d)"
		% [diff, want.size(), first]
	)
	t.ok(
		str(saved.get("warnings", [])).contains("did not flag terrain"),
		"save says the flag was stale: %s" % str(saved.get("warnings", []))
	)
	_rm_rf(root)


func _truthy(v: Variant) -> bool:
	return v != null and v != false and v != 0


func _matching(dir_path: String, name: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	for n in da.get_files():
		if str(n).to_lower() == name.to_lower():
			out.append(str(n))
	out.sort()
	return out


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
