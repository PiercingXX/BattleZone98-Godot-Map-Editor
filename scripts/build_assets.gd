extends SceneTree
## Headless asset-cache build: enumerate a game install and convert assets
## through the in-process backend, printing the payload summary.
##
## Usage:
##   godot --headless --path . -s res://scripts/build_assets.gd -- <cache_dir> [game_root]
## With no game_root, the install is auto-discovered (probe).

func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -- <cache_dir> [game_root]")
		quit(2)
		return
	var cache := String(args[0]).simplify_path()
	var game_root := String(args[1]) if args.size() > 1 else ""

	var payload: Dictionary = BzAssets.build_assets(game_root, cache, null, true, true)
	if not payload.get("ok", false):
		printerr("assets failed: %s" % JSON.stringify(payload.get("error", payload)))
		quit(1)
		return
	var classes: Array = payload.get("classes", [])
	var unresolved: Array = payload.get("unresolved", [])
	var verified := 0
	var with_mesh := 0
	for c in classes:
		if c.get("template_verified", false):
			verified += 1
		if not str(c.get("mesh", "")).is_empty():
			with_mesh += 1
	print("classes: %d  verified: %d  with converted mesh: %d  unresolved: %d" % [
		classes.size(), verified, with_mesh, unresolved.size(),
	])
	for u in unresolved.slice(0, 10):
		print("  unresolved: %s (%s)" % [u.get("prjid", "?"), u.get("reason", "?")])
	print("cache: %s" % payload.get("cache_dir", cache))
	quit(0)
