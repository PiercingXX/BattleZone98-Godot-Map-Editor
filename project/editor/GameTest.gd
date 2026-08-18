extends Node
class_name GameTest
## In-game play-test: persist, addon install, Steam launch, BZLogger poll.
##
## The game only loads authored maps from <install>/addon/. Launch is
## `steam steam://run/301650//<stem>.bzn /startedit /win` (the exe relaunches
## through Steam if invoked directly). BZLogger.txt is written next to the exe.
## Verdict = count of appended lines containing "Sim Startup": 8 = loaded,
## 3 = died instantiating objects, 0 = never reached the map. Failure is a
## modal dialog that never exits — never wait for process exit.

signal running_changed(active: bool)

const STEAM_APP_ID := "301650"
const STEAM_EXE := "steam"
const LOGGER_NAME := "BZLogger.txt"
const SIM_NEEDLE := "Sim Startup"
const SIM_PHASES := 8
const INSTANTIATE_FAIL_COUNT := 3
const POLL_SEC := 2.0
const TIMEOUT_SEC := 150.0

const KIND_PASS := "pass"
const KIND_FAIL := "fail"
const KIND_TIMEOUT := "timeout"
const KIND_PENDING := "pending"
const KIND_CANCELLED := "cancelled"

const MSG_PASS := "test PASS — 8/8 sim phases"
const MSG_FAIL_INSTANTIATE := "test FAIL — died instantiating objects (3/8), check the game window"
const MSG_TIMEOUT := "no verdict — game may be sitting on a modal dialog"
const MSG_CANCELLED := "test cancelled"

## Tests assign Callable(uri: String) -> int to skip OS.create_process.
static var spawn_steam: Callable = Callable()

var log: Callable = Callable()
var last_verdict: Dictionary = {}

var _active: bool = false
var _waiting_package: bool = false
var _timer: Timer
var _offset: int = 0
var _tail: String = ""
var _log_path: String = ""
var _bzn: String = ""
var _started_ms: int = 0
var _game_root: String = ""


func _ready() -> void:
	Backend.call_finished.connect(_on_call_finished)
	Backend.call_failed.connect(_on_call_failed)
	_ensure_timer()


func _exit_tree() -> void:
	if Backend.call_finished.is_connected(_on_call_finished):
		Backend.call_finished.disconnect(_on_call_finished)
	if Backend.call_failed.is_connected(_on_call_failed):
		Backend.call_failed.disconnect(_on_call_failed)


func is_active() -> bool:
	return _active


static func bzn_name(stem: String, variant: String = "") -> String:
	return "%s%s.bzn" % [stem, variant]


static func steam_run_uri(stem: String, variant: String = "") -> String:
	return steam_run_uri_for_bzn(bzn_name(stem, variant))


static func steam_run_uri_for_bzn(bzn: String) -> String:
	return "steam://run/%s//%s /startedit /win" % [STEAM_APP_ID, bzn]


static func logger_path(game_root: String) -> String:
	return String(game_root).path_join(LOGGER_NAME)


