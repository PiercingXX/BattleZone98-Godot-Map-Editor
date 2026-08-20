extends RefCounted
## Shipped BZ98 file sets are mixed case — xxPier02.HG2 and xxPier02.MAT next
## to xxPier02.trn and xxPier02.bzn. A re-encode that builds its own lowercase
## name targets a different path than the pass-1 residue copy, so the stale
## original ships beside the edit (.HG2 + .hg2) on a case-sensitive filesystem,
## and collides into one file of undefined content on Windows.


func run(t) -> void:
	var root := OS.get_temp_dir().path_join("bz-mixedcase")
	if DirAccess.dir_exists_absolute(root):
		_rm_rf(root)
	DirAccess.make_dir_recursive_absolute(root)
	var src_dir := root.path_join("src")
	var session := root.path_join("session")
	var out_dir := root.path_join("out")
	DirAccess.make_dir_recursive_absolute(src_dir)

	# Restage the template with the extension case a shipped map uses.
	var tpl := ProjectSettings.globalize_path("res://templates/highlands-4team")
	var upper := {"hg2": "HG2", "mat": "MAT", "lgt": "LGT"}
	var da := DirAccess.open(tpl)
	t.ok(da != null, "template dir readable")
	if da == null:
		return
	for name in da.get_files():
		var ext: String = str(name).get_extension().to_lower()
		var dest_name: String = "%s.%s" % [str(name).get_basename(), upper.get(ext, ext)]
		t.eq(
			DirAccess.copy_absolute(tpl.path_join(str(name)), src_dir.path_join(dest_name)),
			OK,
			"stage %s" % dest_name
		)

	var opened: Dictionary = BzOpen.open_map(src_dir.path_join("xthiland.trn"), session)
	t.ok(opened.get("ok") == true, "open mixed-case set: %s" % str(opened))
	if opened.get("ok") != true:
		return
	var manifest: Dictionary = BzSession.read_json(session.path_join("manifest.json"))
	var gx := int(manifest.get("grid_x", 0))

	var field := HeightField.new()
	t.eq(field.load_r16(session.path_join("terrain.r16"), gx, gx), OK, "load_r16")
	var vals := PackedInt32Array()
	vals.resize(11 * 11)
	vals.fill(3333)
	field.write_rect(250, 250, 11, 11, vals)
	field.write_r16(session.path_join("terrain.r16"))
	var dirty: Dictionary = BzSession.read_json(session.path_join("dirty.json"))
	dirty["terrain"] = true
	dirty["materials"] = true
	BzSession.write_json(session.path_join("dirty.json"), dirty)

	var saved: Dictionary = BzSave.save_session(session, out_dir, "xthiland")
	t.ok(saved.get("ok") == true, "save: %s" % str(saved))
	if saved.get("ok") != true:
		return

	# Exactly one heightmap and one tilemap, whatever the case.
	var hg2s: Array = _matching(out_dir, "xthiland.hg2")
	var mats: Array = _matching(out_dir, "xthiland.mat")
	t.eq(hg2s.size(), 1, "one heightmap shipped, got %s" % str(hg2s))
	t.eq(mats.size(), 1, "one tilemap shipped, got %s" % str(mats))
	if hg2s.size() != 1:
		return

	# And it is the edited one.
	var rd: Dictionary = BzHg2.read_hg2(out_dir.path_join(str(hg2s[0])))
	t.ok(rd.get("ok", false), "parse shipped %s: %s" % [str(hg2s[0]), str(rd)])
	if rd.get("ok", false):
		var data: PackedInt32Array = (rd.get("heightmap") as BzHg2.HeightMap).data
		var bad := 0
		for zz in range(250, 261):
			for xx in range(250, 261):
				if (data[zz * gx + xx] & 0x1FFF) != 3333:
					bad += 1
		t.eq(bad, 0, "shipped %s lost the sculpt" % str(hg2s[0]))
	_rm_rf(root)


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
