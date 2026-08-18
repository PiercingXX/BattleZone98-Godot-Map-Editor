extends RefCounted
## GameTest: Sim Startup verdict parser, appended-bytes reader, launch URI.


func run(t) -> void:
	_verdict_parser(t)
	_count_sim_startup(t)
	_appended_bytes(t)
	_uri_and_paths(t)
	await _flow(t)


func _verdict_parser(t) -> void:
	var pass8 := GameTest.verdict_from_count(8, false)
	t.eq(pass8["kind"], GameTest.KIND_PASS)
	t.eq(pass8["message"], GameTest.MSG_PASS)
	t.eq(pass8["count"], 8)
	var pass_late := GameTest.verdict_from_count(8, true)
	t.eq(pass_late["kind"], GameTest.KIND_PASS, "8 is PASS even after the timeout clock")
	t.eq(GameTest.verdict_from_count(9, false)["kind"], GameTest.KIND_PASS)

	var mid3 := GameTest.verdict_from_count(3, false)
	t.eq(mid3["kind"], GameTest.KIND_PENDING, "3 is mid-load until timeout")
	t.eq(mid3["message"], "")
	var fail3 := GameTest.verdict_from_count(3, true)
	t.eq(fail3["kind"], GameTest.KIND_FAIL)
	t.eq(fail3["message"], GameTest.MSG_FAIL_INSTANTIATE)
	t.eq(fail3["count"], 3)

	var pending0 := GameTest.verdict_from_count(0, false)
	t.eq(pending0["kind"], GameTest.KIND_PENDING)
	var timeout0 := GameTest.verdict_from_count(0, true)
	t.eq(timeout0["kind"], GameTest.KIND_TIMEOUT)
	t.eq(timeout0["message"], GameTest.MSG_TIMEOUT)

	var timeout5 := GameTest.verdict_from_count(5, true)
	t.eq(timeout5["kind"], GameTest.KIND_TIMEOUT, "other incomplete counts are no-verdict")
	t.eq(timeout5["message"], GameTest.MSG_TIMEOUT)
	t.eq(GameTest.verdict_from_count(1, false)["kind"], GameTest.KIND_PENDING)
	t.eq(GameTest.verdict_from_count(7, false)["kind"], GameTest.KIND_PENDING)


func _count_sim_startup(t) -> void:
	t.eq(GameTest.count_sim_startup(""), 0)
	t.eq(GameTest.count_sim_startup("hello\nworld\n"), 0)
	t.eq(GameTest.count_sim_startup("Sim Startup: Starting Simulator\n"), 1)
	var eight := "\n".join(PackedStringArray([
		"Starting BattleZone 98 Redux, Version 2.2.301, PC Steam",
		"Created windowed window sized (1024,768)",
		"Sim Startup: Starting Simulator",
		"Sim Startup: Mission Preload after 10 ms initializing",
		"Starting Game Simulator",
		"Sim Startup: Mission Load after 20 ms initializing",
		"Sim Startup: Check Resave after 21 ms initializing",
		"Sim Startup: Post Load after 22 ms initializing",
		"Sim Startup: Waiting For VO at 23 ms initializing",
		"Sim Startup: VO complete at 24 ms initializing",
		"Sim Startup: First Frame after 2635 ms initializing",
		"(Tank) is loading (obj #0)",
	]))
	t.eq(GameTest.count_sim_startup(eight), 8, "real 8-phase log")
	t.eq(GameTest.verdict_from_count(GameTest.count_sim_startup(eight), false)["kind"], GameTest.KIND_PASS)

	var three := "\n".join(PackedStringArray([
		"Sim Startup: Starting Simulator",
		"Sim Startup: Mission Preload after 10 ms initializing",
		"Sim Startup: Mission Load after 20 ms initializing",
		"Could not load \"xtbad.bzn\"",
	]))
	t.eq(GameTest.count_sim_startup(three), 3)
	t.eq(GameTest.verdict_from_count(GameTest.count_sim_startup(three), true)["kind"], GameTest.KIND_FAIL)

	var crlf := "Sim Startup: A\r\nnoise\r\nSim Startup: B\r\n"
	t.eq(GameTest.count_sim_startup(crlf), 2, "CRLF lines still match")
	t.eq(GameTest.count_sim_startup("sim startup: lowercase is not a hit\n"), 0)
	t.eq(GameTest.count_sim_startup("prefix Sim Startup suffix twice Sim Startup\n"), 1, "count lines, not occurrences")