static func file_size_or_zero(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := int(f.get_length())
	f.close()
	return n


## Read only the bytes at `path` past `from_offset`.
## `{ok, offset, bytes, text, truncated}`. Missing file → empty, same offset.
static func read_appended(path: String, from_offset: int) -> Dictionary:
	var start := maxi(from_offset, 0)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {
			"ok": true,
			"offset": start,
			"bytes": PackedByteArray(),
			"text": "",
			"truncated": false,
		}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {
			"ok": false,
			"offset": start,
			"bytes": PackedByteArray(),
			"text": "",
			"truncated": false,
			"error": error_string(FileAccess.get_open_error()),
		}
	var length := int(f.get_length())
	var truncated := false
	if length < start:
		start = 0
		truncated = true
	f.seek(start)
	var buf := f.get_buffer(length - start)
	f.close()
	return {
		"ok": true,
		"offset": length,
		"bytes": buf,
		"text": buf.get_string_from_utf8(),
		"truncated": truncated,
	}


static func count_sim_startup(text: String) -> int:
	var n := 0
	for raw in text.split("\n"):
		if raw.contains(SIM_NEEDLE):
			n += 1
	return n


static func verdict_from_count(count: int, timed_out: bool) -> Dictionary:
	var n := maxi(count, 0)
	if n >= SIM_PHASES:
		return {
			"kind": KIND_PASS,
			"count": n,
			"message": MSG_PASS,
		}
	if not timed_out:
		return {
			"kind": KIND_PENDING,
			"count": n,
			"message": "",
		}
	if n == INSTANTIATE_FAIL_COUNT:
		return {
			"kind": KIND_FAIL,
			"count": n,
			"message": MSG_FAIL_INSTANTIATE,
		}
	return {
		"kind": KIND_TIMEOUT,
		"count": n,
		"message": MSG_TIMEOUT,
	}


static func launch_steam(uri: String) -> int:
	if spawn_steam.is_valid():
		return int(spawn_steam.call(uri))
	return OS.create_process(STEAM_EXE, PackedStringArray([uri]))


func begin() -> bool:
	if _active:
		cancel()
		return false
	if not MapState.has_session:
		_emit_log("open a map to test in game")
		return false
	if Settings.game_root.is_empty():
		_emit_log("probe an install first")
		return false
	if MapState.stem.is_empty():
		_emit_log("map has no stem")
		return false
	if Backend.busy:
		_emit_log("wait for the current backend job to finish")
		return false
	_bzn = bzn_name(MapState.stem, MapState.active_variant)
	_game_root = Settings.game_root
	_log_path = logger_path(_game_root)
	_offset = 0
	_tail = ""
	last_verdict = {}
	_active = true
	_waiting_package = true
	_set_running(true)
	MapState.persist()
	_emit_log("testing %s in game (addon/ + Steam)" % _bzn)
	_set_status("busy", "installing addon for test…")
	Backend.package_addon(MapState.session_dir, Settings.game_root)
	return true


func cancel() -> void:
	if not _active:
		return
	_stop_poll()
	_waiting_package = false
	_active = false
	last_verdict = {
		"kind": KIND_CANCELLED,
		"count": count_sim_startup(_tail),
		"message": MSG_CANCELLED,
	}
	_emit_log(MSG_CANCELLED)
	_set_status("info", MSG_CANCELLED)
	_set_running(false)


func _on_call_finished(verb: String, _result: Dictionary) -> void:
	if not _waiting_package or verb != "package":
		return
	_waiting_package = false
	if not _active:
		return
	_launch_and_poll()


func _on_call_failed(verb: String, _error: Dictionary) -> void:
	if not _waiting_package or verb != "package":
		return
	_waiting_package = false
	if not _active:
		return
	_active = false
	last_verdict = {
		"kind": KIND_FAIL,
		"count": 0,
		"message": "test aborted — addon install failed",
	}
	_emit_log(last_verdict["message"])
	_set_status("error", last_verdict["message"])
	_set_running(false)


func _launch_and_poll() -> void:
	_offset = file_size_or_zero(_log_path)
	_tail = ""
	var uri := steam_run_uri_for_bzn(_bzn)
	var pid := launch_steam(uri)
	if pid < 0:
		_active = false
		last_verdict = {
			"kind": KIND_FAIL,
			"count": 0,
			"message": "could not launch steam (is it on PATH?)",
		}
		_emit_log(last_verdict["message"])
		_set_status("error", last_verdict["message"])
		_set_running(false)
		return
	_started_ms = Time.get_ticks_msec()
	_emit_log("launched %s  pid %d  watching %s" % [uri, pid, _log_path])
	_set_status("busy", "testing in game…")
	_ensure_timer()
	_on_poll()
	if _active and _timer:
		_timer.start()


func _on_poll() -> void:
	if not _active or _waiting_package:
		return
	var chunk := read_appended(_log_path, _offset)
	if bool(chunk.get("truncated", false)):
		_tail = ""
	_offset = int(chunk.get("offset", _offset))
	_tail += str(chunk.get("text", ""))
	var count := count_sim_startup(_tail)
	var timed_out := (Time.get_ticks_msec() - _started_ms) >= int(TIMEOUT_SEC * 1000.0)
	var verdict := verdict_from_count(count, timed_out)
	var kind := str(verdict.get("kind", KIND_PENDING))
	if kind == KIND_PENDING:
		_set_status("busy", "testing in game — %d/%d sim phases" % [count, SIM_PHASES])
		return
	_finish(verdict)


func _finish(verdict: Dictionary) -> void:
	_stop_poll()
	_waiting_package = false
	_active = false
	last_verdict = verdict
	var kind := str(verdict.get("kind", ""))
	var message := str(verdict.get("message", ""))
	_emit_log(message)
	var status_kind := "ok"
	if kind == KIND_PASS:
		status_kind = "ok"
	elif kind == KIND_FAIL:
		status_kind = "error"
	else:
		status_kind = "info"
	_set_status(status_kind, message)
	_set_running(false)


func _stop_poll() -> void:
	if _timer:
		_timer.stop()


func _ensure_timer() -> void:
	if _timer != null:
		return
	_timer = Timer.new()
	_timer.name = "Poll"
	_timer.wait_time = POLL_SEC
	_timer.one_shot = false
	_timer.timeout.connect(_on_poll)
	add_child(_timer)


func _set_running(active: bool) -> void:
	running_changed.emit(active)
	var shell := _shell()
	if shell == null:
		return
	var top: Variant = shell.get("_top")
	if top is Object and (top as Object).has_method("set_testing"):
		(top as Object).call("set_testing", active)


func _emit_log(text: String) -> void:
	if log.is_valid():
		log.call(text)
	else:
		EditorFeedback.log(text)


func _set_status(kind: String, text: String) -> void:
	var shell := _shell()
	if shell == null:
		return
	var status: Variant = shell.get("_status")
	if status is Object and (status as Object).has_method("set_status"):
		(status as Object).call("set_status", kind, text)


func _shell() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("editor_shell")
