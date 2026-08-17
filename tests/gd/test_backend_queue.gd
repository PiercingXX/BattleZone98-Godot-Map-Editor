extends RefCounted
## Enqueue while busy → sequential execution. Stub the worker; no python.


func run(t) -> void:
	var started: Array = []
	var finished: Array = []
	var failed: Array = []
	var was_available: bool = Backend.available
	var old_worker: Callable = Backend.test_worker

	Backend.available = true
	Backend.test_worker = _stub
	var s1 := Backend.call_started.connect(func(v): started.append(v))
	var s2 := Backend.call_finished.connect(func(v, _r): finished.append(v))
	var s3 := Backend.call_failed.connect(func(v, e): failed.append("%s:%s" % [v, e]))

	Backend.run("probe")
	Backend.run("worlds")
	Backend.run("assets")

	var deadline := Time.get_ticks_msec() + 4000
	while Backend.busy or not Backend._queue.is_empty():
		await t.tree.process_frame
		if Time.get_ticks_msec() > deadline:
			t.fail("queue did not drain")
			break
	# One extra frame so the last _finish_call lands in the arrays.
	await t.tree.process_frame

	t.eq(failed, [], "no busy / crash failures")
	t.eq(started, ["probe", "worlds", "assets"], "sequential start")
	t.eq(finished, ["probe", "worlds", "assets"], "sequential finish")

	Backend.call_started.disconnect(s1)
	Backend.call_finished.disconnect(s2)
	Backend.call_failed.disconnect(s3)
	Backend.test_worker = old_worker
	Backend.available = was_available


func _stub(verb: String, _args: PackedStringArray) -> Dictionary:
	return {
		"verb": verb,
		"code": 0,
		"stdout": "{\"ok\": true, \"verb\": \"%s\"}" % verb,
		"stderr": "",
	}
