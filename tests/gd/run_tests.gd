extends SceneTree
## Headless assert runner. Each tests/gd/test_*.gd exposes run(t).

func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	# Optional filter: `godot ... -s res://tests/gd/run_tests.gd -- test_foo.gd
	# test_bar.gd` runs only the named files. scripts/test-editor.sh uses this
	# to isolate each test file in its own process with its own timeout.
	var only: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("test_") and arg.ends_with(".gd"):
			only.append(arg)
	var names: Array[String] = []
	var dir := DirAccess.open("res://tests/gd")
	if dir == null:
		push_error("cannot open res://tests/gd")
		quit(2)
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.begins_with("test_") and fn.ends_with(".gd"):
			if only.is_empty() or only.has(fn):
				names.append(fn)
		fn = dir.get_next()
	names.sort()
	if names.is_empty():
		print("no test_*.gd files under tests/gd/")
		quit(2)
		return

	var passed := 0
	var failed_tests := 0
	var skipped_tests := 0
	for name in names:
		var script: GDScript = load("res://tests/gd/%s" % name) as GDScript
		if script == null:
			print("FAIL %s (load)" % name)
			failed_tests += 1
			continue
		# A script that fails to PARSE still loads as a GDScript. Calling new()
		# on it raises "Nonexistent function 'new'", which aborts _go before it
		# can quit() -- the process then spins forever and a one-line typo in a
		# test reads as a hung suite with no verdict. can_instantiate() asks
		# without calling.
		if not script.can_instantiate():
			print("FAIL %s (does not compile)" % name)
			failed_tests += 1
			continue
		var inst: RefCounted = script.new()
		if inst == null or not inst.has_method("run"):
			print("FAIL %s (no run())" % name)
			failed_tests += 1
			continue
		var t := _Assert.new()
		t.name = name
		t.tree = self
		print("RUN  %s" % name)
		await inst.run(t)
		if t.failed > 0:
			print("FAIL %s (%d assertion(s))" % [name, t.failed])
			failed_tests += 1
		elif t.skipped:
			print("SKIP %s (%d check(s) ran; %s)" % [name, t.checks, t.skip_reason])
			skipped_tests += 1
		else:
			print("PASS %s" % name)
			passed += 1
	print("%d passed, %d failed, %d skipped" % [passed, failed_tests, skipped_tests])
	# 3 = something was skipped and nothing failed. scripts/test-editor.sh maps
	# that to SKIP, so an absent precondition reads as neither a pass nor a
	# regression. Any real assertion failure still exits 1.
	if failed_tests > 0:
		quit(1)
		return
	quit(3 if skipped_tests > 0 else 0)


class _Assert:
	extends RefCounted
	var name: String = ""
	var failed: int = 0
	var tree: SceneTree
	## Set by skip()/require_files(). A skipped file is neither a pass nor a
	## failure: the machine could not satisfy a precondition.
	var skipped: bool = false
	var skip_reason: String = ""
	## Assertions attempted. A skipped file still reports this so a partial
	## run ("everything but the fixture cases") is visible, not silent.
	var checks: int = 0

	## Record that some or all of this file could not run. Use it only for
	## preconditions the checkout genuinely cannot supply — chiefly the
	## corpus/synthetic *.bzn fixtures, which .gitignore excludes under
	## AGENTS.md rule 3 and which no CI runner will ever have.
	func skip(reason: String) -> void:
		skipped = true
		if skip_reason.is_empty():
			skip_reason = reason

	## Guard for a fixture-dependent block. Returns false (and marks the file
	## skipped) when any path is absent, so the caller can `return` instead of
	## asserting against data it does not have.
	func require_files(paths: Array, why: String) -> bool:
		for p in paths:
			if not FileAccess.file_exists(str(p)):
				skip("%s (missing %s)" % [why, p])
				return false
		return true

	func eq(got: Variant, want: Variant, msg: String = "") -> void:
		checks += 1
		if _same(got, want):
			return
		fail("%s  got=%s want=%s" % [msg, got, want])

	func ne(got: Variant, want: Variant, msg: String = "") -> void:
		checks += 1
		if _same(got, want):
			fail("%s  both=%s" % [msg, got])

	func ok(cond: bool, msg: String = "") -> void:
		checks += 1
		if not cond:
			fail(msg if not msg.is_empty() else "expected true")

	func near(got: float, want: float, eps: float = 0.0001, msg: String = "") -> void:
		checks += 1
		if absf(got - want) > eps:
			fail("%s  got=%s want=%s ±%s" % [msg, got, want, eps])

	func fail(msg: String) -> void:
		failed += 1
		print("  FAIL %s: %s" % [name, msg])

	func _same(a: Variant, b: Variant) -> bool:
		if typeof(a) == typeof(b):
			return a == b
		# JSON numbers land as float; allow int/float equality.
		if (typeof(a) == TYPE_INT and typeof(b) == TYPE_FLOAT) \
				or (typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_INT):
			return float(a) == float(b)
		return false
