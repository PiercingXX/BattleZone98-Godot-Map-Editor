extends Node
## One-shot ``bzmap editor`` subprocess driver (docs/02).
##
## Invokes the interpreter with an argument array — never a shell string.
## Calls run off the main thread. stdout is one JSON object; stderr is
## surfaced verbatim. A FIFO queue serializes overlapping run() calls.

signal call_started(verb: String)
signal stderr_line(text: String)
signal call_finished(verb: String, result: Dictionary)
signal call_failed(verb: String, error: Dictionary)
signal discovered(ok: bool, detail: String)

const CONTRACT_VERSION := 1

var python_exe: String = ""
var bzmap_home: String = ""
var available: bool = false
var last_error: String = ""
var last_probe: Dictionary = {}
var busy: bool = false

## Tests may assign a Callable(verb, extra_args) -> Dictionary to skip python.
var test_worker: Callable = Callable()

var _thread: Thread
var _pending_verb: String = ""
var _queue: Array = []


func _ready() -> void:
	_discover()


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _discover() -> void:
	available = false
	last_error = ""
	var project_root := ProjectSettings.globalize_path("res://").rstrip("/")
	var override := _cmdline_bzmap()
	if override.is_empty():
		override = OS.get_environment("BZMAP_HOME")
	# Ignore settings that still point at a sibling generator checkout.
	var saved := Settings.bzmap_home
	if saved.contains("skippy-battlezone-map-generator") \
			or saved.contains("battlezone98-map-generator"):
		saved = ""

	var candidates: Array[String] = []
	if not override.is_empty():
		candidates.append(override)
	# In-repo backend is the default. No other git repo is required.
	candidates.append(project_root.path_join("backend"))
	if not saved.is_empty():
		candidates.append(saved)
	candidates.append(OS.get_executable_path().get_base_dir().path_join("backend"))

	for home in candidates:
		var resolved := _resolve_home(home)
		if resolved.is_empty():
			continue
		bzmap_home = resolved
		python_exe = _python_for(resolved, project_root)
		if python_exe.is_empty():
			continue
		if _can_import(python_exe, resolved):
			available = true
			OS.set_environment("PYTHONPATH", resolved)
			Settings.bzmap_home = resolved
			Settings.python_path = python_exe
			Settings.save()
			discovered.emit(true, "backend at %s (%s)" % [resolved, python_exe])
			return

	var path_python := _find_on_path()
	var bundled := project_root.path_join("backend")
	if not path_python.is_empty() and _can_import(path_python, bundled):
		python_exe = path_python
		bzmap_home = bundled
		available = true
		OS.set_environment("PYTHONPATH", bundled)
		discovered.emit(true, "backend via PATH (%s)" % path_python)
		return

	last_error = "bundled backend not found — from the repo root run: python3 -m venv .venv && .venv/bin/pip install -e backend"
	discovered.emit(false, last_error)


func _cmdline_bzmap() -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--bzmap" and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with("--bzmap="):
			return args[i].substr("--bzmap=".length())
	return ""


func _resolve_home(path: String) -> String:
	if path.is_empty():
		return ""
	var abs := path
	if not abs.is_absolute_path():
		abs = ProjectSettings.globalize_path(path)
	abs = abs.simplify_path()
	if FileAccess.file_exists(abs.path_join("bzmap").path_join("cli.py")):
		return abs
	if FileAccess.file_exists(abs.path_join("cli.py")):
		return abs.get_base_dir().get_base_dir()
	return ""


func _python_for(home: String, project_root: String = "") -> String:
	var bases: Array[String] = [home]
	if not project_root.is_empty():
		bases.append(project_root)
	for base in bases:
		var venv_unix := String(base).path_join(".venv").path_join("bin").path_join("python")
		var venv_win := String(base).path_join(".venv").path_join("Scripts").path_join("python.exe")
		if FileAccess.file_exists(venv_unix):
			return venv_unix
		if FileAccess.file_exists(venv_win):
			return venv_win
	return _find_on_path()


func _find_on_path() -> String:
	for name in ["python3", "python"]:
		var path_env := OS.get_environment("PATH")
		var sep := ";" if OS.get_name() == "Windows" else ":"
		for dir in path_env.split(sep):
			var candidate := String(dir).path_join(name)
			if OS.get_name() == "Windows":
				if FileAccess.file_exists(candidate + ".exe"):
					return candidate + ".exe"
			if FileAccess.file_exists(candidate):
				return candidate
	return ""


