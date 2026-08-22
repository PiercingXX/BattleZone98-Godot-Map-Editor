extends RefCounted
## CommandRegistry: deterministic scan, per-file failure, user override.

const BUILTIN := CommandRegistry.BUILTIN_DIR
const TMP := "user://test_commands_scratch"


func run(t) -> void:
	_roots(t)
	_scan_is_deterministic(t)
	_bad_scripts_are_skipped(t)
	_user_root_overrides_and_supplements(t)
	_gating_and_undo_guard(t)
	_fuzzy_ranking(t)
	_wipe(TMP)
	_wipe(CommandRegistry.USER_DIR)


func _roots(t) -> void:
	var roots := CommandRegistry.default_roots()
	t.eq(roots.size(), 2, "built-in root then user root")
	t.eq(roots[0], BUILTIN)
	t.eq(roots[1], CommandRegistry.USER_DIR)
	# C12: user:// is the engine's portable config root. A literal
	# separator here would be a Linux-only path.
	t.ok(str(roots[1]).begins_with("user://"), "user root is user://")
	t.ok(not str(roots[1]).contains("\\"), "no windows separator")
	t.ok(CommandRegistry.ensure_user_dir(), "user command dir is created")
	t.ok(DirAccess.dir_exists_absolute(CommandRegistry.USER_DIR))


func _scan_is_deterministic(t) -> void:
	var a := CommandRegistry.new()
	a.scan(PackedStringArray([BUILTIN]))
	t.ok(a.size() >= 8, "built-ins registered")
	t.eq(a.errors.size(), 0, "clean built-in scan: %s" % str(a.errors))
	var ids := a.ids()
	var sorted := PackedStringArray(ids)
	sorted.sort()
	t.eq(ids, sorted, "registration order is id-sorted")
	var b := CommandRegistry.new()
	b.scan(PackedStringArray([BUILTIN]))
	t.eq(b.ids(), ids, "a second scan gives the same order")
	t.ok(a.get_command("view.frame_map") != null)
	t.ok(a.get_command("nope.missing") == null)


func _bad_scripts_are_skipped(t) -> void:
	_wipe(TMP)
	DirAccess.make_dir_recursive_absolute(TMP)
	_write(TMP, "a_good.gd", """extends EditorCommand
func _init() -> void:
	id = "zz.good"
	title = "Good"
func run(_ctx) -> void:
	pass
""")
	_write(TMP, "b_no_run.gd", """extends RefCounted
var id := "zz.no_run"
""")
	_write(TMP, "c_no_id.gd", """extends RefCounted
var id := ""
func run(_ctx) -> void:
	pass
""")
	_write(TMP, "d_node.gd", """extends Node
var id := "zz.node"
func run(_ctx) -> void:
	pass
""")
	_write(TMP, "e_bad_list.gd", """extends RefCounted
func command_list() -> int:
	return 7
func run(_ctx) -> void:
	pass
""")
	# A file that will not parse. The engine prints its own parse error, so
	# mute error output for the load or the suite reads it as a test fault.
	_write(TMP, "f_broken.gd", """extends RefCounted
func run(_ctx) -> void
	)))) not gdscript
""")
	var reg := CommandRegistry.new()
	var was := Engine.print_error_messages
	Engine.print_error_messages = false
	reg.scan(PackedStringArray([TMP]))
	Engine.print_error_messages = was

	t.eq(reg.size(), 1, "only the well-formed script registered")
	t.eq(reg.ids(), PackedStringArray(["zz.good"]))
	t.eq(reg.errors.size(), 5, "one logged reason per rejected file")
	var joined := "\n".join(PackedStringArray(reg.errors))
	t.ok(joined.contains("no run()"), "missing run() named")
	t.ok(joined.contains("no id"), "missing id named")
	t.ok(joined.contains("not a Node"), "Node command named")
	t.ok(joined.contains("command_list()"), "bad command_list named")
	t.ok(joined.contains("does not compile"), "parse failure named")
	for line in reg.errors:
		t.ok(str(line).contains(TMP), "every error names its file")


