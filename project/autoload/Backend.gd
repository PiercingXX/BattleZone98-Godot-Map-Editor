extends Node
## In-process backend driver (docs/02 verbs, docs/03 port).
##
## The verbs run on a worker thread against the GDScript backend in
## project/backend/ — no subprocess, no Python. Payload shapes are
## unchanged from the bridge contract (docs/02 §3), so the UI is
## agnostic to the port. A FIFO queue serializes overlapping run() calls.

signal call_started(verb: String)
signal stderr_line(text: String)
signal call_finished(verb: String, result: Dictionary)
signal call_failed(verb: String, error: Dictionary)
signal discovered(ok: bool, detail: String)

const CONTRACT_VERSION := 1

var available: bool = true
var last_error: String = ""
var last_probe: Dictionary = {}
var busy: bool = false

## Tests may assign a Callable(verb, extra_args) -> Dictionary payload
## to stub the worker.
var test_worker: Callable = Callable()

var _thread: Thread
var _pending_verb: String = ""
var _queue: Array = []


func _ready() -> void:
	discovered.emit.call_deferred(true, "in-process GDScript backend")


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func run(verb: String, extra_args: PackedStringArray = PackedStringArray()) -> void:
	# Always go through the queue so calls made from finish handlers
	# (while earlier calls are still queued) keep FIFO order.
	_queue.append({"verb": verb, "args": extra_args})
	_try_dequeue()


func _begin(verb: String, extra_args: PackedStringArray) -> void:
	busy = true
	_pending_verb = verb
	call_started.emit(verb)
	_thread = Thread.new()
	if test_worker.is_valid():
		_thread.start(test_worker.bind(verb, extra_args))
	else:
		_thread.start(_worker.bind(verb, extra_args))


func _worker(verb: String, extra_args: PackedStringArray) -> Dictionary:
	var a := _parse_args(extra_args)
	var flags: Dictionary = a["flags"]
	var positional: Array = a["positional"]
	var payload: Dictionary
	match verb:
		"probe":
			var found: Dictionary = BzDiscover.discover()
			payload = {
				"ok": true,
				"contract_version": CONTRACT_VERSION,
				"backend": "gdscript",
				"installs": found.get("installs", []),
				"warnings": found.get("warnings", []),
			}
		"worlds":
			payload = BzWorlds.worlds_from_game(str(flags.get("game-root", "")))
		"new":
			payload = BzNew.create_map(
				str(flags.get("stem", "")),
				str(flags.get("world", "")),
				int(str(flags.get("width", "0"))),
				int(str(flags.get("depth", "0"))),
				str(flags.get("session", "")),
				str(flags.get("game-root", "")),
				int(str(flags.get("base-height", "1000"))),
				str(flags.get("pack-kind", "bzp")),
			)
		"open":
			payload = BzOpen.open_map(
				str(positional[0]) if positional.size() > 0 else "",
				str(flags.get("session", "")),
			)
		"save":
			payload = BzSave.save_session(
				str(flags.get("session", "")),
				str(flags.get("out", "")),
				str(flags.get("stem", "")),
			)
		"validate":
			payload = BzValidate.validate_session(
				str(flags.get("session", "")),
				str(flags.get("tier", "1,2")),
				str(flags.get("game-root", "")),
			)
		"assets":
			payload = BzAssets.build_assets(
				str(flags.get("game-root", "")),
				str(flags.get("cache", "")),
				null,
				flags.has("refresh"),
				not flags.has("no-convert"),
			)
		"render":
			payload = BzRender.render_session(
				str(flags.get("session", "")),
				str(flags.get("out", "")),
				flags.has("debug"),
			)
		"package":
			payload = BzPackage.package_session(
				str(flags.get("session", "")),
				str(flags.get("mode", "")),
				str(flags.get("game-root", "")),
				str(flags.get("test-id", "")),
				str(flags.get("out", "")),
			)
		_:
			payload = BzErrors.err("no_verb", "unknown editor verb: %s" % verb)
	if typeof(payload) != TYPE_DICTIONARY or payload.is_empty():
		payload = BzErrors.err(
			"backend_crash",
			"verb %s returned no payload" % verb,
			"the session was not modified beyond what the verb had already written",
		)
	if not payload.has("ok"):
		payload["ok"] = true
	return payload


