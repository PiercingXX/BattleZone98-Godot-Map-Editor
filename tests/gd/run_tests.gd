extends SceneTree
## Headless assert runner. Each tests/gd/test_*.gd exposes run(t).

func _init() -> void:
	call_deferred("_go")


func _go() -> void:
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
			names.append(fn)
		fn = dir.get_next()
	names.sort()
	if names.is_empty():
		print("no test_*.gd files under tests/gd/")
		quit(2)
		return

	var passed := 0
	var failed_tests := 0
	for name in names:
		var script: GDScript = load("res://tests/gd/%s" % name) as GDScript
		if script == null:
			print("FAIL %s (load)" % name)
			failed_tests += 1
			continue
		var inst: RefCounted = script.new()
		var t := _Assert.new()
		t.name = name
		t.tree = self
		print("RUN  %s" % name)
		await inst.run(t)
		if t.failed > 0:
			print("FAIL %s (%d assertion(s))" % [name, t.failed])
			failed_tests += 1
		else:
			print("PASS %s" % name)
			passed += 1
	print("%d passed, %d failed" % [passed, failed_tests])
	quit(1 if failed_tests > 0 else 0)


class _Assert:
	extends RefCounted
	var name: String = ""
	var failed: int = 0
	var tree: SceneTree

	func eq(got: Variant, want: Variant, msg: String = "") -> void:
		if _same(got, want):
			return
		fail("%s  got=%s want=%s" % [msg, got, want])

	func ne(got: Variant, want: Variant, msg: String = "") -> void:
		if _same(got, want):
			fail("%s  both=%s" % [msg, got])

	func ok(cond: bool, msg: String = "") -> void:
		if not cond:
			fail(msg if not msg.is_empty() else "expected true")

	func near(got: float, want: float, eps: float = 0.0001, msg: String = "") -> void:
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
