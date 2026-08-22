extends SceneTree
## Microbenchmark entry point:
##   godot --headless --path . -s res://tests/gd/bench_main.gd -- [out.json]
## or, with the same Godot discovery and isolated home the suite uses,
##   scripts/bench.sh [out.json]
##
## Covers the three things AGENTS.md rule 6 calls correctness rather than
## polish: the height-texture upload, the analytic raycast, and the full-grid
## selection loops. Nothing here asserts — it produces numbers, and it is
## deliberately kept out of the blocking CI job, because a perf threshold
## enforced on a noisy shared runner is worse than no threshold at all.
##
## run_tests.gd only discovers test_*.gd, so none of this joins the suite.

const Bench := preload("res://tests/gd/bench_harness.gd")
const CASES := "res://tests/gd/bench_cases.gd"


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("-"):
			out_path = arg

	# Loaded rather than preloaded: the cases reach for the MapState autoload,
	# which does not exist yet while this script is being compiled.
	var script: GDScript = load(CASES) as GDScript
	if script == null or not script.can_instantiate():
		printerr("cannot load %s" % CASES)
		quit(2)
		return
	var bench := Bench.new()
	script.new().run(bench)

	print(bench.format_table())
	if out_path.is_empty():
		print("\n(no output path given — JSON not written)")
	else:
		var err: Error = bench.write_json(out_path)
		if err != OK:
			printerr("could not write %s (error %d)" % [out_path, err])
			quit(1)
			return
		print("\nwrote %s" % out_path)
	quit(0)