## CLI-style flag array → {"flags": {name: value-or-true}, "positional": [...]}.
## Mirrors the argparse surface of the old subprocess bridge so the public
## wrapper methods (and their callers) stay unchanged.
static func _parse_args(args: PackedStringArray) -> Dictionary:
	var flags := {}
	var positional: Array = []
	const VALUE_FLAGS := [
		"game-root", "session", "out", "stem", "world", "width", "depth",
		"base-height", "pack-kind", "tier", "cache", "pack", "mode", "test-id",
	]
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg.begins_with("--"):
			var name := arg.substr(2)
			if name.contains("="):
				flags[name.get_slice("=", 0)] = name.substr(name.find("=") + 1)
			elif VALUE_FLAGS.has(name) and i + 1 < args.size():
				flags[name] = args[i + 1]
				i += 1
			else:
				flags[name] = true
		else:
			positional.append(arg)
		i += 1
	return {"flags": flags, "positional": positional}


func _process(_delta: float) -> void:
	if _thread == null or not _thread.is_started():
		return
	if _thread.is_alive():
		return
	var payload: Dictionary = _thread.wait_to_finish()
	_thread = null
	busy = false
	_finish_call(payload)
	_try_dequeue()


func _try_dequeue() -> void:
	if busy or _queue.is_empty():
		return
	var item: Dictionary = _queue.pop_front()
	_begin(str(item.get("verb", "")), item.get("args", PackedStringArray()))


func _finish_call(payload: Dictionary) -> void:
	var verb := _pending_verb
	if payload.get("ok", false):
		if verb == "probe":
			last_probe = payload
			_remember_game_root(payload)
		call_finished.emit(verb, payload)
	else:
		var err: Dictionary = payload.get("error", {})
		if err.is_empty():
			err = {"code": "failed", "message": str(payload)}
		last_error = str(err.get("message", ""))
		call_failed.emit(verb, err)


func _remember_game_root(probe_payload: Dictionary) -> void:
	if not Settings.game_root.is_empty():
		return
	var installs: Array = probe_payload.get("installs", [])
	for item in installs:
		if typeof(item) == TYPE_DICTIONARY and item.get("kind") == "game":
			Settings.game_root = str(item.get("path", ""))
			Settings.save()
			return


func probe() -> void:
	run("probe")


func worlds(game_root: String) -> void:
	run("worlds", PackedStringArray(["--game-root", game_root]))


func open_map(path: String, session_dir: String) -> void:
	run("open", PackedStringArray([path, "--session", session_dir]))


func save_map(session_dir: String, out_dir: String, stem: String = "") -> void:
	var args := PackedStringArray(["--session", session_dir, "--out", out_dir])
	if not stem.is_empty():
		args.append_array(PackedStringArray(["--stem", stem]))
	run("save", args)


func new_map(stem: String, world: String, width_m: int, depth_m: int, session_dir: String, game_root: String, pack_kind: String = "bzp") -> void:
	run("new", PackedStringArray([
		"--stem", stem,
		"--world", world,
		"--width", str(width_m),
		"--depth", str(depth_m),
		"--session", session_dir,
		"--game-root", game_root,
		"--pack-kind", pack_kind,
	]))


func validate(session_dir: String, game_root: String = "") -> void:
	var args := PackedStringArray(["--session", session_dir])
	if not game_root.is_empty():
		args.append_array(PackedStringArray(["--game-root", game_root]))
	run("validate", args)


func assets(game_root: String, cache: String, refresh: bool = false, convert: bool = true) -> void:
	var args := PackedStringArray(["--game-root", game_root, "--cache", cache])
	if refresh:
		args.append("--refresh")
	if not convert:
		args.append("--no-convert")
	run("assets", args)


func render_map(session_dir: String, out_dir: String) -> void:
	run("render", PackedStringArray(["--session", session_dir, "--out", out_dir]))


func package_install(session_dir: String, game_root: String, test_id: String = "") -> void:
	var args := PackedStringArray([
		"--session", session_dir, "--mode", "install", "--game-root", game_root,
	])
	if not test_id.is_empty():
		args.append_array(PackedStringArray(["--test-id", test_id]))
	run("package", args)


## Terrain-test build: same map, every script stripped. See BzPackage._install_addon.
func package_test(session_dir: String, game_root: String) -> void:
	run("package", PackedStringArray([
		"--session", session_dir, "--mode", "test", "--game-root", game_root,
	]))


func package_addon(session_dir: String, game_root: String) -> void:
	run("package", PackedStringArray([
		"--session", session_dir, "--mode", "addon", "--game-root", game_root,
	]))


func package_pack(session_dir: String, out_dir: String) -> void:
	run("package", PackedStringArray([
		"--session", session_dir, "--mode", "pack", "--out", out_dir,
	]))
