extends RefCounted
## The live package routes copy staged names over the destination and never
## delete, so a previous package's files outlive the edit that replaced them.
## Two of those beat the new map: the .lgt a dirty-terrain save drops on
## purpose (it lights the pre-edit geometry) and a case variant of a name we
## did write (an older build guessed a lowercase suffix, so xthiland.hg2 sits
## beside xthiland.HG2 and either may reach the game). Anything the save does
## not name is not ours and must survive.

const PLATEAU := 3333
const UNRELATED := "SBPScript.lua"


func run(t) -> void:
	var root := OS.get_temp_dir().path_join("bz-evict")
	if DirAccess.dir_exists_absolute(root):
		_rm_rf(root)
	DirAccess.make_dir_recursive_absolute(root)
	var src_dir := root.path_join("src")
	var session := root.path_join("session")
	var game_root := root.path_join("game")
	var addon := game_root.path_join("addon")
	DirAccess.make_dir_recursive_absolute(src_dir)
	DirAccess.make_dir_recursive_absolute(addon)

	# Stage the template the way a shipped map is cased.
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

	# What a previous package left in the install: the pre-edit lightmap, a
	# lowercase heightmap twin, and a file that belongs to the rest of the mod.
	t.eq(
		DirAccess.copy_absolute(src_dir.path_join("xthiland.LGT"), addon.path_join("xthiland.LGT")),
		OK,
		"stale lightmap in place"
	)
	t.eq(
		DirAccess.copy_absolute(src_dir.path_join("xthiland.HG2"), addon.path_join("xthiland.hg2")),
		OK,
		"stale lowercase heightmap in place"
	)
	_write_text(addon.path_join(UNRELATED), "-- not ours\n")

	var opened: Dictionary = BzOpen.open_map(src_dir.path_join("xthiland.trn"), session)
	t.ok(opened.get("ok") == true, "open: %s" % str(opened))
	if opened.get("ok") != true:
		return
	var manifest: Dictionary = BzSession.read_json(session.path_join("manifest.json"))
	var gx := int(manifest.get("grid_x", 0))

	var field := HeightField.new()
	t.eq(field.load_r16(session.path_join("terrain.r16"), gx, gx), OK, "load_r16")
	var vals := PackedInt32Array()
	vals.resize(11 * 11)
	vals.fill(PLATEAU)
	field.write_rect(250, 250, 11, 11, vals)
	field.write_r16(session.path_join("terrain.r16"))
	var dirty: Dictionary = BzSession.read_json(session.path_join("dirty.json"))
	dirty["terrain"] = true
	BzSession.write_json(session.path_join("dirty.json"), dirty)

	var pkg: Dictionary = BzPackage.package_session(session, "addon", game_root)
	t.ok(pkg.get("ok") == true, "package addon: %s" % str(pkg))
	if pkg.get("ok") != true:
		return

	# On a case-insensitive filesystem the twin folded onto the file we wrote,
	# so there is one heightmap either way — and it must carry the sculpt.
	var hg2s: Array = _matching(addon, "xthiland.hg2")
	t.eq(hg2s.size(), 1, "one heightmap in the install, got %s" % str(hg2s))
	if hg2s.size() == 1:
		var rd: Dictionary = BzHg2.read_hg2(addon.path_join(str(hg2s[0])))
		t.ok(rd.get("ok", false), "parse %s: %s" % [str(hg2s[0]), str(rd)])
		if rd.get("ok", false):
			var data: PackedInt32Array = (rd.get("heightmap") as BzHg2.HeightMap).data
			var bad := 0
			for zz in range(250, 261):
				for xx in range(250, 261):
					if (data[zz * gx + xx] & 0x1FFF) != PLATEAU:
						bad += 1
			t.eq(bad, 0, "installed %s is not the edit" % str(hg2s[0]))

	# The dropped lightmap must not survive, or the game skips the re-bake and
	# lights the new terrain with the old solution.
	t.eq(
		_matching(addon, "xthiland.lgt").size(),
		0,
		"stale lightmap survived the package: %s" % str(_matching(addon, "xthiland.lgt"))
	)

	# Eviction is scoped to names this save owns.
	t.ok(FileAccess.file_exists(addon.path_join(UNRELATED)), "%s was evicted" % UNRELATED)
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
