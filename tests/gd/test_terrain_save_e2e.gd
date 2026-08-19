extends RefCounted
## End-to-end terrain save on a real multi-zone template (2560 m = 2x2 zones):
## open -> HeightField edit (the editor's sculpt write path) -> dirty flag ->
## BzSave -> parse the shipped .hg2 -> reopen the saved set.
##
## Covers what the format-layer goldens cannot: the editor-side chain from
## viewport heights to shipped bytes, across a zone boundary, plus the F3 §3
## lightmap rules (untouched save keeps .lgt byte-identical; dirty-terrain
## save drops it so the game re-bakes).


func _read_heightmap(t, path: String, label: String) -> Variant:
	var r: Dictionary = BzHg2.read_hg2(path)
	if not bool(r.get("ok", false)):
		t.fail("%s: %s" % [label, str(r)])
		return null
	var hm: Variant = r.get("heightmap")
	if hm == null:
		t.fail("%s: no heightmap in payload" % label)
	return hm


func run(t) -> void:
	var root := OS.get_temp_dir().path_join("bz-e2e-terrain")
	if DirAccess.dir_exists_absolute(root):
		_rm_rf(root)
	DirAccess.make_dir_recursive_absolute(root)
	var session := root.path_join("session")
	var out_clean := root.path_join("out-clean")
	var out_dir := root.path_join("out")
	var session2 := root.path_join("session2")

	var trn := ProjectSettings.globalize_path("res://templates/highlands-4team/xthiland.trn")
	var src_lgt := ProjectSettings.globalize_path("res://templates/highlands-4team/xthiland.lgt")
	var src_hg2 := ProjectSettings.globalize_path("res://templates/highlands-4team/xthiland.hg2")
	var opened: Dictionary = BzOpen.open_map(trn, session)
	t.ok(opened.get("ok") == true, "open template: %s" % str(opened))
	if opened.get("ok") != true:
		return
	var manifest: Dictionary = BzSession.read_json(session.path_join("manifest.json"))
	var gx := int(manifest.get("grid_x", 0))
	var gz := int(manifest.get("grid_z", 0))
	t.ok(gx == 512 and gz == 512, "template is multi-zone (%dx%d)" % [gx, gz])
	if gx < 512 or gz < 512:
		return

	# Untouched save first: .lgt ships byte-identical.
	var saved_clean: Dictionary = BzSave.save_session(session, out_clean, "xthiland")
	t.ok(saved_clean.get("ok") == true, "untouched save: %s" % str(saved_clean))
	if saved_clean.get("ok") == true:
		t.ok(
			FileAccess.get_file_as_bytes(out_clean.path_join("xthiland.lgt"))
				== FileAccess.get_file_as_bytes(src_lgt),
			"untouched save keeps .lgt byte-identical"
		)

	# Editor path: load into HeightField, sculpt a plateau crossing the
	# zone-256 boundary, write back exactly as MapState.persist does.
	var field := HeightField.new()
	var err: Error = field.load_r16(session.path_join("terrain.r16"), gx, gz)
	t.ok(err == OK, "load_r16")
	var x0 := 250
	var z0 := 250
	var w := 11
	var d := 11
	var vals := PackedInt32Array()
	vals.resize(w * d)
	vals.fill(3333)
	field.write_rect(x0, z0, w, d, vals)
	field.write_r16(session.path_join("terrain.r16"))
	var dirty: Dictionary = BzSession.read_json(session.path_join("dirty.json"))
	dirty["terrain"] = true
	BzSession.write_json(session.path_join("dirty.json"), dirty)

	var saved: Dictionary = BzSave.save_session(session, out_dir, "xthiland")
	t.ok(saved.get("ok") == true, "dirty save: %s" % str(saved))
	if saved.get("ok") != true:
		return

	# The shipped .hg2 must carry the plateau at the same global coordinates.
	var hm: Variant = _read_heightmap(t, out_dir.path_join("xthiland.hg2"), "parse saved hg2")
	if hm == null:
		return
	var data: PackedInt32Array = hm.data
	var bad := 0
	for zz in range(z0, z0 + d):
		for xx in range(x0, x0 + w):
			if (data[zz * gx + xx] & 0x1FFF) != 3333:
				bad += 1
	t.eq(bad, 0, "plateau cells wrong in shipped hg2")

	# Flags and untouched heights must pass through from the template.
	var hm0: Variant = _read_heightmap(t, src_hg2, "parse template hg2")
	if hm0 != null:
		var data0: PackedInt32Array = hm0.data
		var flag_diff := 0
		var height_diff_outside := 0
		for i in data.size():
			var zz := i / gx
			var xx := i % gx
			var inside: bool = xx >= x0 and xx < x0 + w and zz >= z0 and zz < z0 + d
			if (data[i] >> 13) != (data0[i] >> 13):
				flag_diff += 1
			if not inside and (data[i] & 0x1FFF) != (data0[i] & 0x1FFF):
				height_diff_outside += 1
		t.eq(flag_diff, 0, "flag words changed")
		t.eq(height_diff_outside, 0, "heights changed outside plateau")

	# F3 §3: dirty-terrain save must not ship the stale lightmap.
	t.ok(
		not FileAccess.file_exists(out_dir.path_join("xthiland.lgt")),
		"stale .lgt dropped on dirty-terrain save"
	)

	# Reopening the shipped set shows the edit at the same cells.
	var reopened: Dictionary = BzOpen.open_map(out_dir.path_join("xthiland.trn"), session2)
	t.ok(reopened.get("ok") == true, "reopen saved map: %s" % str(reopened))
	if reopened.get("ok") == true:
		var field2 := HeightField.new()
		field2.load_r16(session2.path_join("terrain.r16"), gx, gz)
		var bad2 := 0
		for zz in range(z0, z0 + d):
			for xx in range(x0, x0 + w):
				if field2.height_raw(xx, zz) != 3333:
					bad2 += 1
		t.eq(bad2, 0, "plateau cells wrong after reopen")
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
