extends RefCounted
## Starting a map from a template and saving it under your own name renames the
## files but used to ship their bytes untouched, so the .bzn still named the
## TEMPLATE's terrain. The renamed .trn is then the one file the .bzn does not
## ask for and the engine refuses the mission outright:
##   "Could not load terrain xtvalley.trn"
## Uses a stem of a different length than the template's, so a same-length
## in-place patch cannot make this pass by accident.

const OUT_STEM := "tst9"   # 4 chars vs xtvalley's 8


func run(t) -> void:
	var root := OS.get_temp_dir().path_join("bz-restem")
	if DirAccess.dir_exists_absolute(root):
		_rm_rf(root)
	DirAccess.make_dir_recursive_absolute(root)
	var src_dir := root.path_join("src")
	var session := root.path_join("session")
	var out_dir := root.path_join("out")
	DirAccess.make_dir_recursive_absolute(src_dir)

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

	var saved: Dictionary = BzSave.save_session(session, out_dir, OUT_STEM)
	t.ok(saved.get("ok") == true, "save under a new stem: %s" % str(saved))
	if saved.get("ok") != true:
		return

	# The terrain the .bzn asks for must be the .trn we actually shipped.
	var bzn_path := out_dir.path_join("%s.bzn" % OUT_STEM)
	t.ok(FileAccess.file_exists(bzn_path), "%s.bzn shipped" % OUT_STEM)
	t.ok(
		FileAccess.file_exists(out_dir.path_join("%s.trn" % OUT_STEM)),
		"%s.trn shipped" % OUT_STEM
	)
	if not FileAccess.file_exists(bzn_path):
		return
	var loaded: Dictionary = BzBzn.read_bzn(bzn_path)
	t.ok(loaded.get("ok", false), "parse shipped bzn: %s" % str(loaded))
	if not loaded.get("ok", false):
		return
	var bzn: BzBzn.BznFile = loaded.get("bznfile") as BzBzn.BznFile
	t.eq(
		str(bzn.header_value("TerrainName", "")),
		OUT_STEM,
		"TerrainName still points at the template's terrain — mission will not load"
	)
	t.eq(
		str(bzn.header_value("msn_filename", "")),
		"%s.bzn" % OUT_STEM,
		"msn_filename still names the template"
	)

	# Every variant, not just the base.
	for variant in ["_S", "_ST", "_SW"]:
		var vp := out_dir.path_join("%s%s.bzn" % [OUT_STEM, variant])
		if not FileAccess.file_exists(vp):
			continue
		var lv: Dictionary = BzBzn.read_bzn(vp)
		if not lv.get("ok", false):
			continue
		t.eq(
			str((lv.get("bznfile") as BzBzn.BznFile).header_value("TerrainName", "")),
			OUT_STEM,
			"%s%s.bzn TerrainName" % [OUT_STEM, variant]
		)

	# The lobby name must not still be the template's.
	var ini_path := out_dir.path_join("%s.ini" % OUT_STEM)
	if FileAccess.file_exists(ini_path):
		var ini_text := FileAccess.get_file_as_string(ini_path)
		t.ok(
			not ini_text.contains("xtvalley"),
			"ini still shows the template name in the lobby: %s" % ini_text
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
