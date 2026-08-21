extends RefCounted
## A map started from a template is renamed in the editor only: MapState.stem
## becomes the new name while manifest.stem stays the stem the session was
## opened from (BzSave needs it to find residue files). Packaging read the
## manifest, so the map installed under the TEMPLATE's name while the launch
## asked for the user's:
##     Could not load "test1233.bzn"      -- xtvalley.bzn is what shipped
## The name to ship under is the caller's, passed through as out_stem.

const OUT_STEM := "test1233"


func run(t) -> void:
	var root := OS.get_temp_dir().path_join("bz-outstem")
	if DirAccess.dir_exists_absolute(root):
		_rm_rf(root)
	DirAccess.make_dir_recursive_absolute(root)
	var src_dir := root.path_join("src")
	var session := root.path_join("session")
	var game_root := root.path_join("game")
	var addon := game_root.path_join("addon")
	DirAccess.make_dir_recursive_absolute(src_dir)
	DirAccess.make_dir_recursive_absolute(addon)

	var tpl := ProjectSettings.globalize_path("res://templates/valley-2team")
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

	var opened: Dictionary = BzOpen.open_map(src_dir.path_join("xtvalley.trn"), session)
	t.ok(opened.get("ok") == true, "open template: %s" % str(opened))
	if opened.get("ok") != true:
		return
	# The manifest keeps the source stem; that is the whole point.
	var manifest: Dictionary = BzSession.read_json(session.path_join("manifest.json"))
	t.eq(str(manifest.get("stem", "")), "xtvalley", "manifest keeps the source stem")

	for mode in ["test", "addon"]:
		var pkg: Dictionary = BzPackage.package_session(session, mode, game_root, "", "", OUT_STEM)
		t.ok(pkg.get("ok") == true, "package %s: %s" % [mode, str(pkg)])
		if pkg.get("ok") != true:
			continue
		# GameTest launches "<MapState.stem><variant>.bzn" -- it has to be there.
		t.ok(
			_exists_ci(addon, "%s.bzn" % OUT_STEM),
			"%s: launch target %s.bzn missing; shipped %s"
			% [mode, OUT_STEM, str(_stems(addon))]
		)
		for want in ["%s.trn" % OUT_STEM, "%s.hg2" % OUT_STEM, "%s.mat" % OUT_STEM]:
			t.ok(_exists_ci(addon, want), "%s: %s shipped" % [mode, want])
		t.ok(
			not _exists_ci(addon, "xtvalley.bzn"),
			"%s: shipped under the template's name too: %s" % [mode, str(_stems(addon))]
		)

	# And with no out_stem the manifest still decides, so nothing else shifts.
	_rm_rf(addon)
	DirAccess.make_dir_recursive_absolute(addon)
	var fallback: Dictionary = BzPackage.package_session(session, "addon", game_root)
	t.ok(fallback.get("ok") == true, "package without out_stem: %s" % str(fallback))
	t.ok(_exists_ci(addon, "xtvalley.bzn"), "falls back to the manifest stem")
	_rm_rf(root)


func _stems(dir_path: String) -> Array:
	var out := {}
	var da := DirAccess.open(dir_path)
	if da == null:
		return []
	for n in da.get_files():
		if str(n).get_extension().to_lower() == "bzn":
			out[str(n)] = true
	var keys: Array = out.keys()
	keys.sort()
	return keys


func _exists_ci(dir_path: String, name: String) -> bool:
	var da := DirAccess.open(dir_path)
	if da == null:
		return false
	for n in da.get_files():
		if str(n).to_lower() == name.to_lower():
			return true
	return false


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