func _can_import(python: String, home: String) -> bool:
	var args := PackedStringArray(["-c", "import bzmap, bzmap.cli"])
	var output: Array = []
	var old_pp := OS.get_environment("PYTHONPATH")
	if not home.is_empty():
		OS.set_environment("PYTHONPATH", home)
	var code := OS.execute(python, args, output, true, false)
	if not home.is_empty():
		OS.set_environment("PYTHONPATH", old_pp)
	return code == 0


func run(verb: String, extra_args: PackedStringArray = PackedStringArray()) -> void:
	if not available:
		call_failed.emit(verb, {
			"code": "no_backend",
			"message": last_error if not last_error.is_empty() else "backend unavailable",
			"hint": "from the repo root: python3 -m venv .venv && .venv/bin/pip install -e backend",
		})
		return
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
	var argv := PackedStringArray(["-m", "bzmap.cli", "editor", verb])
	argv.append_array(extra_args)
	argv.append("--json")
	var output: Array = []
	var code := OS.execute(python_exe, argv, output, true, false)
	var combined := ""
	for line in output:
		combined += str(line)
		if not str(line).ends_with("\n"):
			combined += "\n"
	return {
		"verb": verb,
		"code": code,
		"stdout": combined,
		"stderr": "",
	}


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
	var verb := str(payload.get("verb", _pending_verb))
	var code := int(payload.get("code", -1))
	var stderr_text := str(payload.get("stderr", ""))
	var stdout_text := str(payload.get("stdout", ""))
	if not stderr_text.is_empty():
		_emit_noise_lines(stderr_text)
	var extracted := _extract_json_object(stdout_text)
	var json_start := int(extracted.get("start", -1))
	if json_start > 0:
		_emit_noise_lines(stdout_text.substr(0, json_start))
	var parsed: Dictionary = extracted.get("data", {})
	if parsed.is_empty():
		call_failed.emit(verb, {
			"code": "backend_crash",
			"message": "backend produced no parseable JSON",
			"hint": stdout_text if not stdout_text.is_empty() else stderr_text,
			"exit_code": code,
		})
		return
	if parsed.get("ok", false):
		if verb == "probe":
			last_probe = parsed
			_remember_game_root(parsed)
		call_finished.emit(verb, parsed)
	else:
		var err: Dictionary = parsed.get("error", {})
		if err.is_empty():
			err = {"code": "failed", "message": str(parsed)}
		call_failed.emit(verb, err)


func _emit_noise_lines(text: String) -> void:
	for line in text.split("\n"):
		if not line.is_empty():
			stderr_line.emit(line)


func _remember_game_root(probe: Dictionary) -> void:
	if not Settings.game_root.is_empty():
		return
	var installs: Array = probe.get("installs", [])
	for item in installs:
		if typeof(item) == TYPE_DICTIONARY and item.get("kind") == "game":
			Settings.game_root = str(item.get("path", ""))
			Settings.save()
			return


func _parse_json_object(text: String) -> Dictionary:
	var data: Dictionary = _extract_json_object(text).get("data", {})
	return data


func _extract_json_object(text: String) -> Dictionary:
	# stdout may carry log noise before the (pretty-printed) JSON reply.
	# rfind("{") would land on a nested object, so track brace depth outside
	# string literals and try each top-level "{" from the last one back.
	var candidates := PackedInt32Array()
	var depth := 0
	var in_string := false
	var escaped := false
	for i in text.length():
		var c := text.unicode_at(i)
		if c == 0x0A:  # valid JSON never has a raw newline inside a string
			in_string = false
			escaped = false
		elif in_string:
			if escaped:
				escaped = false
			elif c == 0x5C:  # backslash
				escaped = true
			elif c == 0x22:  # quote
				in_string = false
		elif c == 0x22:
			in_string = true
		elif c == 0x7B:  # {
			if depth == 0:
				candidates.append(i)
			depth += 1
		elif c == 0x7D:  # }
			depth = maxi(depth - 1, 0)
	var json := JSON.new()
	for k in range(candidates.size() - 1, -1, -1):
		if json.parse(text.substr(candidates[k])) == OK and typeof(json.data) == TYPE_DICTIONARY:
			return {"start": candidates[k], "data": json.data}
	# Unbalanced braces in the noise can hide the real "{" from the depth
	# scan; the plain last-brace slice still catches a flat trailing object.
	var last := text.rfind("{")
	if last >= 0 and not candidates.has(last):
		if json.parse(text.substr(last)) == OK and typeof(json.data) == TYPE_DICTIONARY:
			return {"start": last, "data": json.data}
	if json.parse(text.strip_edges()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		return {"start": 0, "data": json.data}
	return {"start": -1, "data": {}}


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


func package_pack(session_dir: String, out_dir: String) -> void:
	run("package", PackedStringArray([
		"--session", session_dir, "--mode", "pack", "--out", out_dir,
	]))
