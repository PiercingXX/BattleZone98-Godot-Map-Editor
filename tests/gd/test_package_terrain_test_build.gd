extends RefCounted
## The in-game test is a TERRAIN test. A pack map's mission script assumes the
## pack's game mode is running; a play-test launch does not set one up, so the
## script chain dies (SBPAi on an empty GetPlayerHandle()) behind modal Lua
## dialogs and the map is unusable. Mode "test" ships the same terrain, tiles
## and object layout with every script stripped, so it loads as a plain
## mission -- including scripts a previous full package left in the install,
## which nothing would otherwise overwrite.


func run(t) -> void:
	var root := OS.get_temp_dir().path_join("bz-terraintest")
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
	# Make it a pack map: a mission script that pulls in the pack's stack.
	_write_text(src_dir.path_join("xtvalley.lua"), """
RequireFix = require("RequireFix")
RequireFix.Initialize("3406347034")
local SBPScript = require("SBPScript")
local SBPAi = require("SBPAi")
""")
	# And a script left behind by an earlier full package.
	_write_text(addon.path_join("xtvalleyMAP.lua"), "-- stale from a previous package\n")

	var opened: Dictionary = BzOpen.open_map(src_dir.path_join("xtvalley.trn"), session)
	t.ok(opened.get("ok") == true, "open: %s" % str(opened))
	if opened.get("ok") != true:
		return

	var manifest: Dictionary = BzSession.read_json(session.path_join("manifest.json"))
	t.eq(GameTest.source_stem(manifest), "xtvalley", "source stem is the residue's stem")
	t.ok(GameTest.is_pack_map(session, "xtvalley"), "detected as a pack map")

	var pkg: Dictionary = BzPackage.package_session(session, "test", game_root)
	t.ok(pkg.get("ok") == true, "package test: %s" % str(pkg))
	if pkg.get("ok") != true:
		return

	# No script may reach the install -- staged, shared, or already sitting there.
	var lua_left: Array = _matching_ext(addon, "lua")
	t.eq(lua_left.size(), 0, "scripts reached the terrain build: %s" % str(lua_left))
	t.eq((pkg.get("shared_lua", []) as Array).size(), 0, "no shared modules pulled in")
	t.ok(
		(pkg.get("skipped", []) as Array).has("xtvalley.lua"),
		"map script reported as skipped: %s" % str(pkg.get("skipped", []))
	)
	t.ok(
		(pkg.get("evicted", []) as Array).has("xtvalleyMAP.lua"),
		"previous package's script evicted: %s" % str(pkg.get("evicted", []))
	)

	# Terrain, tiles and the map itself must still be there.
	for want in ["xtvalley.hg2", "xtvalley.trn", "xtvalley.mat", "xtvalley.bzn"]:
		t.ok(_exists_ci(addon, want), "%s shipped" % want)

	# ...but every object except the spawn is gone. A pack map's furniture does
	# not survive without the pack: on xxPier02 the mesh-carried moat threw the
	# correctly-spawned player at 1500 m/s and the mission failed.
	t.ok(
		(pkg.get("stripped", []) as Array).has("xtvalley.bzn"),
		"BZN reported as stripped: %s" % str(pkg.get("stripped", []))
	)
	var lb: Dictionary = BzBzn.read_bzn(addon.path_join("xtvalley.bzn"))
	t.ok(lb.get("ok", false), "parse shipped bzn: %s" % str(lb))
	if lb.get("ok", false):
		var shipped: BzBzn.BznFile = lb.get("bznfile") as BzBzn.BznFile
		t.eq(shipped.objects.size(), 1, "only the spawn survives")
		if shipped.objects.size() == 1:
			var only = shipped.objects[0]
			t.ok(
				only.is_user() or str(only.prjid).to_lower() == "player",
				"the survivor is the player, got prjid=%s" % str(only.prjid)
			)

	# The full addon build must still carry the whole layout.
	var before: Dictionary = BzBzn.read_bzn(src_dir.path_join("xtvalley.bzn"))
	var authored: int = (before.get("bznfile") as BzBzn.BznFile).objects.size()
	t.ok(authored > 1, "template has a layout to lose (%d objects)" % authored)

	# And "addon" mode must still ship the scripts -- this is not a global change.
	var full: Dictionary = BzPackage.package_session(session, "addon", game_root)
	t.ok(full.get("ok") == true, "package addon: %s" % str(full))
	t.ok(_exists_ci(addon, "xtvalley.lua"), "full addon build still ships the map script")
	var lb2: Dictionary = BzBzn.read_bzn(addon.path_join("xtvalley.bzn"))
	if lb2.get("ok", false):
		t.eq(
			(lb2.get("bznfile") as BzBzn.BznFile).objects.size(),
			authored,
			"full addon build keeps every object"
		)
	_rm_rf(root)


func _matching_ext(dir_path: String, ext: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	for n in da.get_files():
		if str(n).get_extension().to_lower() == ext:
			out.append(str(n))
	out.sort()
	return out


func _exists_ci(dir_path: String, name: String) -> bool:
	var da := DirAccess.open(dir_path)
	if da == null:
		return false
	for n in da.get_files():
		if str(n).to_lower() == name.to_lower():
			return true
	return false


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