func _user_root_overrides_and_supplements(t) -> void:
	_wipe(TMP)
	DirAccess.make_dir_recursive_absolute(TMP)
	_write(TMP, "override.gd", """extends EditorCommand
func _init() -> void:
	id = "view.frame_map"
	title = "Frame map (mine)"
func run(_ctx) -> void:
	pass
""")
	_write(TMP, "extra.gd", """extends EditorCommand
func _init() -> void:
	id = "zz.extra"
	title = "Extra"
func run(_ctx) -> void:
	pass
""")
	var only_builtin := CommandRegistry.new()
	only_builtin.scan(PackedStringArray([BUILTIN]))
	var both := CommandRegistry.new()
	both.scan(PackedStringArray([BUILTIN, TMP]))
	t.eq(both.size(), only_builtin.size() + 1, "one new id supplements")
	t.eq(
		str(both.get_command("view.frame_map").get("title")),
		"Frame map (mine)",
		"the later root wins the id",
	)
	t.eq(both.overrides.size(), 1, "the override is recorded, not silent")
	t.ok(str(both.overrides[0]).begins_with("view.frame_map"))
	t.ok(both.get_command("zz.extra") != null)
	var ids := both.ids()
	var sorted := PackedStringArray(ids)
	sorted.sort()
	t.eq(ids, sorted, "mixed roots still sort by id")


func _gating_and_undo_guard(t) -> void:
	_wipe(TMP)
	DirAccess.make_dir_recursive_absolute(TMP)
	_write(TMP, "gated.gd", """extends EditorCommand
var ran := 0
func _init() -> void:
	id = "zz.gated"
	title = "Gated"
func is_enabled() -> bool:
	return false
func run(_ctx) -> void:
	ran += 1
""")
	_write(TMP, "liar.gd", """extends EditorCommand
func _init() -> void:
	id = "zz.liar"
	title = "Liar"
	mutates_map = true
func run(_ctx) -> void:
	pass
""")
	var reg := CommandRegistry.new()
	reg.scan(PackedStringArray([TMP]))
	var lines: Array[String] = []
	var ctx := CommandContext.new()
	ctx.bind(CommandContext.HOOK_LOG, func(msg: String) -> void:
		lines.append(msg)
	)
	t.ok(not reg.run_command("zz.nope", ctx), "unknown id refused")
	t.ok(str(lines[-1]).contains("no such command"))
	t.ok(not reg.run_command("zz.gated", ctx), "is_enabled() gates run")
	t.ok(str(lines[-1]).contains("unavailable"))
	t.eq(int(reg.get_command("zz.gated").get("ran")), 0,
		"a gated command never executes")
	# C16: declaring a map edit and pushing no undo entry is a defect the
	# registry names out loud.
	var before := UndoStack.command_count()
	t.ok(reg.run_command("zz.liar", ctx))
	t.eq(UndoStack.command_count(), before)
	t.ok(str(lines[-1]).contains("without an undo entry"))


func _fuzzy_ranking(t) -> void:
	t.eq(CommandRegistry.match_score("zzz", "Frame map"), -1, "miss is -1")
	t.ok(
		CommandRegistry.match_score("frame", "Frame map")
			> CommandRegistry.match_score("frame", "Refine frame edges"),
		"a prefix outranks a mid-word hit",
	)
	t.ok(
		CommandRegistry.match_score("map", "Map mode")
			> CommandRegistry.match_score("map", "Manage apex"),
		"a contiguous run outranks scattered letters",
	)
	t.ok(
		CommandRegistry.match_score("gv", "Ghost variants")
			> CommandRegistry.match_score("gv", "Merging vectors"),
		"word-initial letters outrank mid-word ones",
	)
	t.ok(CommandRegistry.match_score("frame map", "Frame map") > 0,
		"spaces separate terms and never have to match")

	var reg := CommandRegistry.new()
	reg.scan(PackedStringArray([BUILTIN]))
	t.eq(reg.filter("").size(), reg.size(), "empty query keeps everything")
	t.eq(reg.filter("")[0], reg.commands[0], "empty query keeps the order")
	var framed := reg.filter("frame")
	t.ok(not framed.is_empty())
	t.eq(str(framed[0].get("id")), "view.frame_map", "best match first")
	t.eq(reg.filter("qqqqqq").size(), 0, "no match is an empty list")
	var validated := reg.filter("valid")
	t.eq(str(validated[0].get("id")), "map.validate")
	var filters := reg.filter("view filter")
	t.ok(filters.size() >= 13, "the category itself is searchable")


func _write(dir: String, name: String, body: String) -> void:
	var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(body)
	f.close()


func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if not d.current_is_dir():
			d.remove(fn)
		fn = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(dir)
