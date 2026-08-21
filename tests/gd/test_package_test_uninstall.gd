extends RefCounted
## A terrain-test build is temporary and NOT additive: its BZNs hold one
## object, so leaving it in addon/ silently replaces a full build of the same
## map, and its custom assets pile up. The install is recorded so it can be
## undone -- names it created are deleted, bytes it overwrote are put back.

const FULL_BZN := "-- a full addon build's bzn\n"
const OTHER := "SBPScript.lua"


func run(t) -> void:
	var root := OS.get_temp_dir().path_join("bz-uninstall")
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

	# What is already in the install: a full build of this map, and someone
	# else's file that has nothing to do with us.
	_write_text(addon.path_join("xtvalley.bzn"), FULL_BZN)
	_write_text(addon.path_join(OTHER), "-- not ours\n")

	var opened: Dictionary = BzOpen.open_map(src_dir.path_join("xtvalley.trn"), session)
	t.ok(opened.get("ok") == true, "open: %s" % str(opened))
	if opened.get("ok") != true:
		return

	var pkg: Dictionary = BzPackage.package_session(session, "test", game_root)
	t.ok(pkg.get("ok") == true, "package test: %s" % str(pkg))
	if pkg.get("ok") != true:
		return
	var record: Variant = pkg.get("install_record")
	t.ok(typeof(record) == TYPE_DICTIONARY, "install recorded: %s" % str(record))
	if typeof(record) != TYPE_DICTIONARY:
		return

	# The build is live: our stripped BZN replaced the full one.
	t.ok(FileAccess.file_exists(addon.path_join("xtvalley.hg2")), "terrain installed")
	t.ok(
		FileAccess.get_file_as_string(addon.path_join("xtvalley.bzn")) != FULL_BZN,
		"the full build's bzn was overwritten by the test build"
	)
	var during: int = _count(addon)
	t.ok(during > 2, "the build put files in addon/, got %d" % during)

	var undone: Dictionary = BzPackage.uninstall_test(record)
	t.ok(undone.get("ok") == true, "uninstall: %s" % str(undone))

	# Everything it added is gone...
	t.ok(
		not FileAccess.file_exists(addon.path_join("xtvalley.hg2")),
		"terrain left behind in addon/ after the test"
	)
	t.ok(
		not FileAccess.file_exists(addon.path_join("xtvalley.trn")),
		"trn left behind in addon/ after the test"
	)
	# ...what it overwrote is back, byte for byte...
	t.eq(
		FileAccess.get_file_as_string(addon.path_join("xtvalley.bzn")),
		FULL_BZN,
		"the full build's bzn was not restored"
	)
	# ...and what was never ours is untouched.
	t.ok(FileAccess.file_exists(addon.path_join(OTHER)), "%s was removed" % OTHER)
	t.eq(_count(addon), 2, "addon/ is back to what it held before: %s" % str(_names(addon)))

	# Undo is idempotent, and a record whose backup is gone does no harm.
	var again: Dictionary = BzPackage.uninstall_test(record)
	t.ok(again.get("ok") == true, "second uninstall is safe: %s" % str(again))
	t.eq(_count(addon), 2, "second uninstall changed nothing")

	# A full addon build records nothing to undo -- it is meant to persist.
	var full: Dictionary = BzPackage.package_session(session, "addon", game_root)
	t.ok(full.get("ok") == true, "package addon: %s" % str(full))
	t.ok(not full.has("install_record"), "addon builds are not temporary")
	_rm_rf(root)


func _names(dir_path: String) -> Array:
	var da := DirAccess.open(dir_path)
	if da == null:
		return []
	var out: Array = []
	for n in da.get_files():
		out.append(str(n))
	out.sort()
	return out


func _count(dir_path: String) -> int:
	return _names(dir_path).size()


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
