extends Node
## One-shot ``bzmap editor`` subprocess driver (docs/02).
##
## Invokes the interpreter with an argument array — never a shell string.
## Calls run off the main thread. stdout is one JSON object; stderr is
## surfaced verbatim.

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

var _thread: Thread
var _pending_verb: String = ""


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
			Settings.bzmap_home = resolved
			Settings.python_path = python_exe
			Settings.save()
			discovered.emit(true, "backend at %s (%s)" % [resolved, python_exe])
			return

	var path_python := _find_on_path()
	if not path_python.is_empty() and _can_import(path_python, project_root.path_join("backend")):
		python_exe = path_python
		bzmap_home = project_root.path_join("backend")
		available = true
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
		var out: Array = []
		# `command -v` is a shell-ism — walk PATH ourselves.
		var path_env := OS.get_environment("PATH")
		var sep := ";" if OS.get_name() == "Windows" else ":"
		for dir in path_env.split(sep):
			var candidate := String(dir).path_join(name)
			if OS.get_name() == "Windows":
				if FileAccess.file_exists(candidate + ".exe"):
					return candidate + ".exe"
			if FileAccess.file_exists(candidate):
				return candidate
		# Silence unused.
		var _u: Array = out
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
	if busy:
		call_failed.emit(verb, {
			"code": "busy",
			"message": "a backend call is already running",
		})
		return
	if not available:
		call_failed.emit(verb, {
			"code": "no_backend",
			"message": last_error if not last_error.is_empty() else "backend unavailable",
			"hint": "from the repo root: python3 -m venv .venv && .venv/bin/pip install -e backend",
		})
		return
	busy = true
	_pending_verb = verb
	call_started.emit(verb)
	_thread = Thread.new()
	_thread.start(_worker.bind(verb, extra_args))


func _worker(verb: String, extra_args: PackedStringArray) -> Dictionary:
	var argv := PackedStringArray(["-m", "bzmap.cli", "editor", verb])
	argv.append_array(extra_args)
	argv.append("--json")
	var old_pp := OS.get_environment("PYTHONPATH")
	if not bzmap_home.is_empty():
		OS.set_environment("PYTHONPATH", bzmap_home)
	var stdout_text := ""
	var stderr_text := ""
	var code := -1
	if OS.has_method("execute_with_pipe"):
		var pipe: Variant = OS.call("execute_with_pipe", python_exe, argv, true)
		if typeof(pipe) == TYPE_DICTIONARY and not pipe.is_empty():
			var stdout_f: FileAccess = pipe.get("stdio")
			var stderr_f: FileAccess = pipe.get("stderr")
			if stdout_f:
				stdout_text = stdout_f.get_as_text()
			if stderr_f:
				stderr_text = stderr_f.get_as_text()
			code = 0 if stdout_text.strip_edges().begins_with("{") else 1
		else:
			code = -1
	if stdout_text.is_empty():
		var output: Array = []
		code = OS.execute(python_exe, argv, output, true, false)
		var combined := ""
		for line in output:
			combined += str(line)
			if not str(line).ends_with("\n"):
				combined += "\n"
		stdout_text = combined
	if not bzmap_home.is_empty():
		OS.set_environment("PYTHONPATH", old_pp)
	return {
		"verb": verb,
		"code": code,
		"stdout": stdout_text,
		"stderr": stderr_text,
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


func _finish_call(payload: Dictionary) -> void:
	var verb := str(payload.get("verb", _pending_verb))
	var stderr_text := str(payload.get("stderr", ""))
	if not stderr_text.is_empty():
		for line in stderr_text.split("\n"):
			if not line.is_empty():
				stderr_line.emit(line)
	var stdout_text := str(payload.get("stdout", ""))
	var parsed := _parse_json_object(stdout_text)
	if parsed.is_empty():
		call_failed.emit(verb, {
			"code": "backend_crash",
			"message": "backend produced no parseable JSON",
			"hint": stdout_text if not stdout_text.is_empty() else stderr_text,
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
	# stdout may have been mixed with stderr; take the last JSON object.
	var start := text.rfind("{")
	if start < 0:
		return {}
	var slice := text.substr(start)
	var json := JSON.new()
	if json.parse(slice) != OK:
		# Try the whole text.
		if json.parse(text.strip_edges()) != OK:
			return {}
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


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