func _appended_bytes(t) -> void:
	var tmp := OS.get_temp_dir().path_join("bz_game_test_log_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var path := tmp.path_join("BZLogger.txt")

	t.eq(GameTest.file_size_or_zero(path), 0, "missing file is size 0")
	var missing := GameTest.read_appended(path, 0)
	t.ok(bool(missing["ok"]))
	t.eq(missing["offset"], 0)
	t.eq(str(missing["text"]), "")
	t.eq((missing["bytes"] as PackedByteArray).size(), 0)
	t.ok(not bool(missing["truncated"]))

	var prior := GameTest.read_appended(path, 40)
	t.eq(prior["offset"], 40, "absent file keeps the caller's offset")

	_write_text(path, "AAAA")
	t.eq(GameTest.file_size_or_zero(path), 4)
	var first := GameTest.read_appended(path, 0)
	t.eq(str(first["text"]), "AAAA")
	t.eq(int(first["offset"]), 4)
	t.ok(not bool(first["truncated"]))

	_append_text(path, "BBBB")
	var second := GameTest.read_appended(path, 4)
	t.eq(str(second["text"]), "BBBB", "only appended bytes")
	t.eq(int(second["offset"]), 8)
	t.eq((second["bytes"] as PackedByteArray).size(), 4)

	var none := GameTest.read_appended(path, 8)
	t.eq(str(none["text"]), "", "no new bytes")
	t.eq(int(none["offset"]), 8)

	_write_text(path, "NEW")
	var truncated := GameTest.read_appended(path, 8)
	t.ok(bool(truncated["truncated"]), "shorter file is a rewrite")
	t.eq(str(truncated["text"]), "NEW")
	t.eq(int(truncated["offset"]), 3)

	var phases := ""
	for i in 8:
		phases += "Sim Startup: phase %d\n" % i
	_write_text(path, "old boot\n")
	var mark := GameTest.file_size_or_zero(path)
	_append_text(path, phases)
	var tail := GameTest.read_appended(path, mark)
	t.eq(GameTest.count_sim_startup(str(tail["text"])), 8, "tail-only count ignores pre-launch log")
	t.eq(GameTest.count_sim_startup("old boot\n" + str(tail["text"])), 8)

	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(tmp)


func _uri_and_paths(t) -> void:
	t.eq(GameTest.bzn_name("xtcrater", ""), "xtcrater.bzn")
	t.eq(GameTest.bzn_name("xtcrater", "_SW"), "xtcrater_SW.bzn")
	t.eq(
		GameTest.steam_run_uri("xtcrater", "_SW"),
		"steam://run/301650//xtcrater_SW.bzn /startedit /win",
	)
	t.eq(
		GameTest.steam_run_uri("foo"),
		"steam://run/301650//foo.bzn /startedit /win",
	)
	var root := "/games/Battlezone 98 Redux"
	t.eq(GameTest.logger_path(root), root.path_join("BZLogger.txt"))


func _flow(t) -> void:
	var snap := _snapshot()
	var old_spawn: Callable = GameTest.spawn_steam
	var old_worker: Callable = Backend.test_worker
	UndoStack.clear()
	MapState.has_session = false
	Settings.game_root = ""

	var logs: Array = []
	var gt := GameTest.new()
	gt.name = "GameTestFlow"
	gt.log = func(msg): logs.append(str(msg))
	t.tree.root.add_child(gt)
	await t.tree.process_frame
	var idle := Time.get_ticks_msec() + 4000
	while Backend.busy or not Backend._queue.is_empty():
		await t.tree.process_frame
		if Time.get_ticks_msec() > idle:
			break

	t.ok(not gt.begin(), "begin refuses without a session")
	t.ok("open a map" in logs[logs.size() - 1])
	MapState.has_session = true
	MapState.stem = "xttest"
	t.ok(not gt.begin(), "begin refuses without a game root")
	t.ok("probe" in logs[logs.size() - 1])

	var tmp := OS.get_temp_dir().path_join("bz_game_test_flow_%d" % Time.get_ticks_usec())
	var install := tmp.path_join("install")
	DirAccess.make_dir_recursive_absolute(tmp)
	DirAccess.make_dir_recursive_absolute(install)
	MapState.session_dir = tmp
	MapState.active_variant = "_S"
	Settings.game_root = install

	var uris: Array = []
	GameTest.spawn_steam = func(uri: String) -> int:
		uris.append(uri)
		return 4242
	Backend.test_worker = func(_verb: String, _args: PackedStringArray) -> Dictionary:
		return {"ok": true, "mode": "addon", "files": ["xttest_S.bzn"], "dest": install.path_join("addon")}

	t.ok(gt.begin(), "begin starts with session + root")
	t.ok(gt.is_active())
	var deadline := Time.get_ticks_msec() + 4000
	while gt.is_active() and (Backend.busy or not Backend._queue.is_empty() or uris.is_empty()):
		await t.tree.process_frame
		if Time.get_ticks_msec() > deadline:
			break
	await t.tree.process_frame
	t.eq(uris, ["steam://run/301650//xttest_S.bzn /startedit /win"], "Steam URI uses stem+variant")
	t.ok(gt.is_active(), "poll is running after launch")

	gt.cancel()
	t.ok(not gt.is_active())
	t.eq(gt.last_verdict.get("kind"), GameTest.KIND_CANCELLED)
	t.ok("cancelled" in logs[logs.size() - 1])

	# Fresh run: append 8 phases after the recorded offset and poll.
	var log_path := GameTest.logger_path(install)
	_write_text(log_path, "pre-launch junk\nSim Startup: leftover\n")
	t.ok(gt.begin())
	deadline = Time.get_ticks_msec() + 4000
	while Backend.busy or not Backend._queue.is_empty():
		await t.tree.process_frame
		if Time.get_ticks_msec() > deadline:
			break
	await t.tree.process_frame
	t.ok(gt.is_active())
	var phases := ""
	for i in 8:
		phases += "Sim Startup: phase %d\n" % i
	_append_text(log_path, phases)
	gt._on_poll()
	t.ok(not gt.is_active(), "8/8 ends the poll immediately")
	t.eq(gt.last_verdict.get("kind"), GameTest.KIND_PASS)
	t.eq(gt.last_verdict.get("message"), GameTest.MSG_PASS)

	# Timeout at 3/8.
	t.ok(gt.begin())
	deadline = Time.get_ticks_msec() + 4000
	while Backend.busy or not Backend._queue.is_empty():
		await t.tree.process_frame
		if Time.get_ticks_msec() > deadline:
			break
	await t.tree.process_frame
	_append_text(log_path, "Sim Startup: A\nSim Startup: B\nSim Startup: C\n")
	gt._started_ms = Time.get_ticks_msec() - int(GameTest.TIMEOUT_SEC * 1000.0) - 10
	gt._on_poll()
	t.eq(gt.last_verdict.get("kind"), GameTest.KIND_FAIL)
	t.eq(gt.last_verdict.get("message"), GameTest.MSG_FAIL_INSTANTIATE)

	# Second press cancels via SessionIO.
	var shell := _Shell.new()
	shell._game_test = gt
	t.tree.root.add_child(shell)
	var io := SessionIO.new(shell, func(msg): logs.append(str(msg)))
	t.ok(gt.begin())
	deadline = Time.get_ticks_msec() + 4000
	while Backend.busy or not Backend._queue.is_empty():
		await t.tree.process_frame
		if Time.get_ticks_msec() > deadline:
			break
	await t.tree.process_frame
	t.ok(gt.is_active())
	io.test_in_game()
	t.ok(not gt.is_active(), "second Test press cancels")
	t.eq(gt.last_verdict.get("kind"), GameTest.KIND_CANCELLED)

	gt.queue_free()
	shell.queue_free()
	await t.tree.process_frame
	DirAccess.remove_absolute(log_path)
	DirAccess.remove_absolute(install)
	DirAccess.remove_absolute(tmp)
	GameTest.spawn_steam = old_spawn
	Backend.test_worker = old_worker
	UndoStack.clear()
	_restore(snap)


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _append_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	f.seek_end()
	f.store_string(text)
	f.close()


func _snapshot() -> Dictionary:
	return {
		"has_session": MapState.has_session,
		"stem": MapState.stem,
		"session_dir": MapState.session_dir,
		"active_variant": MapState.active_variant,
		"game_root": Settings.game_root,
	}


func _restore(snap: Dictionary) -> void:
	MapState.has_session = bool(snap["has_session"])
	MapState.stem = str(snap["stem"])
	MapState.session_dir = str(snap["session_dir"])
	MapState.active_variant = str(snap["active_variant"])
	Settings.game_root = str(snap["game_root"])


class _Shell:
	extends Node
	var _game_test: GameTest
