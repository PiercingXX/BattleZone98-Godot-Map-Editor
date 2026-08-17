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
	var on_started := func(v): started.append(v)
	var on_finished := func(v, _r): finished.append(v)
	var on_failed := func(v, e): failed.append("%s:%s" % [v, e])
	Backend.call_started.connect(on_started)
	Backend.call_finished.connect(on_finished)
	Backend.call_failed.connect(on_failed)

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

	Backend.call_started.disconnect(on_started)
	Backend.call_finished.disconnect(on_finished)
	Backend.call_failed.disconnect(on_failed)
	Backend.test_worker = old_worker
	Backend.available = was_available


func _stub(verb: String, _args: PackedStringArray) -> Dictionary:
	return {
		"verb": verb,
		"code": 0,
		"stdout": "{\"ok\": true, \"verb\": \"%s\"}" % verb,
		"stderr": "",
	}
