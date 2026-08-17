extends SceneTree
## Headless authoring smoke: create a tiny map session and save a file set,
## entirely through the in-process backend (docs/03).
##
## Usage:
##   godot --headless --path . -s res://scripts/playtest_map.gd -- <out_dir> [game_root]

func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -- <out_dir> [game_root]")
		quit(2)
		return
	var out_dir := String(args[0]).simplify_path()
	var game_root := String(args[1]) if args.size() > 1 else ""
	var session := OS.get_temp_dir().path_join("xxedplay-session")
	DirAccess.make_dir_recursive_absolute(session)
	DirAccess.make_dir_recursive_absolute(out_dir)

	var created: Dictionary = BzNew.create_map(
		"xxedplay", "mars", 1280, 1280, session, game_root, 1000, "bzp"
	)
	if not created.get("ok", false):
		printerr("create_map failed: %s" % JSON.stringify(created.get("error", created)))
		quit(1)
		return
	var saved: Dictionary = BzSave.save_session(session, out_dir)
	if not saved.get("ok", false):
		printerr("save_session failed: %s" % JSON.stringify(saved.get("error", saved)))
		quit(1)
		return
	print(JSON.stringify(saved, "  "))
	quit(0)
